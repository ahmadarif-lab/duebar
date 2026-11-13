import XCTest
@testable import DueKit

final class ExchangeRatesTests: XCTestCase {
    private let rates = ExchangeRates(rates: ["IDR": 16000, "EUR": Decimal(string: "0.8")!, "SAR": Decimal(string: "3.75")!])

    func testBaseToQuoteAndBack() {
        XCTAssertEqual(rates.convert(10, from: "USD", to: "IDR"), 160_000)
        XCTAssertEqual(rates.convert(160_000, from: "IDR", to: "USD"), 10)
    }

    func testCrossRatesGoThroughTheBase() {
        // 1 EUR = 1/0.8 USD = 20,000 IDR
        XCTAssertEqual(rates.convert(1, from: "EUR", to: "IDR"), 20_000)
        XCTAssertEqual(rates.rate(from: "SAR", to: "EUR"), Decimal(string: "0.8")! / Decimal(string: "3.75")!)
    }

    func testSameCurrencyIsAnIdentityEvenWithoutARate() {
        XCTAssertEqual(rates.convert(42, from: "JPY", to: "JPY"), 42)
    }

    func testUnknownCurrencyCannotBeConverted() {
        XCTAssertNil(rates.convert(1, from: "JPY", to: "IDR"))
        XCTAssertNil(rates.convert(1, from: "IDR", to: "JPY"))
        XCTAssertFalse(rates.covers("JPY"))
        XCTAssertTrue(rates.covers("USD"))
    }

    func testTotalsAddMixedCurrenciesAndReportMissingRates() {
        let ok = rates.total(of: [(100, "IDR"), (10, "USD")], in: "IDR")
        XCTAssertEqual(ok.total, 160_100)
        XCTAssertTrue(ok.complete)
        let partial = rates.total(of: [(100, "IDR"), (5, "JPY")], in: "IDR")
        XCTAssertEqual(partial.total, 100)
        XCTAssertFalse(partial.complete)
    }

    func testStaleness() {
        let fetched = Date(timeIntervalSince1970: 1_000_000)
        let r = ExchangeRates(rates: ["IDR": 1], fetchedAt: fetched)
        XCTAssertFalse(r.isStale(now: fetched.addingTimeInterval(3600)))
        XCTAssertTrue(r.isStale(now: fetched.addingTimeInterval(13 * 3600)))
    }

    func testParsesTheProvidersResponse() throws {
        let json = """
        {"result":"success","provider":"https://www.exchangerate-api.com","base_code":"USD",
         "time_last_update_unix":1794528151,"rates":{"USD":1,"IDR":18250.530965,"EUR":0.903491,"BAD":0,"NEG":-2}}
        """
        let parsed = try RatesClient.parse(Data(json.utf8), now: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(parsed.base, "USD")
        XCTAssertEqual(parsed.rates["IDR"], Decimal(string: "18250.530965"))
        XCTAssertNil(parsed.rates["BAD"])           // zero and negative rates are dropped
        XCTAssertNil(parsed.rates["NEG"])
        XCTAssertEqual(parsed.fetchedAt, Date(timeIntervalSince1970: 5))
    }

    func testRejectsAnErrorResponse() {
        let json = #"{"result":"error","error-type":"quota-reached"}"#
        XCTAssertThrowsError(try RatesClient.parse(Data(json.utf8)))
    }

    func testRoundTripsThroughJSONForTheDiskCache() throws {
        let data = try JSONEncoder().encode(rates)
        XCTAssertEqual(try JSONDecoder().decode(ExchangeRates.self, from: data), rates)
    }

    /// Hits the real endpoint; run with DUEBAR_LIVE_RATES=1.
    func testLiveFetchReturnsUsableRates() async throws {
        guard ProcessInfo.processInfo.environment["DUEBAR_LIVE_RATES"] == "1" else { throw XCTSkip("set DUEBAR_LIVE_RATES=1") }
        let live = try await RatesClient.fetch()
        XCTAssertEqual(live.base, "USD")
        XCTAssertGreaterThan(live.rates.count, 100)
        for code in ["IDR", "EUR", "SGD", "MYR", "JPY", "GBP", "AUD", "SAR"] { XCTAssertTrue(live.covers(code), code) }
        let idrPerUSD = try XCTUnwrap(live.rate(from: "USD", to: "IDR"))
        XCTAssertTrue((5_000...50_000).contains(idrPerUSD), "implausible USD/IDR \(idrPerUSD)")
        print("live USD/IDR =", idrPerUSD)
    }
}
