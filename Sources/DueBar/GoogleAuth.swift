import AppKit
import CryptoKit
import DueKit
import Foundation

/// Google sign-in for a desktop app: the system browser, PKCE and a
/// loopback redirect (RFC 8252). The result is a Google ID token, which the
/// DueBar API trades for its own session; Google's access/refresh tokens
/// are never kept.
enum GoogleAuth {
    enum AuthError: LocalizedError {
        case notConfigured, cancelled, denied(String), exchangeFailed(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return tr("Google sign-in isn't configured in this build.", "Login Google belum dikonfigurasi di build ini.")
            case .cancelled: return tr("Sign-in was cancelled.", "Login dibatalkan.")
            case .denied(let why): return tr("Google refused the sign-in: \(why)", "Google menolak login: \(why)")
            case .exchangeFailed(let why): return tr("Couldn't finish sign-in: \(why)", "Gagal menyelesaikan login: \(why)")
            }
        }
    }

    /// Desktop-type OAuth client. Google's own docs say the "secret" of an
    /// installed-app client isn't confidential; it ships in Info.plist.
    static var clientID: String? { value("GoogleClientID", env: "DUEBAR_GOOGLE_CLIENT_ID") }
    private static var clientSecret: String? { value("GoogleClientSecret", env: "DUEBAR_GOOGLE_CLIENT_SECRET") }
    static var isConfigured: Bool { clientID != nil }

    private static func value(_ key: String, env: String) -> String? {
        if let v = ProcessInfo.processInfo.environment[env], !v.isEmpty { return v }
        if let v = Bundle.main.infoDictionary?[key] as? String, !v.isEmpty, !v.hasPrefix("$(") { return v }
        return nil
    }

    @MainActor
    static func signIn() async throws -> String {
        guard let clientID else { throw AuthError.notConfigured }
        let verifier = randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = randomString(24)

        let server = LoopbackServer(page: { ok in GoogleAuth.page(ok: ok) })
        let port = try await server.start()
        let redirect = "http://127.0.0.1:\(port)"

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "prompt", value: "select_account"),
        ]
        NSWorkspace.shared.open(comps.url!)

        // Cancelling the surrounding task (the Cancel button, or the 5-minute limit set by the
        // caller) ends the wait immediately: the loopback listener is closed and sign-in can be retried.
        let query: [String: String]
        do {
            query = try await withTaskCancellationHandler {
                try await server.waitForRedirect()
            } onCancel: {
                server.cancel()
            }
        } catch is LoopbackServer.Cancelled {
            throw AuthError.cancelled
        }
        guard query["state"] == state else { throw AuthError.exchangeFailed("state mismatch") }
        if let error = query["error"] { throw error == "access_denied" ? AuthError.cancelled : AuthError.denied(error) }
        guard let code = query["code"] else { throw AuthError.exchangeFailed("no code") }

        var form = [
            "client_id": clientID, "code": code, "code_verifier": verifier,
            "redirect_uri": redirect, "grant_type": "authorization_code",
        ]
        if let clientSecret { form["client_secret"] = clientSecret }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (response as? HTTPURLResponse)?.statusCode == 200, let idToken = json?["id_token"] as? String else {
            throw AuthError.exchangeFailed((json?["error_description"] as? String) ?? (json?["error"] as? String) ?? "HTTP error")
        }
        return idToken
    }

    private static func randomString(_ length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64URL.prefix(length).description
    }

    fileprivate static func page(ok: Bool) -> String {
        let title = ok ? tr("You're signed in", "Berhasil masuk") : tr("Sign-in failed", "Login gagal")
        let hint = ok ? tr("You can close this tab and return to DueBar.", "Tab ini boleh ditutup, kembali ke DueBar.") : tr("Return to DueBar and try again.", "Kembali ke DueBar dan coba lagi.")
        return """
        <!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>DueBar</title><style>
        body{font:16px -apple-system,system-ui,sans-serif;display:grid;place-items:center;height:100vh;margin:0;background:#1c1c1e;color:#fff}
        div{text-align:center}h1{font-size:22px;margin:.4em 0}p{color:#a1a1a6}b{font-size:46px}
        @media(prefers-color-scheme:light){body{background:#f2f2f7;color:#1d1d1f}p{color:#6e6e73}}
        </style><div><b>\(ok ? "✓" : "✕")</b><h1>\(title)</h1><p>\(hint)</p></div>
        """
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}