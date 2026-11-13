import Foundation

/// Exchange rates relative to one base currency (USD): `rates["IDR"]` is how many IDR one USD
/// buys. Any pair is converted through the base, so one download covers every combination.
public struct ExchangeRates: Codable, Equatable, Sendable {
    public var base: String
    public var rates: [String: Decimal]
    public var fetchedAt: Date

    public init(base: String = "USD", rates: [String: Decimal], fetchedAt: Date = Date()) {
        self.base = base
        self.rates = rates
        self.fetchedAt = fetchedAt
    }

    private func rate(_ currency: String) -> Decimal? {
        currency == base ? 1 : rates[currency]
    }

    public func covers(_ currency: String) -> Bool { rate(currency) != nil }

    /// Units of `to` per one unit of `from`.
    public func rate(from: String, to: String) -> Decimal? {
        if from == to { return 1 }
        guard let f = rate(from), let t = rate(to), f != 0 else { return nil }
        return t / f
    }

    /// `amount` of `from` in `to`, or nil when either currency has no rate.
    public func convert(_ amount: Decimal, from: String, to: String) -> Decimal? {
        rate(from: from, to: to).map { amount * $0 }
    }

    /// Adds amounts in different currencies as one amount in `currency`. `complete` is false when
    /// some amount had no rate and was left out, so the caller can say the total is partial.
    public func total(of amounts: [(amount: Decimal, currency: String)], in currency: String) -> (total: Decimal, complete: Bool) {
        var total: Decimal = 0
        var complete = true
        for entry in amounts {
            if let converted = convert(entry.amount, from: entry.currency, to: currency) { total += converted } else { complete = false }
        }
        return (total, complete)
    }

    public func isStale(after interval: TimeInterval = 12 * 3600, now: Date = Date()) -> Bool {
        now.timeIntervalSince(fetchedAt) > interval
    }
}

/// Downloads the daily rates from open.er-api.com (ExchangeRate-API's free endpoint: no key, about
/// 160 currencies, refreshed once a day). The request carries no personal data, only the base code.
public enum RatesClient {
    public static let endpoint = URL(string: "https://open.er-api.com/v6/latest/USD")!

    public enum RatesError: Error, Equatable { case badResponse, unsuccessful }

    public static func fetch(urlSession: URLSession = .shared, now: Date = Date()) async throws -> ExchangeRates {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await urlSession.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RatesError.badResponse }
        return try parse(data, now: now)
    }

    public static func parse(_ data: Data, now: Date = Date()) throws -> ExchangeRates {
        struct Payload: Decodable {
            var result: String
            var base_code: String
            var rates: [String: Decimal]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.result == "success", !payload.rates.isEmpty else { throw RatesError.unsuccessful }
        // Ignore anything that isn't a positive rate rather than let it poison a conversion.
        let usable = payload.rates.filter { $0.value > 0 }
        return ExchangeRates(base: payload.base_code, rates: usable, fetchedAt: now)
    }
}
