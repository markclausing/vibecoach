import Foundation

// CLAUDE.md §3 — DST-safe time calculations.
// `TimeInterval` math (dividing by 86400 or 7*86400) is wrong around DST transitions,
// because a day can then be 23 or 25 hours. These extensions use `Calendar.dateComponents`
// so all calculations automatically account for the timezone rules.
extension Calendar {

    /// Fractional number of days between two `Date`s — DST-safe.
    ///
    /// Used for displaying remaining time with sub-day precision (e.g. "12.5 days").
    /// Negative if `end` is before `start`.
    func fractionalDays(from start: Date, to end: Date) -> Double {
        let comps = dateComponents([.day, .hour, .minute], from: start, to: end)
        let days = Double(comps.day ?? 0)
        let hours = Double(comps.hour ?? 0)
        let minutes = Double(comps.minute ?? 0)
        return days + hours / 24.0 + minutes / (24.0 * 60.0)
    }

    /// Fractional number of weeks between two `Date`s — DST-safe.
    ///
    /// Based on `fractionalDays` / 7. Negative if `end` is before `start`.
    func fractionalWeeks(from start: Date, to end: Date) -> Double {
        return fractionalDays(from: start, to: end) / 7.0
    }

    /// Integer number of whole days between two `Date`s — DST-safe.
    ///
    /// Use this for "X days ago" or cooldown checks where the fraction doesn't matter.
    func wholeDays(from start: Date, to end: Date) -> Int {
        return dateComponents([.day], from: start, to: end).day ?? 0
    }
}
