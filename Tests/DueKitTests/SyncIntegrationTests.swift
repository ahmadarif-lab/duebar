import XCTest
@testable import DueKit

/// Runs against a real server: `Scripts/integration_test.sh` starts one with
/// DEV_AUTH=1 and sets DUEBAR_TEST_SERVER. Skipped otherwise.
final class SyncIntegrationTests: XCTestCase {
    private func client() throws -> SyncClient {
        guard let server = ProcessInfo.processInfo.environment["DUEBAR_TEST_SERVER"] else {
            throw XCTSkip("DUEBAR_TEST_SERVER not set")
        }
        return try XCTUnwrap(SyncClient(server: server))
    }

    /// Mirrors what the app does on one device.
    private func sync(_ c: SyncClient, _ token: String, _ ledger: inout Ledger) async throws {
        var local = ledger
        try await c.sync(
            token: token,
            snapshot: { (local.cursor, local.pendingChanges()) },
            apply: { reply, pushed in
                local.markPushed(pushed)
                local.apply(remote: reply.changes)
                local.cursor = reply.cursor
            }
        )
        ledger = local
    }

    func testTwoDevicesConverge() async throws {
        let c = try client()
        let email = "it-\(UUID().uuidString.prefix(8))@test.dev"
        let mac = try await c.devLogin(email: email)
        let phone = try await c.devLogin(email: email)
        var a = Ledger(), b = Ledger()

        // Mac adds a monthly bill and pays it; phone picks it up.
        a.upsert(Payment(id: "wifi", name: "Wifi", amount: Decimal(string: "385000.50")!,
                         startDate: DayStamp(year: 2026, month: 11, day: 5), repeatRule: RepeatRule(unit: .month)))
        a.resolve("wifi", .paid)
        try await sync(c, mac.token, &a)
        try await sync(c, phone.token, &b)
        XCTAssertEqual(b.payment("wifi")?.amount, Decimal(string: "385000.50"))
        XCTAssertEqual(b.payment("wifi")?.resolvedCount, 1)
        XCTAssertEqual(b.history.count, 1)
        XCTAssertFalse(a.hasPendingChanges)

        // Both pay the next occurrence while offline, then both sync.
        a.resolve("wifi", .paid, now: Date().addingTimeInterval(10))
        b.resolve("wifi", .paid, now: Date().addingTimeInterval(11))
        try await sync(c, mac.token, &a)
        try await sync(c, phone.token, &b)
        try await sync(c, mac.token, &a)
        XCTAssertEqual(a.payment("wifi")?.resolvedCount, 2)
        XCTAssertEqual(b.payment("wifi")?.resolvedCount, 2)
        XCTAssertEqual(a.history.count, 2)
        XCTAssertEqual(b.history.count, 2)

        // A delete on the phone reaches the Mac.
        b.delete("wifi")
        try await sync(c, phone.token, &b)
        try await sync(c, mac.token, &a)
        XCTAssertNil(a.payment("wifi"))
        XCTAssertTrue(a.history.isEmpty)
    }

    func testRevokedTokenIsUnauthorizedAndAccountDeletionWipes() async throws {
        let c = try client()
        let email = "it-\(UUID().uuidString.prefix(8))@test.dev"
        let s = try await c.devLogin(email: email)
        try await c.logout(token: s.token)
        do { _ = try await c.exchange(token: s.token, cursor: 0, changes: []); XCTFail("should be 401") }
        catch { XCTAssertEqual(error as? SyncError, .unauthorized) }

        let again = try await c.devLogin(email: email)
        var l = Ledger()
        l.upsert(Payment(id: "x", name: "X", amount: 1, startDate: DayStamp(year: 2026, month: 1, day: 1)))
        let pending = l.pendingChanges()
        _ = try await c.exchange(token: again.token, cursor: 0, changes: pending)
        try await c.deleteAccount(token: again.token)
        let fresh = try await c.devLogin(email: email)
        let reply = try await c.exchange(token: fresh.token, cursor: 0, changes: [])
        XCTAssertTrue(reply.changes.isEmpty)
    }

    func testMasterPasswordVerifierReachesTheOtherDevice() async throws {
        let c = try client()
        let email = "lock-\(UUID().uuidString.prefix(8))@test.dev"
        let mac = try await c.devLogin(email: email)
        let phone = try await c.devLogin(email: email)
        let empty = try await c.fetchLock(token: mac.token)
        XCTAssertNil(empty.verifier)

        let verifier = PasswordVerifier.make(password: "rahasia", iterations: 600_000)
        let stamp = try await c.putLock(token: mac.token, verifier: verifier)
        let seen = try await c.fetchLock(token: phone.token)
        XCTAssertEqual(seen.updatedAt, stamp)
        XCTAssertTrue(try XCTUnwrap(seen.verifier).matches("rahasia"))
        XCTAssertFalse(try XCTUnwrap(seen.verifier).matches("salah"))

        _ = try await c.putLock(token: phone.token, verifier: nil)
        let removed = try await c.fetchLock(token: mac.token)
        XCTAssertNil(removed.verifier)
    }
}
