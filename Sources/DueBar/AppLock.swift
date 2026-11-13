import AppKit
import DueKit
import LocalAuthentication
import SwiftUI

/// DueBar's two optional locks, independent of each other: a master password (shared by every device
/// signed in to the account, so Android can use the same one) and Touch ID (this Mac only). Either one
/// turns the lock on, or both. While locked, the dropdown, Settings and the editor stay blurred until
/// the password is typed or Touch ID succeeds.
///
/// The password itself is never stored: only a salted hash, in `lock.json`, which the sync engine
/// copies to and from the account. This is a screen lock, not file encryption: it keeps
/// shoulder-surfers and anyone who sits down at an unlocked Mac away from the numbers.
@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    /// How long the app may stay closed before it asks again; 0 means every time it opens.
    static let timeoutChoices = [0, 5, 15, 60]
    static let timeoutKey = "lockTimeoutMinutes"
    /// Mirrors `isEnabled` for code that only needs to know whether to keep amounts out of notifications.
    static let enabledKey = "lockEnabled"
    static let biometricsKey = "lockBiometrics"

    /// A master password is set (here or from another device).
    @Published private(set) var hasPassword: Bool
    @Published private(set) var isLocked: Bool
    /// Set after too many wrong passwords: no attempts until then.
    @Published private(set) var retryAt: Date?
    var onEnabledChange: (() -> Void)?
    /// Called when this Mac changed the password, so the sync engine can send it to the account.
    var onPasswordChange: (() -> Void)?
    /// True while a system sheet (Touch ID, the Mac password) is up. It takes key status from the
    /// dropdown, which must not read that as a click away and close.
    private(set) var isAuthenticating = false

    private var verifier: PasswordVerifier?
    /// The server's timestamp of the password version this Mac has.
    private var updatedAt: Int64 = 0
    /// This Mac changed the password and the account hasn't heard yet.
    private(set) var dirty = false
    /// The Google account the password belongs to. Another account never replaces or removes it.
    private(set) var owner: String?
    private var failures = 0
    private var leftAt: Date?
    private let fileURL: URL

    private struct Stored: Codable {
        var verifier: PasswordVerifier?
        var updatedAt: Int64?
        var dirty: Bool?
        var owner: String?
    }

    init(directory: URL = Store.defaultDirectory) {
        fileURL = directory.appendingPathComponent("lock.json")
        if let data = try? Data(contentsOf: fileURL), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            verifier = stored.verifier
            updatedAt = stored.updatedAt ?? 0
            dirty = stored.dirty ?? false
            owner = stored.owner
        }
        hasPassword = verifier != nil
        let touch = UserDefaults.standard.bool(forKey: Self.biometricsKey) && Self.biometricsAvailable
        isLocked = verifier != nil || touch
        UserDefaults.standard.set(isLocked, forKey: Self.enabledKey)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lock() }
            }
        }
    }

    /// Either lock is on.
    var isEnabled: Bool { hasPassword || useBiometrics }

    var timeoutMinutes: Int {
        get { UserDefaults.standard.object(forKey: Self.timeoutKey) as? Int ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: Self.timeoutKey); objectWillChange.send() }
    }

    // MARK: Locking

    func lock() { if isEnabled { isLocked = true } }

    /// Called when the dropdown opens: locks again if it was closed long enough. A window that is
    /// already open and unlocked stays usable, so opening Settings from the dropdown asks only once.
    func noteOpened(windowOpen: Bool) {
        guard isEnabled, !isLocked else { return }
        let away = leftAt.map { Date().timeIntervalSince($0) } ?? .infinity
        if timeoutMinutes == 0 ? !windowOpen : away >= Double(timeoutMinutes) * 60 { isLocked = true }
    }

    func noteClosed() { leftAt = Date() }

    /// True when the password was right.
    func unlock(_ password: String) -> Bool {
        guard let verifier, canTry else { return false }
        if verifier.matches(password) {
            failures = 0
            retryAt = nil
            isLocked = false
            return true
        }
        failures += 1
        if failures >= 5 { retryAt = Date().addingTimeInterval(min(30 * pow(2, Double(failures - 5)), 900)) }
        return false
    }

    var canTry: Bool { retryAt.map { $0 <= Date() } ?? true }

    func matches(_ password: String) -> Bool { verifier?.matches(password) ?? false }

    // MARK: Touch ID and Mac password

    static var biometricsAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Snapshots only (kept out of the preferences).
    private var previewTouchOnly = false

    var useBiometrics: Bool {
        get { previewTouchOnly || (UserDefaults.standard.bool(forKey: Self.biometricsKey) && Self.biometricsAvailable) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.biometricsKey)
            UserDefaults.standard.set(hasPassword || newValue, forKey: Self.enabledKey)
            if !isEnabled { isLocked = false }
            objectWillChange.send()
            onEnabledChange?()
        }
    }

    /// Asks macOS for Touch ID, or with `allowPassword` for the Mac's login password (the system sheet may
    /// also offer Touch ID there; that is macOS's own prompt).
    private func authenticate(reason: String, allowPassword: Bool) async -> Bool {
        let context = LAContext()
        if !allowPassword { context.localizedFallbackTitle = "" }   // no "Enter Password" button: DueBar has its own field
        isAuthenticating = true
        defer { isAuthenticating = false }
        let policy: LAPolicy = allowPassword ? .deviceOwnerAuthentication : .deviceOwnerAuthenticationWithBiometrics
        return (try? await context.evaluatePolicy(policy, localizedReason: reason)) ?? false
    }

    /// Unlock with a fingerprint, when the person turned that on.
    func unlockWithBiometrics() async {
        guard isLocked, useBiometrics, !isAuthenticating else { return }
        if await authenticate(reason: tr("Unlock DueBar", "Buka kunci DueBar"), allowPassword: false) { isLocked = false; failures = 0; retryAt = nil }
    }

    /// Checks that Touch ID works before turning it on.
    func enableBiometrics() async {
        if await authenticate(reason: tr("Use Touch ID to unlock DueBar", "Pakai Touch ID untuk membuka DueBar"), allowPassword: false) { useBiometrics = true }
    }

    /// With Touch ID as the only lock there is no password to fall back on: the Mac's login password opens it.
    func unlockWithMacPassword() async {
        guard isLocked, !isAuthenticating else { return }
        if await authenticate(reason: tr("Unlock DueBar", "Buka kunci DueBar"), allowPassword: true) { isLocked = false; failures = 0; retryAt = nil }
    }

    /// The server confirmed the emailed code: the only way back in after forgetting the password.
    func resetConfirmedByEmail() { removePassword() }

    // MARK: Password

    func setPassword(_ password: String, owner: String) {
        verifier = PasswordVerifier.make(password: password)
        self.owner = owner
        changed()
    }

    func removePassword() {
        verifier = nil
        changed()
    }

    private func changed() {
        dirty = true
        hasPassword = verifier != nil
        isLocked = false
        failures = 0
        retryAt = nil
        persist()
        UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        onEnabledChange?()
        onPasswordChange?()
    }

    // MARK: Account sync

    var verifierToSync: PasswordVerifier? { verifier }

    /// The account accepted this Mac's change.
    func markPushed(updatedAt: Int64) {
        self.updatedAt = updatedAt
        dirty = false
        persist()
    }

    /// The account's version of the password. Taken when this Mac has no unsent change of its own and
    /// the account's differs; a password that appears here for the first time locks the app at once.
    func adopt(verifier remote: PasswordVerifier?, updatedAt remoteUpdatedAt: Int64, email: String) {
        guard !dirty, remoteUpdatedAt != updatedAt else { return }
        // A different Google account signing in here has no say over this Mac's password.
        if let owner, owner != email { return }
        owner = remote != nil ? email : nil
        let hadPassword = hasPassword
        verifier = remote
        updatedAt = remoteUpdatedAt
        hasPassword = remote != nil
        if remote != nil, !hadPassword { isLocked = true }
        if remote == nil, !useBiometrics { isLocked = false }
        persist()
        UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        onEnabledChange?()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(Stored(verifier: verifier, updatedAt: updatedAt, dirty: dirty, owner: owner)) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Snapshots only: the locked screen with Touch ID as the only lock.
    func setForPreviewTouchOnly() {
        previewTouchOnly = true
        verifier = nil
        hasPassword = false
        isLocked = true
    }

    /// Snapshots only: show the locked screen without touching the user's real lock file.
    func setForPreview(password: String) {
        verifier = PasswordVerifier.make(password: password, iterations: 1_000)
        hasPassword = true
        isLocked = true
    }
}

// MARK: - Views

/// A password field with an eye button to show or hide what was typed.
struct PasswordField: View {
    var prompt: String
    @Binding var text: String
    var centered = false
    @State private var shown = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if shown { TextField(prompt, text: $text) } else { SecureField(prompt, text: $text) }
            }
            .textFieldStyle(.plain)
            .multilineTextAlignment(centered ? .center : .leading)
            .focused($focused)
            Button {
                shown.toggle()
                DispatchQueue.main.async { focused = true }
            } label: {
                Image(systemName: shown ? "eye.slash" : "eye").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(shown ? tr("Hide password", "Sembunyikan password") : tr("Show password", "Tampilkan password"))
            .accessibilityLabel(shown ? tr("Hide password", "Sembunyikan password") : tr("Show password", "Tampilkan password"))
        }
        .padding(.vertical, 7).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(focused ? 0.3 : 0.1)))
    }
}

/// Blurs what it wraps and asks for the password while the app is locked.
private struct LockGate: ViewModifier {
    @ObservedObject private var lock = AppLock.shared

    func body(content: Content) -> some View {
        content
            .frame(minHeight: lock.isLocked ? 250 : nil)
            // Text becomes grey bars before it is blurred, so nothing readable is left behind the blur.
            .redacted(reason: lock.isLocked ? .placeholder : [])
            .blur(radius: lock.isLocked ? 7 : 0)
            .allowsHitTesting(!lock.isLocked)
            .accessibilityHidden(lock.isLocked)
            .overlay { if lock.isLocked { LockPrompt().transition(.opacity) } }
            .animation(.easeOut(duration: 0.15), value: lock.isLocked)
    }
}

extension View {
    /// Hides the content behind the master password while the app is locked.
    func lockGated() -> some View { modifier(LockGate()) }
}

private struct LockPrompt: View {
    private enum Step { case password, forgot, code }
    /// Snapshots can start on a later step (DUEBAR_SNAPSHOT_LOCK_STEP=forgot|code).
    private static var firstStep: Step {
        switch ProcessInfo.processInfo.environment["DUEBAR_SNAPSHOT_LOCK_STEP"] { case "forgot": return .forgot; case "code": return .code; default: return .password }
    }

    @ObservedObject private var lock = AppLock.shared
    @EnvironmentObject private var sync: SyncService
    @State private var step = LockPrompt.firstStep
    @State private var password = ""
    @State private var code = ""
    @State private var message: String?
    @State private var busy = false
    @State private var now = Date()
    @FocusState private var focused: Bool
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var waiting: Int? {
        guard let retryAt = lock.retryAt, retryAt > now else { return nil }
        return Int(retryAt.timeIntervalSince(now).rounded(.up))
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Brand.orange.opacity(0.16)).frame(width: 46, height: 46)
                Image(systemName: "lock.fill").font(.system(size: 19, weight: .semibold)).foregroundStyle(Brand.orange)
            }
            switch step {
            case .password: passwordStep
            case .forgot: forgotStep
            case .code: codeStep
            }
        }
        .padding(22)
        .frame(maxWidth: 270)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .onAppear { focused = true; Task { await lock.unlockWithBiometrics() } }
        .onReceive(tick) { now = $0 }
    }

    private func field(_ prompt: String, text: Binding<String>, secure: Bool = true, action: @escaping () -> Void) -> some View {
        Group {
            if secure { SecureField(prompt, text: text) } else { TextField(prompt, text: text) }
        }
        .textFieldStyle(.plain)
        .multilineTextAlignment(.center)
        .padding(.vertical, 7).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.08)))
        .frame(width: 210)
        .focused($focused)
        .onSubmit(action)
    }

    private var error: some View {
        Group {
            if let message { Text(message).foregroundStyle(.red) }
        }
        .font(.system(size: 12)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Steps

    private var passwordStep: some View {
        Group {
            Text(tr("DueBar is locked", "DueBar terkunci")).font(.system(size: 15, weight: .semibold))
            if lock.hasPassword {
                PasswordField(prompt: tr("Master password", "Password master"), text: $password, centered: true)
                    .frame(width: 220)
                    .onSubmit(submit)
                    .disabled(waiting != nil)
                if let waiting {
                    Text(tr("Too many tries. Wait \(waiting) s.", "Terlalu banyak percobaan. Tunggu \(waiting) dtk."))
                        .font(.system(size: 12)).foregroundStyle(.red)
                } else { error }
                HStack(spacing: 8) {
                    PillButton(title: tr("Unlock", "Buka kunci"), symbol: "lock.open", action: submit)
                        .disabled(waiting != nil || password.isEmpty)
                    if lock.useBiometrics { touchIDButton }
                }
                Button(tr("Forgot password?", "Lupa password?")) { message = nil; step = .forgot }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                // Touch ID is the only lock: no password to type, so the Mac's login password is the way back in.
                PillButton(title: tr("Unlock with Touch ID", "Buka dengan Touch ID"), symbol: "touchid") { Task { await lock.unlockWithBiometrics() } }
                Button(tr("Use my Mac password", "Pakai password Mac")) { Task { await lock.unlockWithMacPassword() } }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var touchIDButton: some View {
        Button { Task { await lock.unlockWithBiometrics() } } label: {
            Image(systemName: "touchid").font(.system(size: 20)).foregroundStyle(Brand.orange).frame(width: 30, height: 30)
        }
        .buttonStyle(.plain).help(tr("Unlock with Touch ID", "Buka dengan Touch ID"))
    }

    private var forgotStep: some View {
        Group {
            Text(tr("Reset master password", "Reset password master")).font(.system(size: 15, weight: .semibold))
            if let email = sync.session?.email, lock.owner == nil || lock.owner == email {
                Text(tr("We email a 6-digit code to your account. Enter it and the password is removed on every device; your payments are kept and you can set a new password in Settings.",
                        "Kode 6 digit dikirim ke emailmu. Masukkan kode itu dan password dihapus di semua perangkat; data pembayaran tetap ada dan password baru bisa diatur di Pengaturan."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                error
                PillButton(title: tr("Email a code to \(Self.mask(email))", "Kirim kode ke \(Self.mask(email))"), symbol: "envelope") { sendCode() }
                    .disabled(busy)
            } else if let email = sync.session?.email {
                Text(tr("This password belongs to another Google account (\(Self.mask(lock.owner ?? ""))), not \(Self.mask(email)). Sign out and sign in with that account.",
                        "Password ini milik akun Google lain (\(Self.mask(lock.owner ?? ""))), bukan \(Self.mask(email)). Keluar lalu masuk dengan akun itu."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                PillButton(title: tr("Sign out", "Keluar"), symbol: "rectangle.portrait.and.arrow.right") { Task { await sync.signOut() } }
            } else {
                Text(tr("The code goes to the Google account that owns the password\(Self.ownerSuffix(lock.owner)). Sign in with it first.",
                        "Kode dikirim ke akun Google pemilik password\(Self.ownerSuffix(lock.owner)). Masuk dulu dengan akun itu."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                PillButton(title: tr("Sign in with Google", "Masuk dengan Google"), symbol: "person.crop.circle") { sync.startSignIn() }
                    .disabled(sync.signingIn || !GoogleAuth.isConfigured)
            }
            Button(tr("Back", "Kembali")) { message = nil; step = .password }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var codeStep: some View {
        Group {
            Text(tr("Enter the code", "Masukkan kode")).font(.system(size: 15, weight: .semibold))
            Text(tr("We emailed a 6-digit code to \(Self.mask(sync.session?.email ?? "")). It works for 15 minutes.",
                    "Kode 6 digit dikirim ke \(Self.mask(sync.session?.email ?? "")). Berlaku 15 menit."))
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            field("000000", text: $code, secure: false, action: confirmCode)
            error
            PillButton(title: tr("Remove password", "Hapus password"), symbol: "checkmark", action: confirmCode)
                .disabled(code.count < 6 || busy)
            Button(tr("Back", "Kembali")) { message = nil; code = ""; step = .forgot }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func submit() {
        guard !password.isEmpty else { return }
        if lock.unlock(password) { password = ""; message = nil } else { message = tr("Wrong password.", "Password salah."); password = "" }
        now = Date()
    }

    private func sendCode() {
        busy = true; message = nil
        Task {
            if let failure = await sync.requestLockReset() { message = failure } else { code = ""; step = .code }
            busy = false
        }
    }

    private func confirmCode() {
        guard code.count >= 6 else { return }
        busy = true; message = nil
        Task {
            if let failure = await sync.confirmLockReset(code: code) { message = failure; code = "" } else { lock.resetConfirmedByEmail() }
            busy = false
        }
    }

    private static func ownerSuffix(_ owner: String?) -> String {
        guard let owner, !owner.isEmpty else { return "" }
        return " (\(mask(owner)))"
    }

    /// a***@gmail.com
    private static func mask(_ email: String) -> String {
        guard let at = email.firstIndex(of: "@"), at != email.startIndex else { return email }
        return "\(email[email.startIndex])***\(email[at...])"
    }
}

// MARK: - Settings

/// Set, change or remove the master password.
struct MasterPasswordSheet: View {
    enum Mode { case set, change, remove }
    var mode: Mode
    var done: () -> Void
    @ObservedObject private var lock = AppLock.shared
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var error: String?
    @EnvironmentObject private var sync: SyncService

    private var needsCurrent: Bool { mode != .set }
    private var needsNew: Bool { mode != .remove }

    private var title: String {
        switch mode {
        case .set: return tr("Set master password", "Atur password master")
        case .change: return tr("Change master password", "Ganti password master")
        case .remove: return tr("Remove master password", "Hapus password master")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 15, weight: .semibold))
            if mode == .set {
                Text(tr("DueBar stays blurred until you type it. It is saved to your account, so DueBar on your other devices asks for the same password. If you forget it, a code is emailed to your account.",
                        "DueBar tetap buram sampai password diketik. Password disimpan di akunmu, jadi DueBar di perangkat lain meminta password yang sama. Kalau lupa, kode dikirim ke emailmu."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 8) {
                if needsCurrent { PasswordField(prompt: tr("Current password", "Password saat ini"), text: $current) }
                if needsNew {
                    PasswordField(prompt: tr("New password", "Password baru"), text: $new)
                    PasswordField(prompt: tr("Repeat new password", "Ulangi password baru"), text: $confirm)
                }
            }
            .onSubmit(save)
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(tr("Cancel", "Batal"), action: done).keyboardShortcut(.cancelAction)
                Button(mode == .remove ? tr("Remove", "Hapus") : tr("Save", "Simpan"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled((needsCurrent && current.isEmpty) || (needsNew && new.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 330)
    }

    private func save() {
        if needsCurrent, !lock.matches(current) { error = tr("The current password is wrong.", "Password saat ini salah."); return }
        if needsNew {
            guard new == confirm else { error = tr("The two passwords don't match.", "Kedua password tidak sama."); return }
            lock.setPassword(new, owner: sync.session?.email ?? "")
        } else {
            lock.removePassword()
        }
        done()
    }
}

/// The Privacy section of Settings → General.
struct PrivacySection: View {
    @ObservedObject private var lock = AppLock.shared
    @EnvironmentObject private var sync: SyncService
    @State private var sheet: SheetItem?

    var body: some View {
        SettingsGroup(tr("Privacy", "Privasi")) {
            SettingsRow(tr("Master password", "Password master")) {
                HStack(spacing: 8) {
                    if lock.hasPassword {
                        PillButton(title: tr("Change", "Ganti"), symbol: "key") { sheet = SheetItem(mode: .change) }
                        PillButton(title: tr("Remove", "Hapus"), symbol: "trash") { sheet = SheetItem(mode: .remove) }
                    } else {
                        PillButton(title: tr("Set", "Atur"), symbol: "lock") { sheet = SheetItem(mode: .set) }
                            .disabled(!sync.isSignedIn)
                    }
                }
            }
            SettingsNote {
                Text(lock.hasPassword
                     ? tr("Saved to your account, so every device you sign in on asks for the same password. If you forget it, a code is emailed to your account.",
                          "Disimpan di akunmu, jadi semua perangkat yang kamu masuki meminta password yang sama. Kalau lupa, kode dikirim ke emailmu.")
                     : sync.isSignedIn
                     ? tr("Optional. Blurs names and amounts until you type the password. It is saved to your account and shared with your other devices, Android later included.",
                          "Opsional. Membuat nama dan nominal buram sampai password diketik. Disimpan di akunmu dan dipakai di perangkat lain, termasuk Android nanti.")
                     : tr("Sign in with Google first (Account tab): the password is saved to your account so every device shares it, and a forgotten one is reset by email.",
                          "Masuk dengan Google dulu (tab Account): password disimpan di akunmu agar dipakai semua perangkat, dan yang lupa direset lewat email."))
            }
            if AppLock.biometricsAvailable {
                SettingsRow(tr("Touch ID", "Touch ID")) {
                    SettingsSwitch(isOn: Binding(
                        get: { lock.useBiometrics },
                        set: { on in if on { Task { await lock.enableBiometrics() } } else { lock.useBiometrics = false } }
                    ))
                }
                SettingsNote {
                    Text(tr("Locks DueBar on its own, or opens it faster when there is a master password too. This setting stays on this Mac.",
                            "Mengunci DueBar tanpa password master, atau membukanya lebih cepat jika ada password master. Pengaturan ini hanya di Mac ini."))
                }
            }
            if lock.isEnabled {
                SettingsRow(tr("Ask again", "Minta lagi")) {
                    SettingsMenu(selection: Binding(get: { lock.timeoutMinutes }, set: { lock.timeoutMinutes = $0 }),
                                 options: AppLock.timeoutChoices.map { ($0, Self.label($0)) })
                }
                SettingsRow(tr("Lock now", "Kunci sekarang")) {
                    PillButton(title: tr("Lock", "Kunci"), symbol: "lock.fill") { lock.lock() }
                }
                SettingsNote {
                    Text(tr("It also locks when the Mac sleeps or locks, and reminders then leave the amount out.",
                            "Juga terkunci saat Mac tidur atau terkunci, dan pengingat tidak menampilkan nominal."))
                }
            }
        }
        .sheet(item: $sheet) { item in
            MasterPasswordSheet(mode: item.mode) { sheet = nil }
        }
    }

    private static func label(_ minutes: Int) -> String {
        switch minutes {
        case 0: return tr("Every time it opens", "Setiap kali dibuka")
        case 60: return tr("After 1 hour away", "Setelah 1 jam ditinggal")
        default: return tr("After \(minutes) min away", "Setelah \(minutes) menit ditinggal")
        }
    }

    private struct SheetItem: Identifiable {
        var mode: MasterPasswordSheet.Mode
        var id: Int { switch mode { case .set: return 0; case .change: return 1; case .remove: return 2 } }
    }
}
