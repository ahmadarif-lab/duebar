import DueKit
import Foundation
import UserNotifications

/// Turns the reminder plan into local notifications, with "Mark as paid"
/// and "Snooze" buttons. Each device schedules its own from synced data, so
/// no push server is involved.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let store: Store
    private var center: UNUserNotificationCenter? {
        // A bare `swift run` binary has no bundle, and UserNotifications asserts there.
        Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil
    }

    static let paidAction = "paid"
    static let snoozeAction = "snooze"
    static let categoryID = "payment"

    init(store: Store) {
        self.store = store
        super.init()
        guard let center else { return }
        center.delegate = self
        let paid = UNNotificationAction(identifier: Self.paidAction, title: tr("Mark as paid", "Tandai lunas"), options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: tr("Remind in 1 hour", "Ingatkan 1 jam lagi"), options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [paid, snooze], intentIdentifiers: [], options: []),
        ])
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func authorizationStatus() async -> UNAuthorizationStatus? {
        await center?.notificationSettings().authorizationStatus
    }

    private var lastPlan: [PlannedReminder] = []

    /// Replaces the pending reminders with a fresh plan (snoozes are kept).
    /// Skipped when nothing in the plan changed, so a routine sync is free.
    func reschedule(force: Bool = false) {
        guard let center else { return }
        let enabled = UserDefaults.standard.bool(forKey: SettingsKey.notificationsOn)
        let plan = enabled ? ReminderPlanner.plan(payments: store.ledger.allPayments) : []
        guard force || plan != lastPlan else { return }
        lastPlan = plan
        Task {
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { !$0.hasPrefix("snooze|") })
            for item in plan {
                let content = UNMutableNotificationContent()
                content.title = item.name
                content.body = Self.body(item)
                content.sound = .default
                content.categoryIdentifier = Self.categoryID
                content.userInfo = ["paymentID": item.paymentID]
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: "\(item.paymentID)|\(item.due)|\(item.offset)|\(Int(item.fire.timeIntervalSince1970))", content: content, trigger: trigger))
            }
        }
    }

    private static func body(_ r: PlannedReminder) -> String {
        // With a master password on, a reminder on the lock screen shouldn't show the amount.
        let amount = UserDefaults.standard.bool(forKey: AppLock.enabledKey) ? tr("Payment", "Pembayaran") : Money.format(r.amount, currency: r.currency)
        if r.offset < 0 { return tr("\(amount) is overdue since \(DueText.date(r.due)).", "\(amount) sudah lewat jatuh tempo sejak \(DueText.date(r.due)).") }
        switch r.offset {
        case 0: return tr("\(amount) is due today.", "\(amount) jatuh tempo hari ini.")
        case 1: return tr("\(amount) is due tomorrow.", "\(amount) jatuh tempo besok.")
        default: return tr("\(amount) is due in \(r.offset) days (\(DueText.date(r.due))).", "\(amount) jatuh tempo \(r.offset) hari lagi (\(DueText.date(r.due))).")
        }
    }

    // MARK: Delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["paymentID"] as? String else { return }
        let action = response.actionIdentifier
        let content = response.notification.request.content
        await MainActor.run {
            switch action {
            case Self.paidAction:
                store.resolve(id, .paid)
            case Self.snoozeAction:
                let snooze = UNMutableNotificationContent()
                snooze.title = content.title
                snooze.body = content.body
                snooze.sound = .default
                snooze.categoryIdentifier = Self.categoryID
                snooze.userInfo = content.userInfo
                self.center?.add(UNNotificationRequest(
                    identifier: "snooze|\(id)|\(Date().timeIntervalSince1970)", content: snooze,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)))
            default:
                NotificationCenter.default.post(name: .openDueBarPanel, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let openDueBarPanel = Notification.Name("openDueBarPanel")
}
