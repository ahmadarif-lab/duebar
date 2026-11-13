import XCTest
@testable import DueKit

final class AgendaTests: XCTestCase {
    private let today = DayStamp(year: 2026, month: 11, day: 13)
    private func pay(_ name: String, _ day: Int, month: Int = 11, rule: RepeatRule = .none, amount: Decimal = 100) -> Payment {
        Payment(id: name, name: name, amount: amount, startDate: DayStamp(year: 2026, month: month, day: day), repeatRule: rule)
    }

    func testBucketsAndOrdering() {
        let a = Agenda.make(payments: [pay("late", 10), pay("now", 13), pay("soon", 18), pay("far", 30), pay("beyond", 1, month: 3)], today: today, horizonDays: 60)
        XCTAssertEqual(a.overdue.map(\.payment.name), ["beyond", "late"])
        XCTAssertEqual(a.today.map(\.payment.name), ["now"])
        XCTAssertEqual(a.week.map(\.payment.name), ["soon"])
        XCTAssertEqual(a.later.map(\.payment.name), ["far"])
        XCTAssertEqual(a.attentionCount, 3)
        XCTAssertEqual(a.dueSoonCount, 4)   // plus "soon" (5 days out)
        XCTAssertEqual(a.next?.payment.name, "beyond")
    }

    func testPausedAndArchivedAreKeptOutOfBuckets() {
        var p = pay("paused", 15); p.paused = true
        var q = pay("done", 15); q.archived = true
        let a = Agenda.make(payments: [p, q], today: today)
        XCTAssertEqual(a.paused.count, 1)
        XCTAssertTrue(a.overdue.isEmpty && a.today.isEmpty && a.week.isEmpty && a.later.isEmpty)
    }

    func testMonthSummaryCountsPaidAndRemaining() {
        var l = Ledger()
        l.upsert(pay("listrik", 5, rule: RepeatRule(unit: .month), amount: 500))
        l.upsert(pay("wifi", 20, amount: 300))
        l.resolve("listrik", .paid)                       // Nov 5 paid, Dec 5 not this month
        let s = MonthSummary.make(ledger: l, today: today)
        XCTAssertEqual(s.paid["IDR"], 500)
        XCTAssertEqual(s.remaining["IDR"], 300)
        XCTAssertEqual(s.paidCount, 1)
        XCTAssertEqual(s.remainingCount, 1)
        XCTAssertEqual(s.progress, 0.5, accuracy: 0.001)
    }

    func testPlannerSchedulesOffsetsInFutureOnly() {
        let cal = Calendar.current
        let now = DayStamp(year: 2026, month: 11, day: 13).date(hour: 10, calendar: cal)
        var p = pay("sewa", 14)
        p.reminderOffsets = [1, 0]; p.reminderMinute = 9 * 60
        // 1 day before = Nov 13 09:00 (already passed), on the day = Nov 14 09:00
        let plan = ReminderPlanner.plan(payments: [p], now: now)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].offset, 0)
        XCTAssertEqual(plan[0].fire, DayStamp(year: 2026, month: 11, day: 14).date(hour: 9, calendar: cal))
    }

    func testPlannerNudgesOverdueAndRespectsLimit() {
        let cal = Calendar.current
        let now = DayStamp(year: 2026, month: 11, day: 13).date(hour: 10, calendar: cal)
        let plan = ReminderPlanner.plan(payments: [pay("late", 10)], now: now)
        XCTAssertEqual(plan.filter { $0.offset == -1 }.count, 2) // today 09:00 already passed → tomorrow, day after
        XCTAssertEqual(ReminderPlanner.plan(payments: (1...30).map { pay("p\($0)", 20, rule: RepeatRule(unit: .week)) }, now: now, limit: 10).count, 10)
    }

    func testOutstandingCountsOverdueAndTheNextThirtyDaysPerCurrency() {
        var usd = pay("usd", 20, amount: 15)
        usd.currency = "USD"
        let a = Agenda.make(payments: [
            pay("late", 10, amount: 100), pay("now", 13, amount: 200), pay("soon", 18, amount: 300),
            pay("edge", 13, month: 12, amount: 400),      // 30 days out
            pay("far", 14, month: 12, amount: 999),       // 31 days out: not outstanding yet
            usd,
        ], today: today, horizonDays: 90)
        let o = a.outstanding(withinDays: 30)
        XCTAssertEqual(o.totals["IDR"], 1000)
        XCTAssertEqual(o.totals["USD"], 15)
        XCTAssertEqual(o.count, 5)
        XCTAssertEqual(o.currencies, ["IDR", "USD"])
    }
}
