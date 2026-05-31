import Foundation

// MARK: - Epic 17: BlueprintChecker

/// Compares the user's training history with sports-science hard rules
/// per goal type. Returns a list of satisfied and outstanding critical requirements (milestones).
struct BlueprintChecker {

    // MARK: - Hardcoded Blueprints

    /// Marathon Blueprint — sports-science rules for 42.195 km race preparation.
    /// Source: Daniels' Running Formula / Pfitzinger & Douglas periodisation model.
    static let marathonBlueprint = GoalBlueprint(
        goalType: .marathon,
        minLongRunDistance: 32_000,  // 32 km minimum peak long run
        taperPeriodWeeks: 3,
        weeklyTrimpTarget: 500,
        essentialWorkouts: [
            EssentialWorkout(
                id: "marathon_long_run_28",
                description: "28 km duurloop",
                minimumDistanceMeters: 28_000,
                requiredSportCategory: .running,
                mustCompleteByWeeksBefore: 6
            ),
            EssentialWorkout(
                id: "marathon_long_run_32",
                description: "32 km duurloop",
                minimumDistanceMeters: 32_000,
                requiredSportCategory: .running,
                mustCompleteByWeeksBefore: 3
            )
        ]
    )

    /// Half Marathon Blueprint — sports-science rules for 21.1 km race preparation.
    static let halfMarathonBlueprint = GoalBlueprint(
        goalType: .halfMarathon,
        minLongRunDistance: 18_000,  // 18 km minimum peak long run
        taperPeriodWeeks: 2,
        weeklyTrimpTarget: 350,
        essentialWorkouts: [
            EssentialWorkout(
                id: "half_marathon_long_run_16",
                description: "16 km duurloop",
                minimumDistanceMeters: 16_000,
                requiredSportCategory: .running,
                mustCompleteByWeeksBefore: 4
            ),
            EssentialWorkout(
                id: "half_marathon_long_run_18",
                description: "18 km duurloop",
                minimumDistanceMeters: 18_000,
                requiredSportCategory: .running,
                mustCompleteByWeeksBefore: 2
            )
        ]
    )

    /// Cycling-goal Blueprint — sports-science rules for a multi-day cycling tour
    /// (e.g. Arnhem–Karlsruhe ±400 km over 4 days, ~100 km/day average).
    static let cyclingTourBlueprint = GoalBlueprint(
        goalType: .cyclingTour,
        minLongRunDistance: 100_000,  // 100 km minimum long ride
        taperPeriodWeeks: 2,
        weeklyTrimpTarget: 400,
        essentialWorkouts: [
            EssentialWorkout(
                id: "cycling_medium_ride_60",
                description: "60 km duurrit",
                minimumDistanceMeters: 60_000,
                requiredSportCategory: .cycling,
                mustCompleteByWeeksBefore: 8
            ),
            EssentialWorkout(
                id: "cycling_long_ride_100",
                description: "100 km duurrit",
                minimumDistanceMeters: 100_000,
                requiredSportCategory: .cycling,
                mustCompleteByWeeksBefore: 4
            )
        ]
    )

    // MARK: - Blueprint detection

    /// Detects the blueprint type based on keywords in the goal title.
    /// Falls back to the SportCategory if there is no title match.
    static func detectBlueprintType(for goal: FitnessGoal) -> GoalBlueprintType? {
        let title = goal.title.lowercased()

        // Check half marathon before marathon — "marathon" is also contained in "halve marathon"
        for type in [GoalBlueprintType.halfMarathon, .marathon, .cyclingTour]
            where type.detectionKeywords.contains(where: { title.contains($0) }) {
            return type
        }

        // Fall back to SportCategory
        switch goal.sportCategory {
        case .running:  return .marathon
        case .cycling:  return .cyclingTour
        default:        return nil
        }
    }

    static func blueprint(for type: GoalBlueprintType) -> GoalBlueprint {
        switch type {
        case .marathon:     return marathonBlueprint
        case .halfMarathon: return halfMarathonBlueprint
        case .cyclingTour:  return cyclingTourBlueprint
        }
    }

    // MARK: - Milestone Check

    /// Compares the activity history with the blueprint's critical requirements for one goal.
    /// - Returns: A BlueprintCheckResult with all milestones, or nil if no blueprint applies.
    static func check(goal: FitnessGoal, activities: [ActivityRecord]) -> BlueprintCheckResult? {
        guard let blueprintType = detectBlueprintType(for: goal) else { return nil }
        let bp = blueprint(for: blueprintType)

        let milestones: [MilestoneStatus] = bp.essentialWorkouts.map { workout in
            // Deadline = targetDate minus N weeks
            let deadline = Calendar.current.date(
                byAdding: .weekOfYear,
                value: -workout.mustCompleteByWeeksBefore,
                to: goal.targetDate
            ) ?? goal.targetDate

            // Find the earliest activity that meets all requirements (sport + distance + before deadline)
            let satisfyingActivity = activities.first { record in
                guard record.sportCategory == workout.requiredSportCategory else { return false }
                guard record.startDate <= deadline else { return false }
                if let minDist = workout.minimumDistanceMeters {
                    return record.distance >= minDist
                }
                return true
            }

            return MilestoneStatus(
                id: workout.id,
                description: workout.description,
                isSatisfied: satisfyingActivity != nil,
                satisfiedByDate: satisfyingActivity?.startDate,
                deadline: deadline,
                weeksBefore: workout.mustCompleteByWeeksBefore
            )
        }

        return BlueprintCheckResult(blueprint: bp, goal: goal, milestones: milestones)
    }

    /// Checks all active goals and returns results sorted by urgency
    /// (goals with outstanding milestones first).
    static func checkAllGoals(_ goals: [FitnessGoal], activities: [ActivityRecord]) -> [BlueprintCheckResult] {
        let now = Date()
        return goals
            .filter { !$0.isCompleted && now < $0.targetDate }
            .compactMap { check(goal: $0, activities: activities) }
            .sorted { !$0.isOnTrack && $1.isOnTrack }
    }
}
