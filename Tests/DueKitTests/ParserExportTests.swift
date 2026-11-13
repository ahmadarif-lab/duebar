import XCTest
@testable import DueKit

final class ParserExportTests: XCTestCase {
    func testIDRTreatsSeparatorsAsGrouping() {
        XCTAssertEqual(AmountParser.parse("Rp 1.250.000", currency: "IDR"), 1_250_000)
        XCTAssertEqual(AmountParser.parse("1,250,000", currency: "IDR"), 1_250_000)
        XCTAssertEqual(AmountParser.parse("350.000", currency: "IDR"), 350_000)
        XCTAssertEqual(AmountParser.parse("350000", currency: "IDR"), 350_000)
    }

    func testDecimalCurrencies() {
        XCTAssertEqual(AmountParser.parse("12.50", currency: "USD"), Decimal(string: "12.5"))
        XCTAssertEqual(AmountParser.parse("12,5", currency: "EUR"), Decimal(string: "12.5"))
        XCTAssertEqual(AmountParser.parse("1,250", currency: "USD"), 1250)
        XCTAssertEqual(AmountParser.parse("1,250.75", currency: "USD"), Decimal(string: "1250.75"))
        XCTAssertEqual(AmountParser.parse("1.250,75", currency: "EUR"), Decimal(string: "1250.75"))
        XCTAssertEqual(AmountParser.parse("1,250,000", currency: "USD"), 1_250_000)
    }

    func testRejectsNoDigits() {
        XCTAssertNil(AmountParser.parse("abc", currency: "IDR"))
        XCTAssertNil(AmountParser.parse("", currency: "USD"))
    }

    func testCSVEscapesAndBackupRoundTrip() throws {
        var l = Ledger()
        l.upsert(Payment(id: "a", name: "Kos, \"Mawar\"", amount: 900_000, startDate: DayStamp(year: 2026, month: 12, day: 1), repeatRule: RepeatRule(unit: .month)))
        l.resolve("a", .paid)
        let csv = Export.csv(ledger: l)
        XCTAssertTrue(csv.contains("\"Kos, \"\"Mawar\"\"\""))
        XCTAssertEqual(csv.split(separator: "\n").count, 3)

        let data = try Export.backupJSON(ledger: l)
        var fresh = Ledger()
        XCTAssertEqual(try Export.restore(data, into: &fresh), 1)
        XCTAssertEqual(fresh.payment("a")?.resolvedCount, 1)
        XCTAssertEqual(fresh.history.count, 1)
    }
}

final class SessionTests: XCTestCase {
    func testSessionSavedBeforePictureStillLoads() throws {
        let old = #"{"token":"t","email":"a@x.com","name":"A"}"#
        let s = try JSONDecoder().decode(AuthSession.self, from: Data(old.utf8))
        XCTAssertEqual(s.picture, "")
        XCTAssertEqual(s.email, "a@x.com")
    }

    func testProfileWithoutPictureDecodes() throws {
        let p = try JSONDecoder().decode(AccountProfile.self, from: Data(#"{"email":"a@x.com"}"#.utf8))
        XCTAssertEqual(p, try JSONDecoder().decode(AccountProfile.self, from: Data(#"{"email":"a@x.com","name":"","picture":""}"#.utf8)))
    }
}
