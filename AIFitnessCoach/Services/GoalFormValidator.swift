import Foundation

/// Epic #62 story 62.1 — pure-Swift validation for the goal create/edit form.
///
/// AppStorage-free and UI-free (§6): the caller injects `now`/`calendar` and maps the
/// results to DatePicker bounds, the Save gate and inline warnings. Returning value types
/// (not localised strings) keeps it trivially testable; the View owns the copy.
enum GoalFormValidator {

    // MARK: - Target date

    /// A goal's target date must be at least this many days in the future. Closer than this
    /// leaves no room for a meaningful training block — the periodisation phases would
    /// collapse onto (almost) a single day.
    static let minimumLeadDays = 7

    /// Earliest target date the user may pick — `now` + `minimumLeadDays`, normalised to the
    /// start of that day. Use as the DatePicker lower bound. Calendar-based (§3, DST-safe).
    static func earliestTargetDate(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        let startToday = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: minimumLeadDays, to: startToday) ?? startToday
    }

    /// True when `targetDate`'s day is on or after the earliest allowed day. Compares whole
    /// days, not raw seconds, so a same-day pick later than `now` still counts correctly.
    static func isTargetDateValid(_ targetDate: Date, from now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: targetDate) >= earliestTargetDate(from: now, calendar: calendar)
    }

    // MARK: - Title

    /// Trims surrounding whitespace/newlines from a goal title before it is stored, so a
    /// "   " title can't slip past the non-empty Save gate and stored titles stay clean.
    static func sanitizedTitle(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when, after trimming, the title carries at least one visible character.
    static func isTitleValid(_ raw: String) -> Bool {
        !sanitizedTitle(raw).isEmpty
    }

    // MARK: - Stretch (target finish) time plausibility

    /// Verdict for a chosen stretch (target finish) time relative to its sport.
    enum StretchTimePlausibility: Equatable {
        case ok
        case zero       // toggle on but no time set
        case tooFast    // faster than is physically plausible for the sport
        case tooSlow    // longer than a realistic single event
    }

    /// A plausible finish-time band per sport for a single event. Outside this band a stretch
    /// time is almost certainly a mis-entry (e.g. a 4-minute marathon target, or a 20-hour run).
    /// Bounds are deliberately wide — this drives a soft warning, never a hard gate.
    static func plausibleFinishRange(for sport: SportCategory) -> ClosedRange<TimeInterval> {
        let m = 60.0, h = 3600.0
        switch sport {
        case .running:          return (10 * m)...(12 * h)
        case .cycling:          return (15 * m)...(24 * h)
        case .swimming:         return (3 * m)...(6 * h)
        case .walking:          return (20 * m)...(24 * h)
        case .triathlon:        return (20 * m)...(20 * h)
        case .strength, .other: return (1 * m)...(24 * h)
        }
    }

    /// Classifies a stretch time for the given sport. The View maps the verdict to copy and
    /// shows it inline; it never blocks saving (the athlete may legitimately know better).
    static func stretchTimePlausibility(seconds: TimeInterval, sport: SportCategory) -> StretchTimePlausibility {
        guard seconds > 0 else { return .zero }
        let range = plausibleFinishRange(for: sport)
        if seconds < range.lowerBound { return .tooFast }
        if seconds > range.upperBound { return .tooSlow }
        return .ok
    }
}
