import XCTest
@testable import DueKit

final class LoopbackServerTests: XCTestCase {
    private func get(_ port: UInt16, _ path: String) async throws -> (Int, String) {
        let url = URL(string: "http://127.0.0.1:\(port)\(path)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        return ((response as! HTTPURLResponse).statusCode, String(decoding: data, as: UTF8.self))
    }

    func testReceivesTheRedirectQueryAndShowsAPage() async throws {
        let server = LoopbackServer(page: { ok in ok ? "SIGNED-IN" : "FAILED" })
        let port = try await server.start()
        let waiting = Task { try await server.waitForRedirect() }
        let (status, body) = try await get(port, "/?code=abc&state=xyz")
        XCTAssertEqual(status, 200)
        XCTAssertEqual(body, "SIGNED-IN")
        let query = try await waiting.value
        XCTAssertEqual(query["code"], "abc")
        XCTAssertEqual(query["state"], "xyz")
    }

    func testAnErrorRedirectShowsTheFailurePage() async throws {
        let server = LoopbackServer(page: { ok in ok ? "OK" : "FAILED" })
        let port = try await server.start()
        let waiting = Task { try await server.waitForRedirect() }
        let (_, body) = try await get(port, "/?error=access_denied&state=s")
        XCTAssertEqual(body, "FAILED")
        let query = try await waiting.value
        XCTAssertEqual(query["error"], "access_denied")
    }

    func testFaviconRequestsAreIgnoredAndTheRealRedirectStillWorks() async throws {
        let server = LoopbackServer()
        let port = try await server.start()
        let waiting = Task { try await server.waitForRedirect() }
        let (status, _) = try await get(port, "/favicon.ico")
        XCTAssertEqual(status, 404)
        _ = try await get(port, "/?code=1&state=2")
        let query = try await waiting.value
        XCTAssertEqual(query["code"], "1")
    }

    /// The bug this guards against: a wait that cannot be cancelled hangs forever when the
    /// person abandons the browser tab, leaving the Sign in button stuck.
    func testCancellingTheTaskEndsTheWaitPromptly() async throws {
        let server = LoopbackServer()
        _ = try await server.start()
        let waiting = Task {
            try await withTaskCancellationHandler {
                try await server.waitForRedirect()
            } onCancel: {
                server.cancel()
            }
        }
        try await Task.sleep(for: .milliseconds(200))
        let started = Date()
        waiting.cancel()
        do {
            _ = try await waiting.value
            XCTFail("expected Cancelled")
        } catch is LoopbackServer.Cancelled {
            XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        }
    }

    func testCancelBeforeWaitingStillEndsTheWait() async throws {
        let server = LoopbackServer()
        _ = try await server.start()
        server.cancel()
        do {
            _ = try await server.waitForRedirect()
            XCTFail("expected Cancelled")
        } catch is LoopbackServer.Cancelled {}
    }
}
