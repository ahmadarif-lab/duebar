import XCTest
@testable import DueKit

final class RecurrenceTests: XCTestCase {
    private func make(_ start: DayStamp, _ rule: RepeatRule) -> Payment {
        Payment(name: "Test", amount: 100, startDate: start, repeatRule: rule)
    }

    func testMonthlyKeepsAnchorDayAcrossShortMonths() {
        let p = make(DayStamp(year: 2026, month: 1, day: 31), RepeatRule(unit: .month))
        XCTAssertEqual(p.occurrence(1), DayStamp(year: 2026, month: 2, day: 28))
        XCTAssertEqual(p.occurrence(2), DayStamp(year: 2026, month: 3, day: 31))
        XCTAssertEqual(p.occurrence(13), DayStamp(year: 2027, month: 2, day: 28))
    }

    func testQuarterlyAndYearly() {
        let q = make(DayStamp(year: 2026, month: 11, day: 15), RepeatRule(unit: .month, interval: 3))
        XCTAssertEqual(q.occurrence(1), DayStamp(year: 2027, month: 2, day: 15))
        let y = make(DayStamp(year: 2024, month: 2, day: 29), RepeatRule(unit: .year))
        XCTAssertEqual(y.occurrence(1), DayStamp(year: 2025, month: 2, day: 28))
        XCTAssertEqual(y.occurrence(4), DayStamp(year: 2028, month: 2, day: 29))
    }

    func testWeeklyAcrossYearBoundary() {
        let p = make(DayStamp(year: 2026, month: 12, day: 28), RepeatRule(unit: .week, interval: 2))
        XCTAssertEqual(p.occurrence(1), DayStamp(year: 2027, month: 1, day: 11))
    }

    func testEndConditions() {
        let byCount = make(DayStamp(year: 2026, month: 1, day: 1), RepeatRule(unit: .month, end: .afterCount(3)))
        XCTAssertNotNil(byCount.occurrence(2))
        XCTAssertNil(byCount.occurrence(3))
        let byDate = make(DayStamp(year: 2026, month: 1, day: 1),
                          RepeatRule(unit: .month, end: .onDate(DayStamp(year: 2026, month: 3, day: 1))))
        XCTAssertNotNil(byDate.occurrence(2))
        XCTAssertNil(byDate.occurrence(3))
    }

    func testResolveAdvancesAndArchivesAtEnd() {
        var p = make(DayStamp(year: 2026, month: 1, day: 1), RepeatRule(unit: .month, end: .afterCount(2)))
        let first = p.resolve(.paid)
        XCTAssertEqual(first?.dueDate, DayStamp(year: 2026, month: 1, day: 1))
        XCTAssertEqual(p.nextDue(), DayStamp(year: 2026, month: 2, day: 1))
        XCTAssertFalse(p.archived)
        p.resolve(.skipped)
        XCTAssertNil(p.nextDue())
        XCTAssertTrue(p.archived)
    }

    func testOneOffFinishesAfterPaying() {
        var p = make(DayStamp(year: 2026, month: 5, day: 5), .none)
        XCTAssertNotNil(p.nextDue())
        p.resolve(.paid)
        XCTAssertTrue(p.archived)
        XCTAssertNil(p.nextDue())
    }

    func testEventIdIsDeterministicPerOccurrence() {
        var a = make(DayStamp(year: 2026, month: 1, day: 1), RepeatRule(unit: .month))
        var b = a
        XCTAssertEqual(a.resolve(.paid)?.id, b.resolve(.paid)?.id)
    }

    func testStatus() {
        let today = DayStamp(year: 2026, month: 11, day: 13)
        XCTAssertEqual(make(DayStamp(year: 2026, month: 11, day: 10), .none).status(today: today), .overdue(days: 3))
        XCTAssertEqual(make(today, .none).status(today: today), .today)
        XCTAssertEqual(make(DayStamp(year: 2026, month: 11, day: 20), .none).status(today: today), .upcoming(days: 7))
    }

    func testCodableRoundTripKeepsExactMoney() throws {
        let p = Payment(name: "Listrik", amount: Decimal(string: "1250000.55")!, startDate: DayStamp(year: 2026, month: 11, day: 5),
                        repeatRule: RepeatRule(unit: .month, end: .afterCount(12)))
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(Payment.self, from: data)
        XCTAssertEqual(back.amount, p.amount)
        XCTAssertEqual(back.repeatRule, p.repeatRule)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"1250000.55\""))
    }

    func testSavingAFinishedPaymentWithoutTouchingItsDateKeepsItFinished() {
        var p = make(DayStamp(year: 2026, month: 5, day: 5), .none)
        p.resolve(.paid)
        XCTAssertTrue(p.archived)
        let opened = p.nextDue() ?? p.startDate
        p.applyEditedSchedule(openedWith: opened, chosen: opened, rule: .none)
        XCTAssertTrue(p.archived)
        XCTAssertEqual(p.resolvedCount, 1)
    }

    func testChangingTheDateOrRuleStartsTheSeriesOver() {
        var p = make(DayStamp(year: 2026, month: 1, day: 5), RepeatRule(unit: .month))
        p.resolve(.paid); p.resolve(.paid)
        XCTAssertEqual(p.resolvedCount, 2)
        let opened = p.nextDue()!
        // Same date, same rule: nothing happens.
        p.applyEditedSchedule(openedWith: opened, chosen: opened, rule: RepeatRule(unit: .month))
        XCTAssertEqual(p.resolvedCount, 2)
        // New date: the series restarts from it.
        let newDay = DayStamp(year: 2026, month: 6, day: 1)
        p.applyEditedSchedule(openedWith: opened, chosen: newDay, rule: RepeatRule(unit: .month))
        XCTAssertEqual(p.nextDue(), newDay)
        XCTAssertEqual(p.resolvedCount, 0)
        // A different rule restarts it too, and revives a finished payment.
        var done = make(DayStamp(year: 2026, month: 5, day: 5), .none)
        done.resolve(.paid)
        done.applyEditedSchedule(openedWith: DayStamp(year: 2026, month: 5, day: 5), chosen: DayStamp(year: 2026, month: 5, day: 5), rule: RepeatRule(unit: .month))
        XCTAssertFalse(done.archived)
        XCTAssertEqual(done.resolvedCount, 0)
    }
}
