import Foundation

// MARK: - Epic 24 Sprint 1: Nutrition & Fueling Engine

/// Training zone — determines the metabolic fuel mix and sweat loss.
enum TrainingZone: Int, CaseIterable {
    case zone2 = 2  // aerobic, fat burning dominant, ~60–70% HRmax
    case zone4 = 4  // lactate threshold, glycogen dominant, ~80–90% HRmax

    var displayName: String {
        switch self {
        case .zone2: return "Zone 2 (aeroob)"
        case .zone4: return "Zone 4 (drempeltraining)"
    }
    }
}

/// Computed nutrition requirement for one training block.
struct WorkoutFuelingPlan {
    let durationMinutes: Int
    let zone: TrainingZone

    /// Calorie burn including the BMR share during the training.
    let totalCaloriesBurned: Double
    /// Carbohydrate need in grams (recommended intake around the training).
    let carbsGram: Double
    /// Fluid intake in millilitres (during the workout).
    let fluidMl: Double

    /// Readable summary for the coach prompt.
    var coachSummary: String {
        let carbsRounded = Int(carbsGram.rounded())
        let fluidRounded = Int(fluidMl.rounded())
        let calRounded   = Int(totalCaloriesBurned.rounded())
        return """
        \(durationMinutes) min \(zone.displayName): \
        ~\(calRounded) kcal, ~\(carbsRounded) g koolhydraten, ~\(fluidRounded) ml vocht
        """
    }
}

/// Computes the nutrition requirement based on the physiological profile + training load.
///
/// **Scientific basis:**
/// - BMR via Mifflin-St Jeor (more accurate than Harris-Benedict for active populations)
/// - MET values: Zone 2 = 6 MET (easy running/cycling), Zone 4 = 10 MET
/// - Carbohydrates: Zone 2 = ~0.5 g/min, Zone 4 = ~1.0 g/min (Burke et al., 2011)
/// - Fluid: ~500 ml/hour (Zone 2) → ~800 ml/hour (Zone 4) — ACSM guidelines
struct NutritionService {

    // MARK: - MET values per zone

    private static let metZone2: Double = 6.0
    private static let metZone4: Double = 10.0

    // MARK: - Carbohydrates per minute (grams)

    private static let carbsPerMinZone2: Double = 0.5
    private static let carbsPerMinZone4: Double = 1.0

    // MARK: - Fluid per minute (ml)

    private static let fluidMlPerMinZone2: Double = 500.0 / 60.0  // ~8.3 ml/min
    private static let fluidMlPerMinZone4: Double = 800.0 / 60.0  // ~13.3 ml/min

    // MARK: - BMR calculation

    /// Computes the basal metabolic rate (kcal/day) via the Mifflin-St Jeor formula.
    /// Male:   (10 × weight kg) + (6.25 × height cm) − (5 × age) + 5
    /// Female: (10 × weight kg) + (6.25 × height cm) − (5 × age) − 161
    static func calculateBMR(profile: UserPhysicalProfile) -> Double {
        let base = (10 * profile.weightKg) + (6.25 * profile.heightCm) - (5 * Double(profile.ageYears))
        switch profile.sex {
        case .male:            return base + 5
        case .female:          return base - 161
        case .other, .unknown: return base - 78  // average of male/female offset
        }
    }

    // MARK: - Training burn

    /// Computes the calorie burn for a training block.
    /// Formula: MET × weight (kg) × time (hours)
    static func caloriesBurned(durationMinutes: Int, zone: TrainingZone, weightKg: Double) -> Double {
        let met: Double = zone == .zone2 ? metZone2 : metZone4
        let hours = Double(durationMinutes) / 60.0
        return met * weightKg * hours
    }

    // MARK: - Full fueling plan

    /// Builds a complete fueling plan for one workout.
    static func fuelingPlan(
        durationMinutes: Int,
        zone: TrainingZone,
        profile: UserPhysicalProfile
    ) -> WorkoutFuelingPlan {
        let calories = caloriesBurned(durationMinutes: durationMinutes, zone: zone, weightKg: profile.weightKg)
        let carbs    = zone == .zone2
            ? carbsPerMinZone2 * Double(durationMinutes)
            : carbsPerMinZone4 * Double(durationMinutes)
        let fluid    = zone == .zone2
            ? fluidMlPerMinZone2 * Double(durationMinutes)
            : fluidMlPerMinZone4 * Double(durationMinutes)

        return WorkoutFuelingPlan(
            durationMinutes: durationMinutes,
            zone: zone,
            totalCaloriesBurned: calories,
            carbsGram: carbs,
            fluidMl: fluid
        )
    }

    // MARK: - SuggestedWorkout integration

    /// Determines the training zone based on the heart-rate-zone or description field.
    static func zone(for workout: SuggestedWorkout) -> TrainingZone {
        let text = ((workout.heartRateZone ?? "") + " " + workout.description).lowercased()
        let isHigh = text.contains("interval") || text.contains("tempo")
            || text.contains("drempel") || text.contains("zone 4") || text.contains("z4")
        return isHigh ? .zone4 : .zone2
    }

    /// Computes the fueling plan for a `SuggestedWorkout` based on the cached profile.
    /// Returns `nil` for rest days or workouts without a duration.
    static func fuelingPlan(for workout: SuggestedWorkout, profile: UserPhysicalProfile) -> WorkoutFuelingPlan? {
        guard workout.suggestedDurationMinutes > 0,
              workout.activityType.lowercased() != "rust" else { return nil }
        return fuelingPlan(
            durationMinutes: workout.suggestedDurationMinutes,
            zone: zone(for: workout),
            profile: profile
        )
    }

    // MARK: - Interval breakdown

    /// Breaks the fueling plan into fixed intervals for the detail view.
    /// E.g. every 15 min: drink X ml, eat Y g carbohydrates.
    struct FuelingInterval {
        let intervalMinutes: Int
        let fluidMl: Double
        let carbsGram: Double
    }

    static func intervalBreakdown(plan: WorkoutFuelingPlan, every intervalMinutes: Int = 15) -> FuelingInterval {
        let intervals = max(1.0, Double(plan.durationMinutes) / Double(intervalMinutes))
        return FuelingInterval(
            intervalMinutes: intervalMinutes,
            fluidMl: plan.fluidMl   / intervals,
            carbsGram: plan.carbsGram / intervals
        )
    }

    // MARK: - Coach prompt block

    /// Builds the `[VOEDING & FYSIOLOGIE]` block for the AI prompt.
    /// Contains BMR, profile summary and fueling plans for today and tomorrow.
    static func buildCoachContext(
        profile: UserPhysicalProfile,
        todayWorkouts: [(durationMinutes: Int, zone: TrainingZone)],
        tomorrowWorkouts: [(durationMinutes: Int, zone: TrainingZone)]
    ) -> String {
        let bmr = Int(calculateBMR(profile: profile).rounded())
        var lines = [String]()
        lines.append("[VOEDING & FYSIOLOGIE]")
        lines.append("Fysiologisch profiel: \(profile.coachSummary)")
        lines.append("Basaal metabolisme (BMR): ~\(bmr) kcal/dag")

        if !todayWorkouts.isEmpty {
            lines.append("Workouts vandaag:")
            for w in todayWorkouts {
                let plan = fuelingPlan(durationMinutes: w.durationMinutes, zone: w.zone, profile: profile)
                lines.append("  • \(plan.coachSummary)")
            }
        }
        if !tomorrowWorkouts.isEmpty {
            lines.append("Workouts morgen:")
            for w in tomorrowWorkouts {
                let plan = fuelingPlan(durationMinutes: w.durationMinutes, zone: w.zone, profile: profile)
                lines.append("  • \(plan.coachSummary)")
            }
        }

        lines.append("""
        Instructies voor de coach:
        - Geef concrete koolhydraten- en vocht-adviezen (gram en ml) passend bij bovenstaande workouts.
        - Noem altijd de timing: voor, tijdens en na de training.
        - Houd rekening met het BMR: de dagelijkse energiebehoefte ligt hoger dan alleen de trainingsverbranding.
        - Pas adviezen aan op basis van de Vibe Score: bij herstel (<50) voedingsfocus op eiwitten en hydratie; bij vol gas (≥80) koolhydraatloading voor lange sessies.
        """)

        return lines.joined(separator: "\n")
    }
}
