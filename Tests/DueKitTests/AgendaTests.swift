import XCTest
@testable import DueKit

final class AgendaTests: XCTestCase {
    private let today = DayStamp(year: 2026, month: 11, day: 13)
    private func pay(_ name: String, _ day: Int, month: Int = 11, rule: RepeatRule = .none, amount: Decimal = 100, offsets: [Int] = [1, 0]) -> Payment {
        Payment(id: name, name: name, amount: amount, startDate: DayStamp(year: 2026, month: month, day: day), repeatRule: rule, reminderOffsets: offsets)
    }

    func testBucketsAndOrdering() {
        let a = Agenda.make(payments: [pay("late", 10), pay("now", 13), pay("soon", 18), pay("far", 30), pay("beyond", 1, month: 3)], today: today, horizonDays: 60)
        XCTAssertEqual(a.overdue.map(\.payment.name), ["beyond", "late"])
        XCTAssertEqual(a.today.map(\.payment.name), ["now"])
        XCTAssertEqual(a.week.map(\.payment.name), ["soon"])
        XCTAssertEqual(a.later.map(\.payment.name), ["far"])
        XCTAssertEqual(a.dueSoonCount, 3)   // two overdue + today; "soon" is 5 days out but reminds only from 1 day
        XCTAssertEqual(a.next?.payment.name, "beyond")
    }

    func testPausedAndArchivedAreKeptOutOfBuckets() {
        var p = pay("paused", 15); p.paused = true
        var q = pay("done", 15); q.archived = true
        let a = Agenda.make(payments: [p, q], today: today)
        XCTAssertEqual(a.paused.count, 1)
        XCTAssertTrue(a.overdue.isEmpty && a.today.isEmpty && a.week.isEmpty && a.later.isEmpty)
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

    func testDueSoonFollowsEachPaymentsReminderWindow() {
        let a = Agenda.make(payments: [
            pay("late", 10),                                  // overdue: always
            pay("now", 13),                                   // today: always
            pay("in5-week", 18, offsets: [7, 1, 0]),          // 5 days out, reminders from 7: due soon
            pay("in5-day", 18, offsets: [1, 0]),              // 5 days out, reminders from 1: not yet
            pay("in18", 1, month: 12, offsets: [7, 2, 1]),    // 18 days out: not yet
            pay("on-day-only", 14, offsets: []),              // tomorrow, no reminder before the day: not yet
        ], today: today, horizonDays: 90)
        XCTAssertEqual(Set(a.dueSoon.map(\.payment.name)), ["late", "now", "in5-week"])
        XCTAssertEqual(a.dueSoonCount, 3)
        XCTAssertEqual(a.dueSoon.map(\.payment.name), ["late", "now", "in5-week"])   // soonest first
    }

    func testReminderWindowIsTheLargestOffset() {
        XCTAssertEqual(pay("a", 1, offsets: [7, 1, 2]).reminderWindowDays, 7)
        XCTAssertEqual(pay("b", 1, offsets: [0]).reminderWindowDays, 0)
        XCTAssertEqual(pay("c", 1, offsets: []).reminderWindowDays, 0)
    }

    func testOutstandingSumsWhatIsDueSoonInTheMainCurrency() {
        var usd = pay("usd", 16, amount: 10, offsets: [7, 1, 0]); usd.currency = "USD"
        let a = Agenda.make(payments: [
            pay("late", 10, amount: 100), pay("now", 13, amount: 200),
            pay("later-in-window", 17, amount: 300, offsets: [7]),   // 4 days out, inside its 7-day window
            pay("not-yet", 25, amount: 999),                         // 12 days out, window 1
            usd,
        ], today: today, horizonDays: 90)
        let rates = ExchangeRates(rates: ["IDR": 16000])
        let o = a.outstanding(in: "IDR", rates: rates)
        XCTAssertEqual(o.total, 100 + 200 + 300 + 160_000)
        XCTAssertEqual(o.count, 4)
        XCTAssertTrue(o.includesConverted)
        XCTAssertTrue(o.unconverted.isEmpty)
    }

    func testOutstandingKeepsCurrenciesWithoutARateApart() {
        var usd = pay("usd", 13, amount: 10); usd.currency = "USD"
        var jpy = pay("jpy", 13, amount: 5000); jpy.currency = "JPY"
        let a = Agenda.make(payments: [pay("a", 13, amount: 100), usd, jpy], today: today)
        // No rates at all: only the main currency adds up.
        let none = a.outstanding(in: "IDR", rates: nil)
        XCTAssertEqual(none.total, 100)
        XCTAssertEqual(none.unconverted, ["USD": 10, "JPY": 5000])
        XCTAssertFalse(none.includesConverted)
        // Rates that cover USD but not JPY.
        let some = a.outstanding(in: "IDR", rates: ExchangeRates(rates: ["IDR": 16000]))
        XCTAssertEqual(some.total, 100 + 160_000)
        XCTAssertEqual(some.unconverted, ["JPY": 5000])
    }
}
