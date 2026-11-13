import DueKit
import Foundation

/// Keeps the exchange rates used to show one total in the main currency. Rates are cached on disk
/// and refreshed at most every 12 hours, and only fetched at all while some payment uses a
/// currency other than the main one: someone who only pays in rupiah never makes the request.
@MainActor
final class RatesService: ObservableObject {
    @Published private(set) var rates: ExchangeRates?
    @Published private(set) var failed = false
    @Published private(set) var isFetching = false

    private let store: Store
    private let fileURL: URL
    private var loop: Task<Void, Never>?
    private var lastFailure: Date?

    init(store: Store, directory: URL = Store.defaultDirectory) {
        self.store = store
        fileURL = directory.appendingPathComponent("rates.json")
        if let data = try? Data(contentsOf: fileURL), let cached = try? JSONDecoder().decode(ExchangeRates.self, from: data) {
            rates = cached
        }
    }

    /// Checks now and then every few hours while the app runs.
    func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshIfNeeded()
                try? await Task.sleep(for: .seconds(4 * 3600))
            }
        }
    }

    /// Currencies in use that differ from the main currency.
    private var foreignCurrenciesInUse: Set<String> {
        let main = UserDefaults.standard.mainCurrency
        return Set(store.ledger.activePayments.map(\.currency)).subtracting([main])
    }

    private var needsRates: Bool { !foreignCurrenciesInUse.isEmpty }

    /// Fetches when a conversion is needed and the cache is missing, old, or doesn't know a currency in use.
    func refreshIfNeeded() async {
        guard needsRates, !isFetching else { return }
        // After a failed attempt wait a minute: this also runs on every settings change.
        if let lastFailure, Date().timeIntervalSince(lastFailure) < 60 { return }
        let main = UserDefaults.standard.mainCurrency
        let needed = foreignCurrenciesInUse.union([main])
        if let rates, !rates.isStale(), needed.allSatisfy(rates.covers) { return }
        await refresh()
    }

    func refresh() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let fresh = try await RatesClient.fetch()
            rates = fresh
            failed = false
            lastFailure = nil
            if let data = try? JSONEncoder().encode(fresh) { try? data.write(to: fileURL, options: .atomic) }
        } catch {
            // Keep whatever is cached: slightly old rates beat no conversion.
            failed = true
            lastFailure = Date()
        }
    }

    /// For UI snapshots only.
    func setForPreview(_ preview: ExchangeRates) { rates = preview }
}
