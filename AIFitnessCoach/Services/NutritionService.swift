import Foundation

// MARK: - Epic 24 Sprint 1: Nutrition & Fueling Engine

/// Trainingszone — bepaalt de metabole brandstofmix en het zweetverlies.
enum TrainingZone: Int, CaseIterable {
    case zone2 = 2  // aeroob, vetverbranding dominant, ~60–70% HRmax
    case zone4 = 4  // lactaatdrempel, glycogeen dominant, ~80–90% HRmax

    var displayName: String {
        switch self {
        case .zone2: return "Zone 2 (aeroob)"
        case .zone4: return "Zone 4 (drempeltraining)"
    }
    }
}

/// Berekende voedingsbehoefte voor één trainingsblok.
struct WorkoutFuelingPlan {
    let durationMinutes: Int
    let zone: TrainingZone

    /// Calorieverbranding inclusief BMR-aandeel tijdens de training.
    let totalCaloriesBurned: Double
    /// Koolhydratenbehoefte in gram (aanbevolen inname rondom de training).
    let carbsGram: Double
    /// Vochtinname in milliliter (tijdens de workout).
    let fluidMl: Double

    /// Leesbare samenvatting voor de coach-prompt.
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

/// Berekent de voedingsbehoefte op basis van het fysiologisch profiel + trainingsbelasting.
///
/// **Wetenschappelijke basis:**
/// - BMR via Mifflin-St Jeor (nauwkeuriger dan Harris-Benedict voor actieve populaties)
/// - MET-waarden: Zone 2 = 6 MET (rustig hardlopen/fietsen), Zone 4 = 10 MET
/// - Koolhydraten: Zone 2 = ~0.5 g/min, Zone 4 = ~1.0 g/min (Burke et al., 2011)
/// - Vocht: ~500 ml/uur (Zone 2) → ~800 ml/uur (Zone 4) — ACSM richtlijnen
struct NutritionService {

    // MARK: - MET-waarden per zone

    private static let metZone2: Double = 6.0
    private static let metZone4: Double = 10.0

    // MARK: - Koolhydraten per minuut (gram)

    private static let carbsPerMinZone2: Double = 0.5
    private static let carbsPerMinZone4: Double = 1.0

    // MARK: - Vocht per minuut (ml)

    private static let fluidMlPerMinZone2: Double = 500.0 / 60.0  // ~8.3 ml/min
    private static let fluidMlPerMinZone4: Double = 800.0 / 60.0  // ~13.3 ml/min

    // MARK: - BMR berekening

    /// Berekent het basaal metabolisme (kcal/dag) via de Mifflin-St Jeor formule.
    /// Man:   (10 × gewicht kg) + (6.25 × lengte cm) − (5 × leeftijd) + 5
    /// Vrouw: (10 × gewicht kg) + (6.25 × lengte cm) − (5 × leeftijd) − 161
    static func calculateBMR(profile: UserPhysicalProfile) -> Double {
        let base = (10 * profile.weightKg) + (6.25 * profile.heightCm) - (5 * Double(profile.ageYears))
        switch profile.sex {
        case .male:            return base + 5
        case .female:          return base - 161
        case .other, .unknown: return base - 78  // gemiddelde van man/vrouw offset
        }
    }

    // MARK: - Trainingsverbranding

    /// Berekent de calorieverbranding voor een trainingsblok.
    /// Formule: MET × gewicht (kg) × tijd (uur)
    static func caloriesBurned(durationMinutes: Int, zone: TrainingZone, weightKg: Double) -> Double {
        let met: Double = zone == .zone2 ? metZone2 : metZone4
        let hours = Double(durationMinutes) / 60.0
        return met * weightKg * hours
    }

    // MARK: - Volledige voedingsplan

    /// Stelt een compleet fueling-plan op voor één workout.
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

    // MARK: - SuggestedWorkout integratie

    /// Bepaalt de trainingszone op basis van het hartslagzone- of beschrijvingsveld.
    static func zone(for workout: SuggestedWorkout) -> TrainingZone {
        let text = ((workout.heartRateZone ?? "") + " " + workout.description).lowercased()
        let isHigh = text.contains("interval") || text.contains("tempo")
            || text.contains("drempel") || text.contains("zone 4") || text.contains("z4")
        return isHigh ? .zone4 : .zone2
    }

    /// Berekent het voedingsplan voor een `SuggestedWorkout` op basis van het gecachte profiel.
    /// Geeft `nil` terug voor rustdagen of workouts zonder duur.
    static func fuelingPlan(for workout: SuggestedWorkout, profile: UserPhysicalProfile) -> WorkoutFuelingPlan? {
        guard workout.suggestedDurationMinutes > 0,
              workout.activityType.lowercased() != "rust" else { return nil }
        return fuelingPlan(
            durationMinutes: workout.suggestedDurationMinutes,
            zone: zone(for: workout),
            profile: profile
        )
    }

    // MARK: - Interval-verdeling

    /// Breekt het voedingsplan op in vaste intervallen voor de detailweergave.
    /// Bijv. elke 15 min: drink X ml, eet Y g koolhydraten.
    struct FuelingInterval {
        let intervalMinutes: Int
        let fluidMl: Double
        let carbsGram: Double
    }

    static func intervalBreakdown(plan: WorkoutFuelingPlan, every intervalMinutes: Int = 15) -> FuelingInterval {
        let intervals = max(1.0, Double(plan.durationMinutes) / Double(intervalMinutes))
        return FuelingInterval(
            intervalMinutes: intervalMinutes,
            fluidMl:   plan.fluidMl   / intervals,
            carbsGram: plan.carbsGram / intervals
        )
    }

    // MARK: - Coach prompt blok

    /// Bouwt het `[VOEDING & FYSIOLOGIE]` blok voor de AI-prompt.
    /// Bevat BMR, profiel-samenvatting en fueling-plannen voor vandaag en morgen.
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
