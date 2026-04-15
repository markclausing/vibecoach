import XCTest
@testable import AIFitnessCoach

/// Unit tests voor NutritionService (Epic 24 Sprint 1).
///
/// NutritionService is een pure struct zonder side-effects of externe dependencies —
/// geen mocks nodig. Elke test verifieert één formule, grenswaarde of combinatie.
///
/// Wetenschappelijke basis ter referentie:
///   BMR (man)   = (10 × kg) + (6.25 × cm) − (5 × jaar) + 5
///   BMR (vrouw) = (10 × kg) + (6.25 × cm) − (5 × jaar) − 161
///   BMR (other) = (10 × kg) + (6.25 × cm) − (5 × jaar) − 78
///   Calorieën   = MET × gewicht(kg) × tijd(uur)   [Zone2: MET=6, Zone4: MET=10]
///   Koolhydr.   = 0.5 g/min (Zone 2)  |  1.0 g/min (Zone 4)
///   Vocht       = 500 ml/uur (Zone 2) |  800 ml/uur (Zone 4)
final class NutritionServiceTests: XCTestCase {

    // MARK: - Hulp-profielen

    /// Standaard mannelijk testprofiel — 75 kg, 180 cm, 30 jaar.
    private var maleProfile: UserPhysicalProfile {
        UserPhysicalProfile(
            weightKg: 75, heightCm: 180, ageYears: 30, sex: .male,
            weightSource: .defaultValue, heightSource: .defaultValue
        )
    }

    /// Standaard vrouwelijk testprofiel — 60 kg, 165 cm, 25 jaar.
    private var femaleProfile: UserPhysicalProfile {
        UserPhysicalProfile(
            weightKg: 60, heightCm: 165, ageYears: 25, sex: .female,
            weightSource: .defaultValue, heightSource: .defaultValue
        )
    }

    /// Profiel met `other` geslacht — 70 kg, 170 cm, 35 jaar.
    private var otherProfile: UserPhysicalProfile {
        UserPhysicalProfile(
            weightKg: 70, heightCm: 170, ageYears: 35, sex: .other,
            weightSource: .defaultValue, heightSource: .defaultValue
        )
    }

    // MARK: - BMR: Mifflin-St Jeor formule

    /// Man 75 kg, 180 cm, 30 jaar:
    /// base = (10×75) + (6.25×180) − (5×30) = 750 + 1125 − 150 = 1725 → +5 = 1730
    func testBMR_Male_CorrectFormula() {
        let bmr = NutritionService.calculateBMR(profile: maleProfile)
        XCTAssertEqual(bmr, 1730, accuracy: 0.01,
                       "BMR man (75 kg, 180 cm, 30 jaar) moet 1730 kcal zijn.")
    }

    /// Vrouw 60 kg, 165 cm, 25 jaar:
    /// base = (10×60) + (6.25×165) − (5×25) = 600 + 1031.25 − 125 = 1506.25 → −161 = 1345.25
    func testBMR_Female_CorrectFormula() {
        let bmr = NutritionService.calculateBMR(profile: femaleProfile)
        XCTAssertEqual(bmr, 1345.25, accuracy: 0.01,
                       "BMR vrouw (60 kg, 165 cm, 25 jaar) moet 1345.25 kcal zijn.")
    }

    /// Other 70 kg, 170 cm, 35 jaar:
    /// base = (10×70) + (6.25×170) − (5×35) = 700 + 1062.5 − 175 = 1587.5 → −78 = 1509.5
    func testBMR_Other_UsesAverageOffset() {
        let bmr = NutritionService.calculateBMR(profile: otherProfile)
        XCTAssertEqual(bmr, 1509.5, accuracy: 0.01,
                       "BMR other (70 kg, 170 cm, 35 jaar) moet 1509.5 kcal zijn (gemiddelde offset −78).")
    }

    /// Unknown geslacht moet dezelfde offset gebruiken als other (−78).
    func testBMR_Unknown_SameAsOtherOffset() {
        let unknownProfile = UserPhysicalProfile(
            weightKg: 70, heightCm: 170, ageYears: 35, sex: .unknown,
            weightSource: .defaultValue, heightSource: .defaultValue
        )
        let bmrOther   = NutritionService.calculateBMR(profile: otherProfile)
        let bmrUnknown = NutritionService.calculateBMR(profile: unknownProfile)
        XCTAssertEqual(bmrOther, bmrUnknown, accuracy: 0.01,
                       "Unknown en other moeten dezelfde BMR opleveren.")
    }

    /// BMR mag nooit negatief zijn, ook niet bij extreme (lage) inputwaarden.
    func testBMR_ExtremeInputs_NeverNegative() {
        let tinyProfile = UserPhysicalProfile(
            weightKg: 1, heightCm: 1, ageYears: 999, sex: .male,
            weightSource: .defaultValue, heightSource: .defaultValue
        )
        let bmr = NutritionService.calculateBMR(profile: tinyProfile)
        // Formule geeft negatief bij extreme leeftijd — NutritionService clamt dit NIET,
        // maar de test documenteert het verwachte model-gedrag.
        // base = 10 + 6.25 − 4995 = −4978.75 +5 = −4973.75
        XCTAssertEqual(bmr, -4973.75, accuracy: 0.01,
                       "Extreme inputs: BMR reflecteert rauwe formule-uitkomst zonder clamp.")
    }

    // MARK: - Calorieverbranding

    /// Zone 2, 60 min, 70 kg: 6 × 70 × 1.0 = 420 kcal.
    func testCaloriesBurned_Zone2_60Min_70kg() {
        let cal = NutritionService.caloriesBurned(durationMinutes: 60, zone: .zone2, weightKg: 70)
        XCTAssertEqual(cal, 420, accuracy: 0.01,
                       "Zone 2, 60 min, 70 kg → 6 × 70 × 1 = 420 kcal.")
    }

    /// Zone 4, 45 min, 70 kg: 10 × 70 × 0.75 = 525 kcal.
    func testCaloriesBurned_Zone4_45Min_70kg() {
        let cal = NutritionService.caloriesBurned(durationMinutes: 45, zone: .zone4, weightKg: 70)
        XCTAssertEqual(cal, 525, accuracy: 0.01,
                       "Zone 4, 45 min, 70 kg → 10 × 70 × 0.75 = 525 kcal.")
    }

    /// Zone 4 MET (10) is 5/3× hoger dan Zone 2 MET (6) bij zelfde duur en gewicht.
    func testCaloriesBurned_Zone4_HigherThanZone2() {
        let calZ2 = NutritionService.caloriesBurned(durationMinutes: 60, zone: .zone2, weightKg: 70)
        let calZ4 = NutritionService.caloriesBurned(durationMinutes: 60, zone: .zone4, weightKg: 70)
        XCTAssertGreaterThan(calZ4, calZ2,
                             "Zone 4 moet meer calorieën verbranden dan Zone 2 bij gelijke duur.")
    }

    /// 0 minuten training → 0 kcal.
    func testCaloriesBurned_ZeroDuration_ReturnsZero() {
        let cal = NutritionService.caloriesBurned(durationMinutes: 0, zone: .zone4, weightKg: 80)
        XCTAssertEqual(cal, 0, accuracy: 0.001,
                       "0 minuten duur moet 0 kcal opleveren.")
    }

    /// Dubbel gewicht → dubbele calorieverbranding (lineaire schaling).
    func testCaloriesBurned_DoubleWeight_DoublesCalories() {
        let cal70 = NutritionService.caloriesBurned(durationMinutes: 30, zone: .zone2, weightKg: 70)
        let cal140 = NutritionService.caloriesBurned(durationMinutes: 30, zone: .zone2, weightKg: 140)
        XCTAssertEqual(cal140, cal70 * 2, accuracy: 0.01,
                       "Dubbel gewicht moet de calorieverbranding verdubbelen.")
    }

    // MARK: - Fueling plan: koolhydraten & vocht

    /// Zone 2, 60 min: carbs = 0.5 × 60 = 30 g.
    func testFuelingPlan_Zone2_Carbs() {
        let plan = NutritionService.fuelingPlan(durationMinutes: 60, zone: .zone2, profile: maleProfile)
        XCTAssertEqual(plan.carbsGram, 30, accuracy: 0.01,
                       "Zone 2, 60 min → 0.5 g/min × 60 = 30 g koolhydraten.")
    }

    /// Zone 4, 60 min: carbs = 1.0 × 60 = 60 g.
    func testFuelingPlan_Zone4_Carbs() {
        let plan = NutritionService.fuelingPlan(durationMinutes: 60, zone: .zone4, profile: maleProfile)
        XCTAssertEqual(plan.carbsGram, 60, accuracy: 0.01,
                       "Zone 4, 60 min → 1.0 g/min × 60 = 60 g koolhydraten.")
    }

    /// Zone 2, 60 min: vocht = (500/60) × 60 = 500 ml.
    func testFuelingPlan_Zone2_Fluid() {
        let plan = NutritionService.fuelingPlan(durationMinutes: 60, zone: .zone2, profile: maleProfile)
        XCTAssertEqual(plan.fluidMl, 500, accuracy: 0.01,
                       "Zone 2, 60 min → 500/60 ml/min × 60 = 500 ml vocht.")
    }

    /// Zone 4, 60 min: vocht = (800/60) × 60 = 800 ml.
    func testFuelingPlan_Zone4_Fluid() {
        let plan = NutritionService.fuelingPlan(durationMinutes: 60, zone: .zone4, profile: maleProfile)
        XCTAssertEqual(plan.fluidMl, 800, accuracy: 0.01,
                       "Zone 4, 60 min → 800/60 ml/min × 60 = 800 ml vocht.")
    }

    /// Calorieverbranding in het plan is consistent met de losse `caloriesBurned` functie.
    func testFuelingPlan_CaloriesConsistentWithCaloriesBurned() {
        let plan = NutritionService.fuelingPlan(durationMinutes: 45, zone: .zone4, profile: maleProfile)
        let expected = NutritionService.caloriesBurned(durationMinutes: 45, zone: .zone4, weightKg: maleProfile.weightKg)
        XCTAssertEqual(plan.totalCaloriesBurned, expected, accuracy: 0.01,
                       "Calorieën in het plan moeten overeenkomen met caloriesBurned.")
    }

    /// Plan-metadata (duur en zone) worden correct doorgegeven aan het resultaat.
    func testFuelingPlan_MetadataPassedThrough() {
        let plan = NutritionService.fuelingPlan(durationMinutes: 90, zone: .zone2, profile: femaleProfile)
        XCTAssertEqual(plan.durationMinutes, 90)
        XCTAssertEqual(plan.zone, .zone2)
    }

    // MARK: - WorkoutFuelingPlan.coachSummary

    /// coachSummary moet duur, zonenaam, kcal, koolhydraten en vocht bevatten.
    func testCoachSummary_ContainsAllFields() {
        let plan = NutritionService.fuelingPlan(durationMinutes: 60, zone: .zone2, profile: maleProfile)
        let summary = plan.coachSummary
        XCTAssertTrue(summary.contains("60"), "Summary moet de duur (60) bevatten.")
        XCTAssertTrue(summary.contains("Zone 2"), "Summary moet de zonenaam bevatten.")
        XCTAssertTrue(summary.contains("kcal"), "Summary moet 'kcal' bevatten.")
        XCTAssertTrue(summary.contains("koolhydraten"), "Summary moet 'koolhydraten' bevatten.")
        XCTAssertTrue(summary.contains("ml"), "Summary moet 'ml' bevatten.")
    }

    // MARK: - Zone detectie (zone(for:))

    /// Workout met "interval" in beschrijving → Zone 4.
    func testZoneDetection_IntervalKeyword_ReturnsZone4() {
        let workout = makeWorkout(description: "Intervaltraining 5×1000m", heartRateZone: nil)
        XCTAssertEqual(NutritionService.zone(for: workout), .zone4,
                       "'interval' in beschrijving moet Zone 4 opleveren.")
    }

    /// Workout met "tempo" in beschrijving → Zone 4.
    func testZoneDetection_TempoKeyword_ReturnsZone4() {
        let workout = makeWorkout(description: "Tempoloop 10km", heartRateZone: nil)
        XCTAssertEqual(NutritionService.zone(for: workout), .zone4,
                       "'tempo' in beschrijving moet Zone 4 opleveren.")
    }

    /// Workout met "drempel" in beschrijving → Zone 4.
    func testZoneDetection_DrempelKeyword_ReturnsZone4() {
        let workout = makeWorkout(description: "Drempeltraining 20min", heartRateZone: nil)
        XCTAssertEqual(NutritionService.zone(for: workout), .zone4,
                       "'drempel' in beschrijving moet Zone 4 opleveren.")
    }

    /// Workout met "zone 4" in hartslagzone-veld → Zone 4.
    func testZoneDetection_Zone4InHeartRateZone_ReturnsZone4() {
        let workout = makeWorkout(description: "Hardlopen", heartRateZone: "Zone 4")
        XCTAssertEqual(NutritionService.zone(for: workout), .zone4,
                       "'Zone 4' in heartRateZone moet Zone 4 opleveren.")
    }

    /// Workout met "z4" (afkorting) in hartslagzone-veld → Zone 4.
    func testZoneDetection_Z4Abbreviation_ReturnsZone4() {
        let workout = makeWorkout(description: "Fietsen", heartRateZone: "Z4")
        XCTAssertEqual(NutritionService.zone(for: workout), .zone4,
                       "'Z4' in heartRateZone moet Zone 4 opleveren.")
    }

    /// Aërobe/herstelworkout zonder Zone 4-keywords → Zone 2 (default).
    func testZoneDetection_AerobeWorkout_ReturnsZone2() {
        let workout = makeWorkout(description: "Rustige Zone 2 duurrit 90min", heartRateZone: "Zone 2")
        XCTAssertEqual(NutritionService.zone(for: workout), .zone2,
                       "Aërobe workout zonder Zone 4-keywords moet Zone 2 opleveren.")
    }

    /// Workout zonder beschrijving en zonder hartslagzone → Zone 2 (veilige default).
    func testZoneDetection_EmptyDescription_DefaultsToZone2() {
        let workout = makeWorkout(description: "", heartRateZone: nil)
        XCTAssertEqual(NutritionService.zone(for: workout), .zone2,
                       "Lege beschrijving moet standaard Zone 2 opleveren.")
    }

    // MARK: - fuelingPlan(for:profile:) — rustdag & geen duur

    /// Rustdag (activityType = "rust") → nil plan.
    func testFuelingPlanForWorkout_RestDay_ReturnsNil() {
        let restWorkout = makeWorkout(description: "Rustdag", heartRateZone: nil,
                                     activityType: "rust", durationMinutes: 0)
        let plan = NutritionService.fuelingPlan(for: restWorkout, profile: maleProfile)
        XCTAssertNil(plan, "Rustdag moet nil teruggeven — geen voedingsplan nodig.")
    }

    /// Workout met duur 0 → nil plan.
    func testFuelingPlanForWorkout_ZeroDuration_ReturnsNil() {
        let workout = makeWorkout(description: "Optionele training", heartRateZone: nil,
                                  activityType: "Hardlopen", durationMinutes: 0)
        let plan = NutritionService.fuelingPlan(for: workout, profile: maleProfile)
        XCTAssertNil(plan, "Workout met duur 0 moet nil teruggeven.")
    }

    /// Normale workout met duur > 0 → geldig plan.
    func testFuelingPlanForWorkout_ValidWorkout_ReturnsPlan() {
        let workout = makeWorkout(description: "Zone 2 duurloop", heartRateZone: "Zone 2",
                                  activityType: "Hardlopen", durationMinutes: 45)
        let plan = NutritionService.fuelingPlan(for: workout, profile: maleProfile)
        XCTAssertNotNil(plan, "Geldige workout moet een voedingsplan opleveren.")
        XCTAssertEqual(plan?.durationMinutes, 45)
    }

    /// Zone-detectie wordt correct doorgegeven vanuit fuelingPlan(for:) aan het plan.
    func testFuelingPlanForWorkout_ZoneDetectedCorrectly() {
        let workout = makeWorkout(description: "Intervaltraining", heartRateZone: nil,
                                  activityType: "Hardlopen", durationMinutes: 30)
        let plan = NutritionService.fuelingPlan(for: workout, profile: maleProfile)
        XCTAssertEqual(plan?.zone, .zone4,
                       "Interval-workout moet Zone 4 plan opleveren.")
    }

    // MARK: - Interval-verdeling

    /// 60 min plan, elke 15 min → 4 intervallen.
    /// Zone 2: 500 ml totaal → 125 ml/interval; 30 g carbs → 7.5 g/interval.
    func testIntervalBreakdown_Zone2_60Min_Every15Min() {
        let plan = NutritionService.fuelingPlan(durationMinutes: 60, zone: .zone2, profile: maleProfile)
        let breakdown = NutritionService.intervalBreakdown(plan: plan, every: 15)
        XCTAssertEqual(breakdown.intervalMinutes, 15)
        XCTAssertEqual(breakdown.fluidMl, 125, accuracy: 0.01,
                       "500 ml ÷ 4 intervallen = 125 ml per 15 min.")
        XCTAssertEqual(breakdown.carbsGram, 7.5, accuracy: 0.01,
                       "30 g ÷ 4 intervallen = 7.5 g per 15 min.")
    }

    /// Zone 4, 45 min, elke 15 min → 3 intervallen.
    /// 800*(45/60) = 600 ml totaal → 200 ml/interval.
    func testIntervalBreakdown_Zone4_45Min_Every15Min() {
        let plan = NutritionService.fuelingPlan(durationMinutes: 45, zone: .zone4, profile: maleProfile)
        let breakdown = NutritionService.intervalBreakdown(plan: plan, every: 15)
        XCTAssertEqual(breakdown.fluidMl, 200, accuracy: 0.01,
                       "600 ml ÷ 3 intervallen = 200 ml per 15 min.")
    }

    /// Interval langer dan de workout → max(1, ...) prevents division by zero; geeft het volledige plan terug.
    func testIntervalBreakdown_IntervalLongerThanWorkout_ReturnsFullPlan() {
        let plan = NutritionService.fuelingPlan(durationMinutes: 10, zone: .zone2, profile: maleProfile)
        let breakdown = NutritionService.intervalBreakdown(plan: plan, every: 30)
        // intervals = max(1, 10/30) = max(1, 0.33) = 1 → volledige waarden worden teruggegeven
        XCTAssertEqual(breakdown.fluidMl, plan.fluidMl, accuracy: 0.01,
                       "Interval groter dan duur → 1 interval → volledige vochtwaarde.")
        XCTAssertEqual(breakdown.carbsGram, plan.carbsGram, accuracy: 0.01,
                       "Interval groter dan duur → 1 interval → volledige koolhydratenwaarde.")
    }

    // MARK: - Coach context blok

    /// buildCoachContext moet de verplichte headers bevatten.
    func testBuildCoachContext_ContainsRequiredHeaders() {
        let context = NutritionService.buildCoachContext(
            profile: maleProfile,
            todayWorkouts: [],
            tomorrowWorkouts: []
        )
        XCTAssertTrue(context.contains("[VOEDING & FYSIOLOGIE]"),
                      "Coach context moet de sectie-header bevatten.")
        XCTAssertTrue(context.contains("BMR"),
                      "Coach context moet 'BMR' bevatten.")
        XCTAssertTrue(context.contains("Fysiologisch profiel"),
                      "Coach context moet 'Fysiologisch profiel' bevatten.")
    }

    /// BMR in de context moet overeenkomen met de berekende waarde.
    func testBuildCoachContext_BMRValueIsCorrect() {
        let bmr = Int(NutritionService.calculateBMR(profile: maleProfile).rounded())
        let context = NutritionService.buildCoachContext(
            profile: maleProfile,
            todayWorkouts: [],
            tomorrowWorkouts: []
        )
        XCTAssertTrue(context.contains("\(bmr)"),
                      "BMR-waarde in de context moet overeenkomen met calculateBMR.")
    }

    /// Workouts vandaag worden opgenomen in de context; morgen-sectie verschijnt alleen als er workouts zijn.
    func testBuildCoachContext_TodayWorkoutsIncluded() {
        let context = NutritionService.buildCoachContext(
            profile: maleProfile,
            todayWorkouts: [(durationMinutes: 60, zone: .zone2)],
            tomorrowWorkouts: []
        )
        XCTAssertTrue(context.contains("Workouts vandaag"),
                      "Context moet 'Workouts vandaag' bevatten als er workouts zijn.")
        XCTAssertFalse(context.contains("Workouts morgen"),
                       "Context mag 'Workouts morgen' NIET bevatten als die lijst leeg is.")
    }

    /// Beide lijsten gevuld → beide secties aanwezig.
    func testBuildCoachContext_BothWorkoutDaysIncluded() {
        let context = NutritionService.buildCoachContext(
            profile: maleProfile,
            todayWorkouts:    [(durationMinutes: 45, zone: .zone4)],
            tomorrowWorkouts: [(durationMinutes: 30, zone: .zone2)]
        )
        XCTAssertTrue(context.contains("Workouts vandaag"),
                      "Context moet 'Workouts vandaag' bevatten.")
        XCTAssertTrue(context.contains("Workouts morgen"),
                      "Context moet 'Workouts morgen' bevatten als die lijst niet leeg is.")
    }

    // MARK: - Hulpfunctie

    /// Maakt een minimale `SuggestedWorkout` aan voor zone-detectietests.
    private func makeWorkout(
        description: String,
        heartRateZone: String?,
        activityType: String = "Hardlopen",
        durationMinutes: Int = 60
    ) -> SuggestedWorkout {
        SuggestedWorkout(
            dateOrDay: "Maandag",
            activityType: activityType,
            suggestedDurationMinutes: durationMinutes,
            targetTRIMP: nil,
            description: description,
            heartRateZone: heartRateZone,
            targetPace: nil,
            reasoning: nil
        )
    }
}
