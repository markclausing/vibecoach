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
}
