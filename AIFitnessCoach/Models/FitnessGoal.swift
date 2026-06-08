import Foundation
import SwiftData

// MARK: - Epic Goal Intents: Enums

/// The format of the event the user is training for.
enum EventFormat: String, Codable, CaseIterable {
    case singleDayRace  = "single_day_race"
    case singleDayTour  = "single_day_tour"
    case multiDayStage  = "multi_day_stage"

    var displayName: String {
        switch self {
        case .singleDayRace:  return "Eendaagse wedstrijd"
        case .singleDayTour:  return "Eendaagse toertocht"
        case .multiDayStage:  return "Meerdaagse etapperit"
        }
    }
}

/// The user's primary intent for the event.
enum PrimaryIntent: String, Codable, CaseIterable {
    case completion      = "completion"
    case peakPerformance = "peak_performance"

    var displayName: String {
        switch self {
        case .completion:      return "Uitlopen / overleven"
        case .peakPerformance: return "Zo snel mogelijk"
        }
    }
}

/// Represents a user's fitness goal.
/// This model is stored in SwiftData to track local goals.
@Model
final class FitnessGoal {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String?
    var targetDate: Date
    var createdAt: Date
    var isCompleted: Bool
    var sportCategory: SportCategory?
    var targetTRIMP: Double? // Sprint 12.1: load required to reach this goal.

    // Epic Goal Intents — optionals so SwiftData safely loads old records as nil
    var format: EventFormat?
    var intent: PrimaryIntent?
    var stretchGoalTime: TimeInterval?

    /// Epic #55: number of consecutive event days for a multi-day event (e.g. 5 for a
    /// 5-day stage tour). `nil`/≤1 = single-day. `targetDate` is the START day.
    var eventDurationDays: Int?

    /// Safe fallback: always returns a valid EventFormat, even for records without a value.
    ///
    /// Epic #55 story 55.3: a goal with `eventDurationDays > 1` is by definition a
    /// multi-day stage event, so it is treated as `.multiDayStage` regardless of a
    /// missing/legacy `format`. Without this guard a multi-day event with `format == nil`
    /// fell back to `.singleDayRace` — the coach then "raced" the event instead of
    /// treating it as a tour.
    var resolvedFormat: EventFormat {
        if resolvedEventDurationDays > 1 { return .multiDayStage }
        return format ?? .singleDayRace
    }

    /// Safe fallback: always returns a valid PrimaryIntent, even for records without a value.
    ///
    /// Epic #55 story 55.3: a multi-day event without an explicit intent defaults to
    /// `.completion` (you finish a multi-day tour, you don't "peak" across it). An
    /// explicitly chosen intent is always respected.
    /// Epic #56: the free text route extraction reads from — the title plus any notes.
    /// Also the cache-invalidation key: change the text and the resolved route is recomputed.
    var routeSourceText: String {
        [title, details ?? ""].joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    var resolvedIntent: PrimaryIntent {
        if let intent { return intent }
        return resolvedEventDurationDays > 1 ? .completion : .peakPerformance
    }

    // MARK: - Multi-day event window (Epic #55)

    /// Number of event days, clamped to ≥1. A `multiDayStage` without an explicit count
    /// still behaves as a single day until the user sets a duration.
    var resolvedEventDurationDays: Int { max(1, eventDurationDays ?? 1) }

    /// Last day of the event. For a single-day event this equals `startOfDay(targetDate)`.
    var eventEndDate: Date {
        let start = Calendar.current.startOfDay(for: targetDate)
        return Calendar.current.date(byAdding: .day, value: resolvedEventDurationDays - 1, to: start) ?? start
    }

    /// True when `date` falls within the event window `[startOfDay(targetDate) … eventEndDate]`.
    func isEventDay(_ date: Date) -> Bool {
        let day = Calendar.current.startOfDay(for: date)
        return day >= Calendar.current.startOfDay(for: targetDate) && day <= eventEndDate
    }

    /// 1-based stage index for `date` within the event, or `nil` if `date` is outside the window.
    func eventStageIndex(for date: Date) -> Int? {
        guard isEventDay(date) else { return nil }
        let start = Calendar.current.startOfDay(for: targetDate)
        let day = Calendar.current.startOfDay(for: date)
        let offset = Calendar.current.dateComponents([.day], from: start, to: day).day ?? 0
        return offset + 1
    }

    init(id: UUID = UUID(),
         title: String,
         details: String? = nil,
         targetDate: Date,
         createdAt: Date = Date(),
         isCompleted: Bool = false,
         sportCategory: SportCategory? = nil,
         targetTRIMP: Double? = nil,
         format: EventFormat? = .singleDayRace,
         intent: PrimaryIntent? = .peakPerformance,
         stretchGoalTime: TimeInterval? = nil,
         eventDurationDays: Int? = nil) {
        self.id = id
        self.title = title
        self.details = details
        self.targetDate = targetDate
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.sportCategory = sportCategory
        self.targetTRIMP = targetTRIMP
        self.format = format
        self.intent = intent
        self.stretchGoalTime = stretchGoalTime
        self.eventDurationDays = eventDurationDays
    }

    /// Current training phase of this goal based on weeks remaining (Epic 16).
    /// Returns nil if the goal is completed or already expired.
    var currentPhase: TrainingPhase? {
        guard !isCompleted, Date() < targetDate else { return nil }
        return TrainingPhase.calculate(weeksRemaining: weeksRemaining)
    }

    /// Safely computes or returns the Target TRIMP, including a fail-safe fallback formula.
    var computedTargetTRIMP: Double {
        if let trimp = targetTRIMP, trimp > 0 {
            return trimp
        }
        let days = max(1.0, totalDays)
        return (days / 7.0) * 350.0
    }

    // MARK: - DST-safe time calculations (CLAUDE.md §3)

    /// Number of weeks until `targetDate` at the given moment — DST-safe.
    /// Negative if the goal has already expired. Defaults to relative to `Date()`.
    func weeksRemaining(from now: Date = Date()) -> Double {
        Calendar.current.fractionalWeeks(from: now, to: targetDate)
    }

    /// Number of weeks until `targetDate` relative to now (computed-property accessor for `weeksRemaining(from:)`).
    var weeksRemaining: Double { weeksRemaining() }

    /// Number of days until `targetDate` at the given moment — DST-safe.
    /// Negative if the goal has already expired.
    func daysRemaining(from now: Date = Date()) -> Double {
        Calendar.current.fractionalDays(from: now, to: targetDate)
    }

    /// Number of days until `targetDate` relative to now (fractional, DST-safe).
    var daysRemaining: Double { daysRemaining() }

    /// Total number of days between `createdAt` and `targetDate` — DST-safe.
    /// Used for total-training-period calculations (such as the fallback Target TRIMP).
    var totalDays: Double {
        Calendar.current.fractionalDays(from: createdAt, to: targetDate)
    }
}
