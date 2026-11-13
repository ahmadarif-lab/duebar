import Foundation

public extension Payment {
    /// How many days ahead the first reminder fires: the largest of its reminder offsets (0 = only
    /// on the day). A payment counts as due soon from then on.
    var reminderWindowDays: Int { max(reminderOffsets.filter { $0 >= 0 }.max() ?? 0, 0) }

    /// Due day of the nth occurrence (0-based), always computed from the
    /// series start rather than the previous occurrence, so Jan 31 → Feb 28
    /// → Mar 31 doesn't drift to the 28th. nil past the end of the series.
    func occurrence(_ index: Int, calendar: Calendar = .current) -> DayStamp? {
        guard index >= 0 else { return nil }
        if case .afterCount(let n) = repeatRule.end, index >= max(1, n) { return nil }
        let day: DayStamp
        if !repeatRule.isRepeating {
            guard index == 0 else { return nil }
            day = startDate
        } else {
            let step = index * repeatRule.interval
            switch repeatRule.unit {
            case .none: return nil
            case .day: day = startDate.adding(days: step, calendar: calendar)
            case .week: day = startDate.adding(days: step * 7, calendar: calendar)
            case .month:
                let total = (startDate.year * 12 + startDate.month - 1) + step
                let y = total / 12, m = total % 12 + 1
                day = DayStamp(year: y, month: m,
                               day: min(startDate.day, DayStamp.daysInMonth(year: y, month: m, calendar: calendar)))
            case .year:
                let y = startDate.year + step
                day = DayStamp(year: y, month: startDate.month,
                               day: min(startDate.day, DayStamp.daysInMonth(year: y, month: startDate.month, calendar: calendar)))
            }
        }
        if case .onDate(let end) = repeatRule.end, day > end { return nil }
        return day
    }

    /// The occurrence waiting to be paid, nil once the series is finished.
    func nextDue(calendar: Calendar = .current) -> DayStamp? {
        occurrence(resolvedCount, calendar: calendar)
    }

    var isFinished: Bool { nextDue() == nil }

    /// Upcoming occurrences starting with the next unpaid one, capped by
    /// `limit` and `until` (used for the calendar and notification queue).
    func upcoming(limit: Int, until: DayStamp? = nil, calendar: Calendar = .current) -> [DayStamp] {
        var out: [DayStamp] = []
        var index = resolvedCount
        while out.count < limit, let day = occurrence(index, calendar: calendar) {
            if let until, day > until { break }
            out.append(day)
            index += 1
        }
        return out
    }

    /// Pays or skips the current occurrence: returns the history event and
    /// moves the series on. Archives the payment when the series ends.
    @discardableResult
    mutating func resolve(_ kind: EventKind, paidAmount: Decimal? = nil, at date: Date = Date(), calendar: Calendar = .current) -> PaymentEvent? {
        guard let due = nextDue(calendar: calendar) else { return nil }
        let event = PaymentEvent(
            paymentId: id, name: name, kind: kind, dueDate: due,
            amount: paidAmount ?? amount, currency: currency, category: category, resolvedAt: date
        )
        resolvedCount += 1
        if nextDue(calendar: calendar) == nil { archived = true }
        return event
    }

    /// What saving the edit form does to the schedule. `opened` is the date the form opened with:
    /// comparing against it (not `nextDue`, which is nil once a series has finished) means saving a
    /// finished payment without touching its date leaves it finished. A changed date or rule starts
    /// the series over from the chosen day.
    mutating func applyEditedSchedule(openedWith opened: DayStamp?, chosen day: DayStamp, rule: RepeatRule) {
        let dateChanged = opened.map { $0 != day } ?? true
        let ruleChanged = repeatRule != rule
        repeatRule = rule
        if dateChanged || ruleChanged { reschedule(to: day) }
    }

    /// Re-anchors the series on a new next due date (editing the date).
    mutating func reschedule(to day: DayStamp) {
        startDate = day
        resolvedCount = 0
        archived = false
    }
}

public enum DueStatus: Equatable, Sendable {
    case overdue(days: Int)
    case today
    case upcoming(days: Int)
}

public extension Payment {
    func status(today: DayStamp = .today(), calendar: Calendar = .current) -> DueStatus? {
        guard let due = nextDue(calendar: calendar) else { return nil }
        let diff = due.days(since: today, calendar: calendar)
        if diff < 0 { return .overdue(days: -diff) }
        return diff == 0 ? .today : .upcoming(days: diff)
    }
}
