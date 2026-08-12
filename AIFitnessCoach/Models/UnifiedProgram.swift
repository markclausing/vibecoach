import Foundation

// MARK: - Epic #73: Unified multi-goal training program
//
// Value types (no @Model, no schema migration — §2.1) describing the single macrocycle that
// unifies every active goal. Instead of each goal running its own base→build→peak→taper (which
// contradict when races overlap), one A-race anchors the program and interim races are folded in
// as mini-taper tune-ups. Pure Swift, AppStorage-free (§6) so `MacrocyclePlanner` is unit-testable.

/// Race priority within a multi-goal macrocycle. Exactly one **A**-race anchors the program and
/// gets the full taper; **B**/**C** races are interim tune-ups folded in with a mini-taper.
///
/// Stored on `FitnessGoal` from story 73.2 onward; until then `MacrocyclePlanner` derives it from
/// dates (latest race = A). Kept `String, Codable` so the 73.2 SwiftData addition is a pure,
/// lightweight migration.
enum RacePriority: String, Codable, CaseIterable {
    case a = "A"   // main goal — full taper, anchors the macrocycle
    case b = "B"   // secondary race — mini-taper tune-up
    case c = "C"   // low-priority checkpoint — mini-taper tune-up

    /// Lower rank = higher priority. Used to pick the anchor (A beats B beats C).
    var rank: Int {
        switch self {
        case .a: return 0
        case .b: return 1
        case .c: return 2
        }
    }
}

/// A race plotted on the unified macrocycle timeline.
struct RaceMarker: Identifiable, Equatable {
    let goalID: UUID
    let title: String
    let date: Date
    let priority: RacePriority
    /// True for the A-race that anchors the macrocycle.
    let isAnchor: Bool
    /// Start of the short unload before an **interim** race. `nil` for the anchor, which uses the
    /// macrocycle's own taper window instead of a separate mini-taper.
    let miniTaperStart: Date?

    var id: UUID { goalID }
}

/// The single training program that unifies every active goal into one macrocycle.
struct UnifiedProgram {
    /// The A-race whose target date anchors the macrocycle.
    let anchorGoalID: UUID
    /// Macrocycle phase windows (base→build→peak→taper) up to the anchor race.
    let phases: [PhaseWindow]
    /// Every active race on the timeline (anchor + interim), sorted by date ascending.
    let races: [RaceMarker]
    /// The phase in effect **right now** — an interim mini-taper overrides the underlying window.
    let currentPhase: TrainingPhase
    /// True when `now` sits inside an interim race's mini-taper window.
    let inMiniTaper: Bool
    /// Combined weekly TRIMP target for the current week (derived from the anchor's macrocycle,
    /// with the taper multiplier applied during a mini-taper).
    let weeklyTrimpTarget: Double
    /// Program span: earliest goal `createdAt` → anchor `targetDate`.
    let start: Date
    let end: Date

    /// The next race at or after `now`, if any — the one the athlete is training toward.
    func nextRace(after now: Date) -> RaceMarker? {
        races.first { $0.date >= now }
    }

    /// The A-race marker that anchors the macrocycle.
    var anchorRace: RaceMarker? {
        races.first { $0.isAnchor }
    }

    /// Story 73.5: where `date` sits on the program timeline, as a 0...1 fraction of the span.
    /// Drives the x-position of the macrocycle bar's race markers and "you are here" indicator.
    /// Clamped, so a date outside the span pins to an edge instead of drawing off-card.
    func fraction(of date: Date, calendar: Calendar = .current) -> Double {
        let span = calendar.fractionalDays(from: start, to: end)
        guard span > 0 else { return 0 }
        let elapsed = calendar.fractionalDays(from: start, to: date)
        return min(1.0, max(0.0, elapsed / span))
    }

    /// Story 73.3: 1-based program week + total program length, for the dashboard header
    /// ("WK 3/14"). Replaces the old per-goal week maths, which counted from whichever goal
    /// happened to come first in the query and therefore disagreed with the macrocycle bar.
    /// Clamped to `1...total` so a `now` outside the span still reads sensibly.
    func programWeek(at now: Date, calendar: Calendar = .current) -> (current: Int, total: Int) {
        let totalWeeks = calendar.fractionalDays(from: start, to: end) / 7.0
        let total = max(1, Int(totalWeeks.rounded(.up)))
        let elapsedWeeks = calendar.fractionalDays(from: start, to: now) / 7.0
        let current = min(max(1, Int(elapsedWeeks.rounded(.down)) + 1), total)
        return (current, total)
    }
}
