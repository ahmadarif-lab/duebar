import Foundation
import Network

/// A one-shot HTTP listener on 127.0.0.1 that catches an OAuth redirect (RFC 8252, loopback flow).
///
/// `waitForRedirect()` has no timeout of its own; the caller bounds it by cancelling, either
/// through `cancel()` or by cancelling the task around it (see `GoogleAuth.signIn`). A wait that
/// cannot be cancelled would hang forever when the browser tab is abandoned.
public final class LoopbackServer: @unchecked Sendable {
    public struct Cancelled: Error {}

    private let page: @Sendable (Bool) -> String

    private var listener: NWListener?
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var pending: Result<[String: String], Error>?
    private let lock = NSLock()

    /// `page` renders the HTML shown in the browser: `true` for a successful redirect.
    public init(page: @escaping @Sendable (Bool) -> String = { $0 ? "You can close this tab." : "Sign-in failed." }) {
        self.page = page
    }

    public func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        let listener = try NWListener(using: params, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        return try await withCheckedThrowingContinuation { cont in
            let once = Once()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: once.run { cont.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let e): once.run { cont.resume(throwing: e) }
                default: break
                }
            }
            listener.start(queue: .global())
        }
    }

    public func waitForRedirect() async throws -> [String: String] {
        defer { listener?.cancel() }
        return try await nextRedirect()
    }

    /// Ends a pending `waitForRedirect` with `cancelled` and stops listening.
    public func cancel() {
        listener?.cancel()
        finish(.failure(Cancelled()))
    }

    private func nextRedirect() async throws -> [String: String] {
        try await withCheckedThrowingContinuation { cont in
            lock.lock(); defer { lock.unlock() }
            if let pending { cont.resume(with: pending) } else { continuation = cont }
        }
    }

    private func finish(_ result: Result<[String: String], Error>) {
        lock.lock(); defer { lock.unlock() }
        if let continuation { continuation.resume(with: result); self.continuation = nil } else { pending = result }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global())
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let text = String(data: data, encoding: .utf8),
                  let line = text.split(separator: "\r\n").first else { conn.cancel(); return }
            let parts = line.split(separator: " ")
            guard parts.count >= 2, let comps = URLComponents(string: "http://x" + parts[1]) else { conn.cancel(); return }
            // Browsers also ask for /favicon.ico; only the redirect carries a query.
            guard let items = comps.queryItems, !items.isEmpty else {
                conn.send(content: Self.response("", status: "404 Not Found"), completion: .contentProcessed { _ in conn.cancel() })
                return
            }
            let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
            let ok = query["error"] == nil
            conn.send(content: Self.response(self.page(ok)), completion: .contentProcessed { _ in conn.cancel() })
            self.finish(.success(query))
        }
    }

    private static func response(_ body: String, status: String = "200 OK") -> Data {
        let bytes = body.data(using: .utf8) ?? Data()
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
        return head.data(using: .utf8)! + bytes
    }
}

/// Runs a block at most once, from any thread.
private final class Once: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()

    func run(_ block: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { block() }
    }
}
