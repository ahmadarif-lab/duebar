import Foundation

public struct AuthSession: Codable, Equatable, Sendable {
    public var token: String
    public var email: String
    public var name: String
    /// Google profile photo URL; empty when there is none.
    public var picture: String

    public init(token: String, email: String, name: String, picture: String = "") {
        self.token = token
        self.email = email
        self.name = name
        self.picture = picture
    }

    // A session file written before `picture` existed still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decode(String.self, forKey: .token)
        email = try c.decode(String.self, forKey: .email)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        picture = try c.decodeIfPresent(String.self, forKey: .picture) ?? ""
    }
}

public struct AccountProfile: Decodable, Equatable, Sendable {
    public var email: String
    public var name: String
    public var picture: String

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        email = try c.decode(String.self, forKey: .email)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        picture = try c.decodeIfPresent(String.self, forKey: .picture) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case email, name, picture }
}

public struct SyncReply: Decodable, Sendable {
    public var cursor: Int64
    public var more: Bool
    public var changes: [SyncRecord]
}

public enum SyncError: LocalizedError, Equatable {
    case unauthorized
    case server(String)
    case badURL

    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "Unauthorized"
        case .server(let m): return m
        case .badURL: return "The server URL is invalid."
        }
    }
}

/// HTTP client for the DueBar API. Platform-neutral so it can be tested
/// against a real server; the app wraps it with state and scheduling.
public struct SyncClient: Sendable {
    public var baseURL: URL
    private let urlSession: URLSession

    public init?(server: String, urlSession: URLSession = .shared) {
        guard let url = URL(string: server.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))) else { return nil }
        baseURL = url
        self.urlSession = urlSession
    }

    private struct AuthReply: Decodable {
        var token: String
        var user: AccountProfile
    }
    private struct Request: Encodable { var cursor: Int64; var changes: [SyncRecord] }

    public func googleLogin(idToken: String) async throws -> AuthSession {
        let r: AuthReply = try decode(await send("POST", "/v1/auth/google", json: ["idToken": idToken], token: nil))
        return AuthSession(token: r.token, email: r.user.email, name: r.user.name, picture: r.user.picture)
    }

    /// Only works against a server started with DEV_AUTH=1 (local testing).
    public func devLogin(email: String) async throws -> AuthSession {
        let r: AuthReply = try decode(await send("POST", "/v1/auth/dev", json: ["email": email], token: nil))
        return AuthSession(token: r.token, email: r.user.email, name: r.user.name, picture: r.user.picture)
    }

    /// The signed-in account's current name, email and photo.
    public func me(token: String) async throws -> AccountProfile {
        try decode(await send("GET", "/v1/me", body: nil, token: token))
    }

    public func logout(token: String) async throws { _ = try await send("POST", "/v1/logout", json: [String: String](), token: token) }
    public func deleteAccount(token: String) async throws { _ = try await send("DELETE", "/v1/account", json: nil as [String: String]?, token: token) }

    /// The account's master password (a salted hash, never the password) so every device shares it.
    public struct RemoteLock: Codable, Equatable, Sendable {
        public var verifier: PasswordVerifier?
        public var updatedAt: Int64
    }

    public func fetchLock(token: String) async throws -> RemoteLock {
        try decode(await send("GET", "/v1/lock", body: nil, token: token))
    }

    /// Stores the verifier (nil removes it); returns the server's timestamp for the change.
    public func putLock(token: String, verifier: PasswordVerifier?) async throws -> Int64 {
        struct Reply: Decodable { var updatedAt: Int64 }
        if let verifier {
            struct Body: Encodable { var verifier: PasswordVerifier }
            let reply: Reply = try decode(await send("PUT", "/v1/lock", json: Body(verifier: verifier), token: token))
            return reply.updatedAt
        }
        let reply: Reply = try decode(await send("DELETE", "/v1/lock", json: nil as [String: String]?, token: token))
        return reply.updatedAt
    }

    /// "Forgot master password": the server emails a one-time code to the account's address
    /// (at most one a minute and two a day), and the app then confirms the code the person typed.
    public func requestLockReset(token: String) async throws {
        _ = try await send("POST", "/v1/lock/reset/request", json: [String: String](), token: token)
    }

    public func confirmLockReset(token: String, code: String) async throws {
        _ = try await send("POST", "/v1/lock/reset/confirm", json: ["code": code], token: token)
    }

    public func exchange(token: String, cursor: Int64, changes: [SyncRecord]) async throws -> SyncReply {
        try decode(await send("POST", "/v1/sync", body: try JSONEncoder().encode(Request(cursor: cursor, changes: changes)), token: token))
    }

    /// Pushes local changes and pulls remote ones until the server has nothing more.
    /// `snapshot` is read fresh each round; `apply` receives what was pushed so
    /// the caller can mark it as sent.
    public func sync(
        token: String,
        snapshot: () async -> (cursor: Int64, pending: [SyncRecord]),
        apply: (SyncReply, [SyncRecord]) async -> Void
    ) async throws {
        var more = true
        while more {
            let (cursor, pending) = await snapshot()
            let reply = try await exchange(token: token, cursor: cursor, changes: pending)
            await apply(reply, pending)
            more = reply.more
        }
    }

    // MARK: HTTP

    private func send<B: Encodable>(_ method: String, _ path: String, json: B?, token: String?) async throws -> Data {
        try await send(method, path, body: json.map { try? JSONEncoder().encode($0) } ?? nil, token: token)
    }

    private func send(_ method: String, _ path: String, body: Data?, token: String?) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw SyncError.badURL }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await urlSession.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 && token != nil { throw SyncError.unauthorized }
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw SyncError.server(message ?? "HTTP \(status)")
        }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T { try JSONDecoder().decode(T.self, from: data) }
}
