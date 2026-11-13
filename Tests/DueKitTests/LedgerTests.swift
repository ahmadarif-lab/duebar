import XCTest
@testable import DueKit

final class LedgerTests: XCTestCase {
    private func sample() -> Payment {
        Payment(id: "p1", name: "Internet", amount: 400_000, startDate: DayStamp(year: 2026, month: 11, day: 5),
                repeatRule: RepeatRule(unit: .month))
    }

    func testPaySameOccurrenceOnTwoDevicesConverges() {
        var a = Ledger()
        a.upsert(sample(), now: Date(timeIntervalSince1970: 1000))
        var b = Ledger()
        b.apply(remote: a.pendingChanges())
        a.markPushed(a.pendingChanges())

        a.resolve("p1", .paid, now: Date(timeIntervalSince1970: 2000))
        b.resolve("p1", .paid, now: Date(timeIntervalSince1970: 2001))
        let fromA = a.pendingChanges(), fromB = b.pendingChanges()
        a.apply(remote: fromB)
        b.apply(remote: fromA)

        XCTAssertEqual(a.payment("p1")?.resolvedCount, 1)
        XCTAssertEqual(b.payment("p1")?.resolvedCount, 1)
        XCTAssertEqual(a.history.count, 1)
        XCTAssertEqual(b.history.count, 1)
    }

    func testNewerEditWinsOlderIsIgnored() {
        var l = Ledger()
        var p = sample()
        l.upsert(p, now: Date(timeIntervalSince1970: 5000))
        p.name = "Old"
        let stale = SyncRecord(kind: "payment", id: "p1", updatedAt: 4000, deleted: false,
                               data: String(decoding: try! JSONEncoder().encode(p), as: UTF8.self))
        l.apply(remote: [stale])
        XCTAssertEqual(l.payment("p1")?.name, "Internet")
    }

    func testDeleteSyncsAsTombstoneAndRemovesHistory() {
        var a = Ledger()
        a.upsert(sample(), now: Date(timeIntervalSince1970: 1000))
        a.resolve("p1", .paid, now: Date(timeIntervalSince1970: 1500))
        var b = Ledger()
        b.apply(remote: a.pendingChanges())
        a.delete("p1", now: Date(timeIntervalSince1970: 3000))
        b.apply(remote: a.pendingChanges())
        XCTAssertNil(b.payment("p1"))
        XCTAssertTrue(b.history.isEmpty)
    }

    func testEditDuringPushKeepsDirtyFlag() {
        var l = Ledger()
        l.upsert(sample(), now: Date(timeIntervalSince1970: 1000))
        let inFlight = l.pendingChanges()
        var p = l.payment("p1")!
        p.name = "Edited"
        l.upsert(p, now: Date(timeIntervalSince1970: 1001))
        l.markPushed(inFlight)
        XCTAssertTrue(l.hasPendingChanges)
    }

    func testUndoRestoresOccurrence() {
        var l = Ledger()
        l.upsert(sample(), now: Date(timeIntervalSince1970: 1000))
        let ev = l.resolve("p1", .paid, now: Date(timeIntervalSince1970: 2000))!
        l.undo(ev.id, now: Date(timeIntervalSince1970: 3000))
        XCTAssertEqual(l.payment("p1")?.resolvedCount, 0)
        XCTAssertTrue(l.history.isEmpty)
    }

    func testHistoryGroupsByMonthNewestFirstAcrossYears() {
        var l = Ledger()
        l.upsert(sample(), now: Date(timeIntervalSince1970: 1000))
        let cal = Calendar(identifier: .gregorian)
        func at(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
        for (i, when) in [at(2026, 11, 5), at(2026, 12, 20), at(2027, 1, 3), at(2026, 12, 2)].enumerated() {
            l.record(PaymentEvent(paymentId: "p1", name: "Internet", kind: .paid, dueDate: DayStamp(year: 2026, month: 1, day: i + 1),
                                  amount: 100, currency: "IDR", category: .internet, resolvedAt: when), now: when)
        }
        let months = l.historyByMonth(calendar: cal)
        XCTAssertEqual(months.map(\.id), [202701, 202612, 202611])          // January 2027 comes first
        XCTAssertEqual(months[1].events.count, 2)
        XCTAssertEqual(months[1].events.map { cal.component(.day, from: $0.resolvedAt) }, [20, 2])   // newest first inside a month
        XCTAssertEqual(l.historyByMonth(limit: 2, calendar: cal).flatMap(\.events).count, 2)
    }
}
