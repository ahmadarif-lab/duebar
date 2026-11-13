import AppKit
import Combine
import DueKit
import Foundation

enum Sync {
    static let defaultServer = "https://duebar-api.ahmadarif.id"

    /// How long a sign-in may wait for the person to finish in the browser.
    static let signInTimeout: TimeInterval = 5 * 60

    /// The server the app talks to. Fixed: it receives the Google ID token and the payments,
    /// so it is not a setting. `DUEBAR_SERVER_URL` overrides it for local testing only, and
    /// only for HTTPS or a loopback address.
    static var server: String {
        guard let override = ProcessInfo.processInfo.environment["DUEBAR_SERVER_URL"], let url = URL(string: override),
              url.scheme == "https" || ["127.0.0.1", "localhost", "::1"].contains(url.host ?? "") else { return defaultServer }
        return override
    }
}

/// Talks to the DueBar API: signs in with a Google ID token, then keeps the
/// local ledger and the server's copy converged (push local edits, pull
/// everything newer, last write wins per record).
@MainActor
final class SyncService: ObservableObject {
    enum State: Equatable {
        case signedOut
        case idle
        case syncing
        case failed(String)
    }

    @Published private(set) var state: State = .signedOut
    @Published private(set) var session: AuthSession?
    @Published private(set) var lastSync: Date?
    @Published private(set) var signingIn = false

    private let store: Store
    private let sessionURL: URL
    private var debounce: Task<Void, Never>?
    private var loop: Task<Void, Never>?
    private var inFlight = false
    private var again = false
    private var wakeObserver: NSObjectProtocol?
    private var signInTask: Task<Void, Never>?
    private var signInTimeout: Task<Void, Never>?
    private var signInTimedOut = false
    private var profileRefreshed = false

    init(store: Store, directory: URL = Store.defaultDirectory) {
        self.store = store
        sessionURL = directory.appendingPathComponent("session.json")
        if let data = try? Data(contentsOf: sessionURL), let s = try? JSONDecoder().decode(AuthSession.self, from: data) {
            session = s
            state = .idle
        }
        lastSync = UserDefaults.standard.object(forKey: SettingsKey.lastSync) as? Date
        guard session != nil else { return }
        start()
    }

    var isSignedIn: Bool { session != nil }

    private var client: SyncClient? {
        SyncClient(server: Sync.server)
    }

    // MARK: Account

    /// Starts sign-in in the background. It gives up by itself after `Sync.signInTimeout`
    /// so a forgotten browser tab never leaves the button stuck.
    func startSignIn() {
        guard !signingIn else { return }
        lastError = nil
        signingIn = true
        signInTimedOut = false
        signInTask = Task { await performSignIn() }
        signInTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Sync.signInTimeout))
            guard !Task.isCancelled, let self, self.signingIn else { return }
            self.signInTimedOut = true
            self.signInTask?.cancel()
        }
    }

    func cancelSignIn() { signInTask?.cancel() }

    private func performSignIn() async {
        defer {
            signInTimeout?.cancel()
            signInTask = nil
            signingIn = false
        }
        do {
            guard let client else { throw SyncError.badURL }
            let s: AuthSession
            if let devEmail = ProcessInfo.processInfo.environment["DUEBAR_DEV_EMAIL"], !devEmail.isEmpty {
                s = try await client.devLogin(email: devEmail)   // local testing against a DEV_AUTH server
            } else {
                s = try await client.googleLogin(idToken: try await GoogleAuth.signIn())
            }
            save(session: s)
            UserDefaults.standard.set(s.email, forKey: SettingsKey.syncEmail)
            session = s
            state = .idle
            // First sign-in on this device: send everything it already has.
            store.resetCursorAndPushAll()
            start()
            await syncNow()
        } catch where Self.isCancellation(error) {
            if signInTimedOut {
                lastError = tr("Sign-in took too long and was cancelled. Try again.", "Login terlalu lama dan dibatalkan. Coba lagi.")
            }
        } catch {
            state = session == nil ? .signedOut : .failed(error.localizedDescription)
            lastError = error.localizedDescription
            objectWillChange.send()
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if case GoogleAuth.AuthError.cancelled = error { return true }
        return error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    /// Why the last sign-in attempt failed, while signed out.
    @Published private(set) var lastError: String?

    func signOut() async {
        if let session { try? await client?.logout(token: session.token) }
        clearAuthSession()
    }

    /// Removes the account and its data from the server (kept locally).
    func deleteAccount() async -> Bool {
        guard let session else { return false }
        do {
            try await client?.deleteAccount(token: session.token)
            clearAuthSession()
            return true
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
    }

    private func clearAuthSession() {
        stop()
        profileRefreshed = false
        try? FileManager.default.removeItem(at: sessionURL)
        session = nil
        state = .signedOut
        lastError = nil
        UserDefaults.standard.removeObject(forKey: SettingsKey.syncEmail)
        UserDefaults.standard.removeObject(forKey: SettingsKey.lastSync)
        lastSync = nil
    }

    private func save(session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: sessionURL, options: .atomic)
        // A bearer token: readable by this user only.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sessionURL.path)
    }

    // MARK: Scheduling

    private func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncNow()
                try? await Task.sleep(for: .seconds(300))
            }
        }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.syncNow() }
        }
    }

    private func stop() {
        loop?.cancel(); loop = nil
        debounce?.cancel(); debounce = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    /// Called after every local edit: pushes a moment later, batching bursts.
    func localChanged() {
        guard isSignedIn else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Once per launch: picks up a changed name or photo, and fills in the photo for
    /// sessions saved before the app knew about it.
    private func refreshProfile() async {
        guard !profileRefreshed, var current = session, let client else { return }
        guard let profile = try? await client.me(token: current.token) else { return }
        profileRefreshed = true
        guard profile.email != current.email || profile.name != current.name || profile.picture != current.picture else { return }
        current.email = profile.email
        current.name = profile.name
        current.picture = profile.picture
        save(session: current)
        session = current
        UserDefaults.standard.set(current.email, forKey: SettingsKey.syncEmail)
    }

    // MARK: Sync

    func syncNow() async {
        guard let session else { return }
        if inFlight { again = true; return }
        inFlight = true
        state = .syncing
        defer { inFlight = false }
        do {
            guard let client else { throw SyncError.badURL }
            let store = self.store
            repeat {
                again = false
                try await client.sync(
                    token: session.token,
                    snapshot: { (store.ledger.cursor, store.ledger.pendingChanges()) },
                    apply: { reply, pushed in store.applyRemote(reply.changes, cursor: reply.cursor, pushed: pushed) }
                )
            } while again
            await refreshProfile()
            lastSync = Date()
            UserDefaults.standard.set(lastSync, forKey: SettingsKey.lastSync)
            state = .idle
            store.onChangeAfterRemote?()
        } catch SyncError.unauthorized {
            clearAuthSession()
            lastError = tr("Your session expired. Sign in again to keep syncing.", "Sesi habis. Login lagi untuk melanjutkan sinkron.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
