import Foundation

// MARK: - Calendar day

/// A calendar date without a time zone ("2026-11-13"). Due dates float with
/// the person: a bill due on the 5th is due on the 5th wherever they travel.
public struct DayStamp: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public static func today(calendar: Calendar = .current) -> DayStamp {
        DayStamp(Date(), calendar: calendar)
    }

    public static func < (a: DayStamp, b: DayStamp) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = DayStamp(string: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad day: \(raw)"))
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    /// Midnight local time of this day (clamped to a valid date).
    public func date(hour: Int = 0, minute: Int = 0, calendar: Calendar = .current) -> Date {
        var c = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        c.calendar = calendar
        return calendar.date(from: c) ?? Date()
    }

    public func adding(days: Int, calendar: Calendar = .current) -> DayStamp {
        DayStamp(calendar.date(byAdding: .day, value: days, to: date(hour: 12, calendar: calendar)) ?? date(), calendar: calendar)
    }

    /// Whole days from `other` to self (positive when self is later).
    public func days(since other: DayStamp, calendar: Calendar = .current) -> Int {
        let a = other.date(hour: 12, calendar: calendar)
        let b = date(hour: 12, calendar: calendar)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    public static func daysInMonth(year: Int, month: Int, calendar: Calendar = .current) -> Int {
        let first = DayStamp(year: year, month: month, day: 1).date(hour: 12, calendar: calendar)
        return calendar.range(of: .day, in: .month, for: first)?.count ?? 30
    }
}

// MARK: - Repetition

public enum RepeatUnit: String, Codable, CaseIterable, Sendable {
    case none, day, week, month, year
}

public enum RepeatEnd: Codable, Equatable, Sendable {
    case never
    case onDate(DayStamp)
    case afterCount(Int)

    private enum CodingKeys: String, CodingKey { case type, date, count }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "date": self = .onDate(try c.decode(DayStamp.self, forKey: .date))
        case "count": self = .afterCount(try c.decode(Int.self, forKey: .count))
        default: self = .never
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .never: try c.encode("never", forKey: .type)
        case .onDate(let d): try c.encode("date", forKey: .type); try c.encode(d, forKey: .date)
        case .afterCount(let n): try c.encode("count", forKey: .type); try c.encode(n, forKey: .count)
        }
    }
}

public struct RepeatRule: Codable, Equatable, Sendable {
    public var unit: RepeatUnit
    /// Every N units: 1 = monthly, 3 = quarterly (unit .month).
    public var interval: Int
    public var end: RepeatEnd

    public init(unit: RepeatUnit = .none, interval: Int = 1, end: RepeatEnd = .never) {
        self.unit = unit
        self.interval = max(1, interval)
        self.end = end
    }

    public static let none = RepeatRule()
    public var isRepeating: Bool { unit != .none }
}

// MARK: - Category

public enum PaymentCategory: String, Codable, CaseIterable, Sendable {
    case utilities, internet, subscription, rent, loan, insurance, tax, credit, education, other

    public var symbol: String {
        switch self {
        case .utilities: return "bolt.fill"
        case .internet: return "wifi"
        case .subscription: return "play.rectangle.fill"
        case .rent: return "house.fill"
        case .loan: return "banknote.fill"
        case .insurance: return "cross.case.fill"
        case .tax: return "doc.text.fill"
        case .credit: return "creditcard.fill"
        case .education: return "graduationcap.fill"
        case .other: return "tag.fill"
        }
    }

    /// Hex colour used for the row icon.
    public var colorHex: UInt32 {
        switch self {
        case .utilities: return 0xFFB020
        case .internet: return 0x2F7BF6
        case .subscription: return 0xF0468C
        case .rent: return 0x34C759
        case .loan: return 0xFF6B3D
        case .insurance: return 0x32D1E8
        case .tax: return 0x8B6BFF
        case .credit: return 0xFF453A
        case .education: return 0x5E8BFF
        case .other: return 0x8E8E93
        }
    }
}

// MARK: - Payment

public struct Payment: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// Decimal as a string on the wire ("1250000.50") so every platform keeps exact money.
    public var amount: Decimal
    public var currency: String
    public var category: PaymentCategory
    /// First due date of the current series.
    public var startDate: DayStamp
    public var repeatRule: RepeatRule
    /// How many occurrences of the series are already paid or skipped.
    public var resolvedCount: Int
    /// Days before the due date to remind; 0 = on the day.
    public var reminderOffsets: [Int]
    /// Minutes after midnight for the reminder.
    public var reminderMinute: Int
    public var notes: String
    public var url: String
    public var paused: Bool
    /// Hidden from the menu bar when the series ended or it was archived.
    public var archived: Bool
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        amount: Decimal,
        currency: String = "IDR",
        category: PaymentCategory = .other,
        startDate: DayStamp,
        repeatRule: RepeatRule = .none,
        resolvedCount: Int = 0,
        reminderOffsets: [Int] = [1, 0],
        reminderMinute: Int = 9 * 60,
        notes: String = "",
        url: String = "",
        paused: Bool = false,
        archived: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.currency = currency
        self.category = category
        self.startDate = startDate
        self.repeatRule = repeatRule
        self.resolvedCount = resolvedCount
        self.reminderOffsets = reminderOffsets
        self.reminderMinute = reminderMinute
        self.notes = notes
        self.url = url
        self.paused = paused
        self.archived = archived
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, amount, currency, category, startDate, repeatRule, resolvedCount
        case reminderOffsets, reminderMinute, notes, url, paused, archived, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        let raw = try c.decode(String.self, forKey: .amount)
        amount = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) ?? 0
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "IDR"
        category = (try? c.decode(PaymentCategory.self, forKey: .category)) ?? .other
        startDate = try c.decode(DayStamp.self, forKey: .startDate)
        repeatRule = try c.decodeIfPresent(RepeatRule.self, forKey: .repeatRule) ?? .none
        resolvedCount = try c.decodeIfPresent(Int.self, forKey: .resolvedCount) ?? 0
        reminderOffsets = try c.decodeIfPresent([Int].self, forKey: .reminderOffsets) ?? [1, 0]
        reminderMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 540
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        let ms = try c.decodeIfPresent(Double.self, forKey: .createdAt) ?? 0
        createdAt = Date(timeIntervalSince1970: ms / 1000)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(NSDecimalNumber(decimal: amount).stringValue, forKey: .amount)
        try c.encode(currency, forKey: .currency)
        try c.encode(category, forKey: .category)
        try c.encode(startDate, forKey: .startDate)
        try c.encode(repeatRule, forKey: .repeatRule)
        try c.encode(resolvedCount, forKey: .resolvedCount)
        try c.encode(reminderOffsets, forKey: .reminderOffsets)
        try c.encode(reminderMinute, forKey: .reminderMinute)
        try c.encode(notes, forKey: .notes)
        try c.encode(url, forKey: .url)
        try c.encode(paused, forKey: .paused)
        try c.encode(archived, forKey: .archived)
        try c.encode((createdAt.timeIntervalSince1970 * 1000).rounded(), forKey: .createdAt)
    }
}

// MARK: - History

public enum EventKind: String, Codable, Sendable {
    case paid, skipped
}

/// One resolved occurrence. The id is derived from payment + due day, so
/// marking the same occurrence on two devices collapses into one record.
public struct PaymentEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var paymentId: String
    public var name: String
    public var kind: EventKind
    public var dueDate: DayStamp
    public var amount: Decimal
    public var currency: String
    public var category: PaymentCategory
    public var resolvedAt: Date

    public init(
        paymentId: String, name: String, kind: EventKind, dueDate: DayStamp,
        amount: Decimal, currency: String, category: PaymentCategory, resolvedAt: Date = Date()
    ) {
        self.id = "\(paymentId)_\(dueDate)"
        self.paymentId = paymentId
        self.name = name
        self.kind = kind
        self.dueDate = dueDate
        self.amount = amount
        self.currency = currency
        self.category = category
        self.resolvedAt = resolvedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, paymentId, name, kind, dueDate, amount, currency, category, resolvedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        paymentId = try c.decode(String.self, forKey: .paymentId)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(EventKind.self, forKey: .kind)
        dueDate = try c.decode(DayStamp.self, forKey: .dueDate)
        let raw = try c.decode(String.self, forKey: .amount)
        amount = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) ?? 0
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "IDR"
        category = (try? c.decode(PaymentCategory.self, forKey: .category)) ?? .other
        resolvedAt = Date(timeIntervalSince1970: (try c.decodeIfPresent(Double.self, forKey: .resolvedAt) ?? 0) / 1000)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(paymentId, forKey: .paymentId)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(dueDate, forKey: .dueDate)
        try c.encode(NSDecimalNumber(decimal: amount).stringValue, forKey: .amount)
        try c.encode(currency, forKey: .currency)
        try c.encode(category, forKey: .category)
        try c.encode((resolvedAt.timeIntervalSince1970 * 1000).rounded(), forKey: .resolvedAt)
    }
}
