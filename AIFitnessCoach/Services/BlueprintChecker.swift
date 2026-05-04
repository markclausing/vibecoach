import Foundation

// MARK: - Epic 17: BlueprintChecker

/// Vergelijkt de trainingshistorie van de gebruiker met sportwetenschappelijke harde regels
/// per doeltype. Retourneert een lijst van voldane en openstaande kritieke eisen (milestones).
struct BlueprintChecker {

    // MARK: - Hardcoded Blueprints

    /// Marathon Blueprint — sportwetenschappelijke regels voor 42.195 km race-voorbereiding.
    /// Bron: Daniels' Running Formula / Pfitzinger & Douglas periodiseringsmodel.
    static let marathonBlueprint = GoalBlueprint(
        goalType: .marathon,
        minLongRunDistance: 32_000,  // 32 km minimale piekduurloop
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

    /// Halve Marathon Blueprint — sportwetenschappelijke regels voor 21.1 km race-voorbereiding.
    static let halfMarathonBlueprint = GoalBlueprint(
        goalType: .halfMarathon,
        minLongRunDistance: 18_000,  // 18 km minimale piekduurloop
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

    /// Fietsdoel Blueprint — sportwetenschappelijke regels voor een meerdaagse fietstocht
    /// (bijv. Arnhem–Karlsruhe ±400 km over 4 dagen, ~100 km/dag gemiddeld).
    static let cyclingTourBlueprint = GoalBlueprint(
        goalType: .cyclingTour,
        minLongRunDistance: 100_000,  // 100 km minimale lange duurrit
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

    // MARK: - Blueprint detectie

    /// Detecteert het blueprint-type op basis van sleutelwoorden in de doeltitel.
    /// Valt terug op de SportCategory als er geen titelmatch is.
    static func detectBlueprintType(for goal: FitnessGoal) -> GoalBlueprintType? {
        let title = goal.title.lowercased()

        // Halve marathon vóór marathon checken — "marathon" zit ook in "halve marathon"
        for type in [GoalBlueprintType.halfMarathon, .marathon, .cyclingTour] {
            if type.detectionKeywords.contains(where: { title.contains($0) }) {
                return type
            }
        }

        // Fallback op SportCategory
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

    /// Vergelijkt de activiteitenhistorie met de kritieke eisen van het blueprint voor één doel.
    /// - Returns: BlueprintCheckResult met alle milestones, of nil als er geen blueprint van toepassing is.
    static func check(goal: FitnessGoal, activities: [ActivityRecord]) -> BlueprintCheckResult? {
        guard let blueprintType = detectBlueprintType(for: goal) else { return nil }
        let bp = blueprint(for: blueprintType)

        let milestones: [MilestoneStatus] = bp.essentialWorkouts.map { workout in
            // Deadline = targetDate minus N weken
            let deadline = Calendar.current.date(
                byAdding: .weekOfYear,
                value: -workout.mustCompleteByWeeksBefore,
                to: goal.targetDate
            ) ?? goal.targetDate

            // Zoek de vroegste activiteit die aan alle eisen voldoet (sport + afstand + vóór deadline)
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

    /// Controleert alle actieve doelen en retourneert resultaten gesorteerd op urgentie
    /// (doelen met openstaande milestones eerst).
    static func checkAllGoals(_ goals: [FitnessGoal], activities: [ActivityRecord]) -> [BlueprintCheckResult] {
        let now = Date()
        return goals
            .filter { !$0.isCompleted && now < $0.targetDate }
            .compactMap { check(goal: $0, activities: activities) }
            .sorted { !$0.isOnTrack && $1.isOnTrack }
    }
}
