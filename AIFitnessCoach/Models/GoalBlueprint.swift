import Foundation

// MARK: - Epic 17: Goal-Specific Blueprints — Data Types

/// Supported blueprint types — detected via keywords in the goal title.
enum GoalBlueprintType: String, CaseIterable {
    case marathon     = "marathon"
    case halfMarathon = "half_marathon"
    case cyclingTour  = "cycling_tour"

    /// Keywords that must appear in the goal title for automatic detection (lowercase).
    var detectionKeywords: [String] {
        switch self {
        case .marathon:
            return ["marathon"]
        case .halfMarathon:
            return ["halve marathon", "half marathon", "21km", "21 km", "21,1"]
        case .cyclingTour:
            return ["arnhem", "karlsruhe", "cycling tour", "fietstocht", "fietsdoel", "gran fondo", "sportieve rit"]
        }
    }

    var displayName: String {
        switch self {
        case .marathon:     return "Marathon"
        case .halfMarathon: return "Halve Marathon"
        case .cyclingTour:  return "Fietstocht"
        }
    }
}

/// A critical training requirement that must be met before a certain moment.
/// Part of a GoalBlueprint — one outstanding requirement keeps the milestone red.
struct EssentialWorkout: Equatable {
    /// Stable identifier for the milestone check (e.g. "marathon_long_run_32")
    let id: String
    /// Readable description for UI and AI context (e.g. "32 km long run")
    let description: String
    /// Minimum distance in metres for this requirement, or nil if duration is leading
    let minimumDistanceMeters: Double?
    /// Required sport type (type-safe via SportCategory)
    let requiredSportCategory: SportCategory
    /// Number of weeks before the end date within which this workout must be completed
    let mustCompleteByWeeksBefore: Int
}

/// Sports-science training plan for a specific goal type.
/// Contains hard rules that — regardless of AI output — always apply.
struct GoalBlueprint {
    let goalType: GoalBlueprintType
    /// Minimum distance of the longest endurance workout in metres (e.g. 32,000 for a marathon)
    let minLongRunDistance: Double
    /// Weeks before the race that the taper period starts
    let taperPeriodWeeks: Int
    /// Weekly TRIMP target during the build phase
    let weeklyTrimpTarget: Double
    /// Critical workouts that must appear in the schedule
    let essentialWorkouts: [EssentialWorkout]
}

/// Progress status of one critical training requirement relative to the deadline.
struct MilestoneStatus: Identifiable, Equatable {
    let id: String
    let description: String
    /// True if a matching activity has been found that satisfies the requirement
    let isSatisfied: Bool
    /// Date on which the requirement was met (only set if isSatisfied == true)
    let satisfiedByDate: Date?
    /// Latest date by which this workout must be done (computed from targetDate)
    let deadline: Date
    /// Number of weeks before the race that this requirement must be completed at the latest
    let weeksBefore: Int
}

/// Full blueprint check for one goal: blueprint + all milestone statuses.
struct BlueprintCheckResult {
    let blueprint: GoalBlueprint
    let goal: FitnessGoal
    let milestones: [MilestoneStatus]

    /// True if all critical requirements whose deadline has already passed are also met.
    var isOnTrack: Bool {
        milestones
            .filter { $0.deadline < Date() }
            .allSatisfy { $0.isSatisfied }
    }

    var satisfiedCount: Int { milestones.filter { $0.isSatisfied }.count }
    var totalCount: Int { milestones.count }
}
