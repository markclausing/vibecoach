import XCTest
@testable import AIFitnessCoach

/// Unit tests voor FutureProjectionService (Epic 23, Sprint 23.2).
///
/// Dekt drie kernonderdelen:
///   1. ProjectionStatus transities (alreadyPeaking → onTrack → atRisk → catchUpNeeded → unreachable)
///   2. BottleneckMetric ranking (.trimp / .km / .both / .alreadyMet)
///   3. Cross-Training Bonus activatie en effect op km-groeicap
///
/// Blueprint referentiewaarden (Peak Phase multiplier = 1.30):
///   Marathon:     weeklyTrimpTarget=500 → requiredPeakTRIMP=650 | weeklyKmTarget=55  → requiredPeakKm=71.5
///   HalfMarathon: weeklyTrimpTarget=350 → requiredPeakTRIMP=455 | weeklyKmTarget=40  → requiredPeakKm=52.0
///   CyclingTour:  weeklyTrimpTarget=400 → requiredPeakTRIMP=520 | weeklyKmTarget=180 → requiredPeakKm=234.0
final class FutureProjectionServiceTests: XCTestCase {

    // MARK: - Setup

    private let calendar = Calendar.current

    // MARK: - Helpers

    /// FitnessGoal met een marathon-titel en targetDate `weeksAhead` weken in de toekomst.
    private func marathonGoal(weeksAhead: Int) -> FitnessGoal {
        FitnessGoal(
            title: "Amsterdam Marathon",
            targetDate: calendar.date(byAdding: .weekOfYear, value: weeksAhead, to: Date())!
        )
    }

    /// FitnessGoal met een halve-marathon-titel.
    private func halfMarathonGoal(weeksAhead: Int) -> FitnessGoal {
        FitnessGoal(
            title: "Halve Marathon Rotterdam",
            targetDate: calendar.date(byAdding: .weekOfYear, value: weeksAhead, to: Date())!
        )
    }

    /// FitnessGoal met een fietsdoel-titel.
    private func cyclingGoal(weeksAhead: Int) -> FitnessGoal {
        FitnessGoal(
            title: "Fietstocht Arnhem-Karlsruhe",
            targetDate: calendar.date(byAdding: .weekOfYear, value: weeksAhead, to: Date())!
        )
    }

    /// Eén ActivityRecord met startDate `daysAgo` dagen geleden.
    private func activity(
        sport: SportCategory,
        trimp: Double,
        distanceKm: Double,
        daysAgo: Int,
        id: String = UUID().uuidString
    ) -> ActivityRecord {
        ActivityRecord(
            id: id,
            name: sport.workoutName,
            distance: distanceKm * 1000,
            movingTime: 3600,
            averageHeartrate: 145,
            sportCategory: sport,
            startDate: calendar.date(byAdding: .day, value: -daysAgo, to: Date())!,
            trimp: trimp
        )
    }

    /// Bouwt vier activiteiten — één per sliding-window week.
    /// week 0 = 3 dagen geleden, week 1 = 10 d, week 2 = 17 d, week 3 = 24 d.
    private func fourWeekActivities(
        sport: SportCategory,
        week0Trimp: Double, week0Km: Double,
        week1Trimp: Double, week1Km: Double,
        week2Trimp: Double, week2Km: Double,
        week3Trimp: Double, week3Km: Double
    ) -> [ActivityRecord] {
        [
            activity(sport: sport, trimp: week0Trimp, distanceKm: week0Km, daysAgo: 3,  id: "w0"),
            activity(sport: sport, trimp: week1Trimp, distanceKm: week1Km, daysAgo: 10, id: "w1"),
            activity(sport: sport, trimp: week2Trimp, distanceKm: week2Km, daysAgo: 17, id: "w2"),
            activity(sport: sport, trimp: week3Trimp, distanceKm: week3Km, daysAgo: 24, id: "w3"),
        ]
    }

    // MARK: - 1. ProjectionStatus Transities

    func testStatus_BothMetricsAbovePeak_ReturnsAlreadyPeaking() {
        // Marathon: requiredPeakTRIMP=650, requiredPeakKm=71.5
        // Huidige load zit al boven beide piek-eisen → meteen alreadyPeaking.
        let goal = marathonGoal(weeksAhead: 26)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 700, week0Km: 80,
            week1Trimp: 700, week1Km: 80,
            week2Trimp: 600, week2Km: 70,
            week3Trimp: 600, week3Km: 70
        )

        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, .alreadyPeaking)
        XCTAssertEqual(result?.bottleneck, .alreadyMet)
        XCTAssertNil(result?.projectedPeakDate, "Bij alreadyPeaking mag geen projectiedatum worden getoond.")
    }

    func testStatus_StrongGrowthFarFromRace_ReturnsOnTrack() {
        // Marathon, race 26 weken (plannedPeakDate = 22 weken).
        // currentTRIMP = 350, groei ≈ 10% → piek bereikt in ~6–7 weken << 22 weken → onTrack.
        // Km al voldaan (80 ≥ 71.5) → TRIMP is de bottleneck maar alles is op schema.
        let goal = marathonGoal(weeksAhead: 26)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 350, week0Km: 80,
            week1Trimp: 350, week1Km: 80,
            week2Trimp: 290, week2Km: 70,
            week3Trimp: 290, week3Km: 70
        )

        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, .onTrack)
    }

    func testStatus_SlowGrowthRaceCloseIn8Weeks_ReturnsAtRisk() {
        // Marathon, race 8 weken (plannedPeakDate = 4 weken).
        // Km al voldaan. currentTRIMP = 400, groei ≈ 8.8% → piek na ~5–6 weken.
        // 5–6 weken > plannedPeakDate(4), maar < targetDate(8) → atRisk.
        let goal = marathonGoal(weeksAhead: 8)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 400, week0Km: 80,
            week1Trimp: 400, week1Km: 80,
            week2Trimp: 340, week2Km: 70,
            week3Trimp: 340, week3Km: 70
        )

        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, .atRisk)
    }

    func testStatus_NoActivitiesRaceWithin6Weeks_ReturnsUnreachable() {
        // Geen activiteiten → currentTRIMP = 0 en currentKm = 0 → beide unreachable.
        // Race 6 weken weg (< gracePeriodWeeks=12) → unreachable (niet catchUpNeeded).
        let goal = marathonGoal(weeksAhead: 6)

        let result = FutureProjectionService.calculateProjection(for: goal, activities: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, .unreachable)
    }

    func testStatus_NoActivitiesRaceMoreThan12WeeksAway_ReturnsCatchUpNeeded() {
        // Race 20 weken weg (> gracePeriodWeeks=12) → ondanks nul-groei is er tijd om bij te sturen.
        // Verwacht: catchUpNeeded (oranje), niet unreachable (rood).
        let goal = marathonGoal(weeksAhead: 20)

        let result = FutureProjectionService.calculateProjection(for: goal, activities: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, .catchUpNeeded)
    }

    func testStatus_FlatLoad_NoGrowth_RaceCloseIn6Weeks_ReturnsUnreachable() {
        // Constante belasting (geen groei) → effectiveRate = 0 → projectDate geeft nil → unreachable.
        // Race 6 weken weg → status unreachable (niet catchUpNeeded).
        let goal = marathonGoal(weeksAhead: 6)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 200, week0Km: 30,
            week1Trimp: 200, week1Km: 30,
            week2Trimp: 200, week2Km: 30,
            week3Trimp: 200, week3Km: 30
        )

        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, .unreachable)
    }

    // MARK: - 2. BottleneckMetric Ranking

    func testBottleneck_TRIMPAlreadyMet_KmBehind_ReturnsKm() {
        // TRIMP = 700 ≥ requiredPeakTRIMP(650) → trimpAlreadyMet = true.
        // Km = 50 < requiredPeakKm(71.5) → km is de bottleneck.
        let goal = marathonGoal(weeksAhead: 26)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 700, week0Km: 50,
            week1Trimp: 700, week1Km: 50,
            week2Trimp: 600, week2Km: 40,
            week3Trimp: 600, week3Km: 40
        )

        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.bottleneck, .km)
    }

    func testBottleneck_KmAlreadyMet_TRIMPBehind_ReturnsTRIMP() {
        // Km = 80 ≥ requiredPeakKm(71.5) → kmAlreadyMet = true.
        // TRIMP = 350 < requiredPeakTRIMP(650) → TRIMP is de bottleneck.
        let goal = marathonGoal(weeksAhead: 26)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 350, week0Km: 80,
            week1Trimp: 350, week1Km: 80,
            week2Trimp: 290, week2Km: 70,
            week3Trimp: 290, week3Km: 70
        )

        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.bottleneck, .trimp)
    }

    func testBottleneck_BothUnreachableNoActivities_ReturnsBoth() {
        // Geen activiteiten → beide metrics unreachable → bottleneck = .both.
        let goal = marathonGoal(weeksAhead: 20)

        let result = FutureProjectionService.calculateProjection(for: goal, activities: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.bottleneck, .both)
    }

    func testBottleneck_BothAlreadyMet_ReturnsAlreadyMet() {
        // Zowel TRIMP als km boven piek-eis → bottleneck = .alreadyMet.
        let goal = marathonGoal(weeksAhead: 26)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 700, week0Km: 80,
            week1Trimp: 700, week1Km: 80,
            week2Trimp: 650, week2Km: 75,
            week3Trimp: 650, week3Km: 75
        )

        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)

        XCTAssertEqual(result?.bottleneck, .alreadyMet)
    }

    // MARK: - 3. Sport-isolatie (km telt alleen voor doelsport)

    func testKmIsolation_MarathonGoal_IgnoresCyclingKm() {
        // Marathon doel: alleen hardloop-km tellen mee.
        // Fietsactiviteiten (200 km/week) worden volledig genegeerd voor de km-projectie.
        // Hardloopkm = 30 < 71.5 → km niet voldaan ondanks de hoge fiets-km.
        let goal = marathonGoal(weeksAhead: 26)
        let runActivities = [
            activity(sport: .running, trimp: 700, distanceKm: 30, daysAgo: 3,  id: "r0"),
            activity(sport: .running, trimp: 700, distanceKm: 30, daysAgo: 10, id: "r1"),
        ]
        let cycleActivities = [
            activity(sport: .cycling, trimp: 500, distanceKm: 200, daysAgo: 3,  id: "c0"),
            activity(sport: .cycling, trimp: 500, distanceKm: 200, daysAgo: 10, id: "c1"),
        ]

        let result = FutureProjectionService.calculateProjection(for: goal, activities: runActivities + cycleActivities)

        XCTAssertNotNil(result)
        // Km-target is 71.5; TRIMP al voldaan (700) maar km niet (30 < 71.5) → bottleneck km.
        XCTAssertEqual(result?.bottleneck, .km,
                       "Fiets-km mogen NIET worden meegeteld voor een marathondoel.")
        XCTAssertEqual(result?.currentWeeklyKm ?? 0, 30.0, accuracy: 1.0,
                       "currentWeeklyKm moet uitsluitend hardloop-km bevatten.")
    }

    func testKmIsolation_CyclingGoal_IgnoresRunningKm() {
        // Fietsdoel: alleen fiets-km tellen mee (requiredPeakKm = 234).
        // Hardloopactiviteiten met 80 km/week worden genegeerd.
        let goal = cyclingGoal(weeksAhead: 26)
        let runActivities = [
            activity(sport: .running, trimp: 300, distanceKm: 80, daysAgo: 3,  id: "r0"),
            activity(sport: .running, trimp: 300, distanceKm: 80, daysAgo: 10, id: "r1"),
        ]
        let cycleActivities = [
            activity(sport: .cycling, trimp: 400, distanceKm: 60, daysAgo: 3,  id: "c0"),
            activity(sport: .cycling, trimp: 400, distanceKm: 60, daysAgo: 10, id: "c1"),
        ]

        let result = FutureProjectionService.calculateProjection(for: goal, activities: runActivities + cycleActivities)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.currentWeeklyKm ?? 0, 60.0, accuracy: 1.0,
                       "currentWeeklyKm moet uitsluitend fiets-km bevatten voor een fietsdoel.")
    }

    // MARK: - 4. Cross-Training Bonus

    func testCrossTrainingBonus_TRIMPAboveThreshold_BonusActivated() {
        // Drempelwaarde = 0.90 × weeklyTrimpTarget(500) = 450.
        // currentTRIMP = 460 ≥ 450 → hasCrossTrainingBonus = true.
        let goal = marathonGoal(weeksAhead: 26)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 460, week0Km: 30,
            week1Trimp: 460, week1Km: 30,
            week2Trimp: 400, week2Km: 20,
            week3Trimp: 400, week3Km: 20
        )

        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.hasCrossTrainingBonus == true,
                      "TRIMP ≥ 90% van weekdoel moet de Cross-Training Bonus activeren.")
    }

    func testCrossTrainingBonus_TRIMPBelowThreshold_BonusNotActivated() {
        // currentTRIMP = 350 < 450 (90% van 500) → hasCrossTrainingBonus = false.
        let goal = marathonGoal(weeksAhead: 26)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 350, week0Km: 30,
            week1Trimp: 350, week1Km: 30,
            week2Trimp: 290, week2Km: 20,
            week3Trimp: 290, week3Km: 20
        )

        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)

        XCTAssertNotNil(result)
        XCTAssertFalse(result?.hasCrossTrainingBonus == true,
                       "TRIMP < 90% van weekdoel mag de Cross-Training Bonus NIET activeren.")
    }

    func testCrossTrainingBonus_HigherKmGrowthCapApplied() {
        // Met de bonus is de km-groeicap 17% i.p.v. 10%.
        // Controleer: effectiveKmGrowthRate ≤ 0.17 (bonus cap) en > 0.10 als observedGrowth > 10%.
        // Setup: TRIMP = 460 (bonus actief), km groeit van 20 → 30 per 2 weken.
        // observedKmGrowth = (30 - 20) / 20 / 2 = 25% → cap zonder bonus = 10%, met bonus = 17%.
        let goal = marathonGoal(weeksAhead: 26)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 460, week0Km: 30,
            week1Trimp: 460, week1Km: 30,
            week2Trimp: 400, week2Km: 20,
            week3Trimp: 400, week3Km: 20
        )

        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)

        XCTAssertNotNil(result)
        // effectiveKmGrowthRate moet 0.17 zijn (cap van cross-training bonus, observed = 25%)
        XCTAssertEqual(result?.effectiveKmGrowthRate ?? 0,
                       FutureProjectionService.maxWeeklyGrowthRateCrossTraining,
                       accuracy: 0.001,
                       "Met cross-training bonus moet de km-groeicap 17% zijn.")
    }

    func testCrossTrainingBonus_NoBonusStandardCapApplied() {
        // TRIMP < 450 → geen bonus → km-groeicap is standaard 10%.
        // observedKmGrowth = (30 - 20) / 20 / 2 = 25% → gecapt op 10%.
        let goal = marathonGoal(weeksAhead: 26)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 350, week0Km: 30,
            week1Trimp: 350, week1Km: 30,
            week2Trimp: 290, week2Km: 20,
            week3Trimp: 290, week3Km: 20
        )

        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.effectiveKmGrowthRate ?? 0,
                       FutureProjectionService.maxWeeklyGrowthRate,
                       accuracy: 0.001,
                       "Zonder bonus moet de km-groeicap standaard 10% zijn.")
    }

    // MARK: - 5. Km-Veiligheidscap

    func testSafetyCap_KmFarBelowRequired_ProjectionClampedToPlannedPeakDate() {
        // kmRatio = 30/71.5 ≈ 0.42 < kmSafetyThreshold(0.95).
        // Veiligheidscap: rawProjectedDate mag nooit eerder vallen dan plannedPeakDate.
        // TRIMP al voldaan → bottleneck = km. Zonder cap ≈ nu + 3 weken; met cap = now + 22 weken.
        let goal = marathonGoal(weeksAhead: 26)
        let activities = [
            activity(sport: .running, trimp: 700, distanceKm: 30, daysAgo: 3,  id: "w0"),
            activity(sport: .running, trimp: 700, distanceKm: 30, daysAgo: 10, id: "w1"),
            activity(sport: .running, trimp: 600, distanceKm: 20, daysAgo: 17, id: "w2"),
            activity(sport: .running, trimp: 600, distanceKm: 20, daysAgo: 24, id: "w3"),
        ]

        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)

        XCTAssertNotNil(result)
        // Door de veiligheidscap mag weeksDelta niet negatief zijn (projectie niet vóór plannedPeakDate)
        XCTAssertGreaterThanOrEqual(result?.weeksDelta ?? -99, -0.5,
            "Veiligheidscap: wanneer km < 95% van de piek-eis, mag projectie niet vóór de geplande peakdatum vallen.")
    }

    // MARK: - 6. Blueprint-filtering via calculateProjections

    func testCalculateProjections_CompletedGoal_IsExcluded() {
        let activeGoal = marathonGoal(weeksAhead: 26)
        let completedGoal = marathonGoal(weeksAhead: 20)
        completedGoal.isCompleted = true

        let results = FutureProjectionService.calculateProjections(for: [activeGoal, completedGoal], activities: [])

        XCTAssertEqual(results.count, 1, "Afgeronde doelen mogen niet in de projecties verschijnen.")
    }

    func testCalculateProjections_PastTargetDate_IsExcluded() {
        let activeGoal = marathonGoal(weeksAhead: 26)
        let pastGoal = FitnessGoal(
            title: "Amsterdam Marathon",
            targetDate: Date().addingTimeInterval(-86400) // gisteren
        )

        let results = FutureProjectionService.calculateProjections(for: [activeGoal, pastGoal], activities: [])

        XCTAssertEqual(results.count, 1, "Doelen met targetDate in het verleden mogen niet worden geprojecteerd.")
    }

    func testCalculateProjections_UnknownGoalTitle_ReturnsNil() {
        // Titel bevat geen herkend sleutelwoord en heeft geen SportCategory fallback → nil.
        let unknownGoal = FitnessGoal(
            title: "Gezonder leven algemeen",
            targetDate: calendar.date(byAdding: .weekOfYear, value: 20, to: Date())!,
            sportCategory: .strength
        )

        let result = FutureProjectionService.calculateProjection(for: unknownGoal, activities: [])

        XCTAssertNil(result, "Doelen zonder herkend blueprint-type moeten nil retourneren.")
    }

    // MARK: - 7. HalfMarathon Blueprint

    func testHalfMarathon_AlreadyPeaking_CorrectRequiredValues() {
        // HalfMarathon: requiredPeakTRIMP=455, requiredPeakKm=52.
        // currentTRIMP=500 en km=60 → alreadyPeaking met correcte blueprint-waarden.
        let goal = halfMarathonGoal(weeksAhead: 16)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 500, week0Km: 60,
            week1Trimp: 500, week1Km: 60,
            week2Trimp: 460, week2Km: 55,
            week3Trimp: 460, week3Km: 55
        )

        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, .alreadyPeaking)
        XCTAssertEqual(result?.requiredPeakTRIMP ?? 0, 455.0, accuracy: 1.0)
        XCTAssertEqual(result?.requiredPeakKm ?? 0,    52.0,  accuracy: 1.0)
    }

    // MARK: - 8. Effectieve groeisnelheid (cap-gedrag)

    func testEffectiveGrowthRate_ObservedAbove10Percent_CappedAt10() {
        // observedGrowth = (350 - 290) / 290 / 2 ≈ 10.3% → gecapt op 10%.
        let goal = marathonGoal(weeksAhead: 26)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 350, week0Km: 80,
            week1Trimp: 350, week1Km: 80,
            week2Trimp: 290, week2Km: 70,
            week3Trimp: 290, week3Km: 70
        )

        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.effectiveGrowthRate ?? 0,
                       FutureProjectionService.maxWeeklyGrowthRate,
                       accuracy: 0.001,
                       "Geobserveerde TRIMP-groei > 10% moet worden gecapt op 10%.")
    }

    func testEffectiveGrowthRate_ObservedBelow10Percent_NotCapped() {
        // observedGrowth = (350 - 330) / 330 / 2 ≈ 3% → NIET gecapt.
        let goal = marathonGoal(weeksAhead: 26)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 350, week0Km: 80,
            week1Trimp: 350, week1Km: 80,
            week2Trimp: 330, week2Km: 70,
            week3Trimp: 330, week3Km: 70
        )

        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)

        XCTAssertNotNil(result)
        let expectedGrowth = (350 - 330) / 330.0 / 2.0
        XCTAssertEqual(result?.effectiveGrowthRate ?? 0,
                       expectedGrowth,
                       accuracy: 0.001,
                       "Geobserveerde TRIMP-groei < 10% mag NIET worden gecapt.")
    }

    // MARK: - 9. coachContext (Epic #36 sub-task 36.2 coverage uplift)

    /// Verifieer dat coachContext voor `alreadyPeaking` de checkmark-formulering bevat.
    func testCoachContext_AlreadyPeaking_IncludesCheckmarkAndTaper() {
        let goal = marathonGoal(weeksAhead: 26)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 700, week0Km: 80, week1Trimp: 700, week1Km: 80,
            week2Trimp: 650, week2Km: 75, week3Trimp: 650, week3Km: 75
        )
        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)
        let context = result?.coachContext ?? ""

        XCTAssertTrue(context.contains("✅ PROGNOSE"), "alreadyPeaking moet ✅-prefix bevatten.")
        XCTAssertTrue(context.contains("Vasthouden") || context.contains("taperen"),
                      "alreadyPeaking moet 'Vasthouden en taperen' communiceren.")
    }

    /// onTrack-branch: verifieer 🟢 prefix en aanduiding van weken vóór plannedPeakDate.
    func testCoachContext_OnTrack_IncludesGreenIconAndSchedule() {
        let goal = marathonGoal(weeksAhead: 26)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 350, week0Km: 80, week1Trimp: 350, week1Km: 80,
            week2Trimp: 290, week2Km: 70, week3Trimp: 290, week3Km: 70
        )
        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)
        let context = result?.coachContext ?? ""

        XCTAssertTrue(context.contains("🟢 PROGNOSE"))
        XCTAssertTrue(context.contains("Op schema"))
    }

    /// atRisk-branch (km al voldaan, TRIMP loopt achter en race is dichtbij).
    func testCoachContext_AtRisk_IncludesOrangeIconAndUrgency() {
        let goal = marathonGoal(weeksAhead: 8)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 400, week0Km: 80, week1Trimp: 400, week1Km: 80,
            week2Trimp: 340, week2Km: 70, week3Trimp: 340, week3Km: 70
        )
        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)
        let context = result?.coachContext ?? ""

        XCTAssertTrue(context.contains("🟠 PROGNOSE"))
        XCTAssertTrue(context.contains("MOET het volume verhogen"),
                      "atRisk moet de coach instrueren om het volume te verhogen.")
    }

    /// catchUpNeeded-branch (geen activiteiten, race > 12 weken weg).
    func testCoachContext_CatchUpNeeded_IsConstructiveNotAlarming() {
        let goal = marathonGoal(weeksAhead: 20)
        let result = FutureProjectionService.calculateProjection(for: goal, activities: [])
        let context = result?.coachContext ?? ""

        XCTAssertTrue(context.contains("🟠"))
        XCTAssertTrue(context.contains("constructief") || context.contains("Inhaalslag"),
                      "catchUpNeeded mag NIET alarmerend zijn.")
        XCTAssertTrue(context.contains("opbouwplan"))
    }

    /// unreachable-branch (race binnen 6 weken, geen activiteiten).
    func testCoachContext_Unreachable_RecommendsDoeldatumOrTrainingsrace() {
        let goal = marathonGoal(weeksAhead: 6)
        let result = FutureProjectionService.calculateProjection(for: goal, activities: [])
        let context = result?.coachContext ?? ""

        XCTAssertTrue(context.contains("🔴 PROGNOSE"))
        XCTAssertTrue(context.contains("doeldatum uitstellen") || context.contains("trainingsrace"),
                      "unreachable moet alternatieven aanbieden i.p.v. een ramp uit te roepen.")
    }

    /// Bottleneck=.km zonder Cross-Training Bonus → het sport-specifieke advies moet erin staan.
    /// Setup: TRIMP groeit, km groeit langzamer; currentTRIMP < 90% van weekdoel (geen bonus).
    /// Een marathon weekdoel = 500 → bonus-drempel 450. We mikken op currentTRIMP ≈ 280.
    func testCoachContext_BottleneckKm_WithoutBonus_FlagsSportSpecificGap() {
        let goal = marathonGoal(weeksAhead: 26)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 280, week0Km: 30,
            week1Trimp: 280, week1Km: 30,
            week2Trimp: 200, week2Km: 24,
            week3Trimp: 200, week3Km: 24
        )

        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)
        let context = result?.coachContext ?? ""

        XCTAssertEqual(result?.bottleneck, .km, "Met TRIMP-groei sneller dan km-groei is km de bottleneck.")
        XCTAssertFalse(result?.hasCrossTrainingBonus ?? true,
                       "currentTRIMP=280 < bonus-drempel(450) — geen bonus.")
        XCTAssertTrue(context.contains("BOTTLENECK") && context.contains("hardloop-km"))
        XCTAssertTrue(context.contains("telt NIET mee"),
                      "Zonder bonus moet de cross-sport-waarschuwing erin staan.")
    }

    /// Bottleneck=.km MET Cross-Training Bonus → empathische 17%-cap-formulering.
    func testCoachContext_BottleneckKm_WithBonus_ShowsCrossTrainingMessage() {
        let goal = marathonGoal(weeksAhead: 26)
        let activities = fourWeekActivities(
            sport: .running,
            week0Trimp: 460, week0Km: 30, week1Trimp: 460, week1Km: 30,
            week2Trimp: 400, week2Km: 20, week3Trimp: 400, week3Km: 20
        )
        let result = FutureProjectionService.calculateProjection(for: goal, activities: activities)
        let context = result?.coachContext ?? ""

        XCTAssertEqual(result?.bottleneck, .km)
        XCTAssertTrue(result?.hasCrossTrainingBonus ?? false)
        XCTAssertTrue(context.contains("Cross-Training Bonus"))
        XCTAssertTrue(context.contains("17"), "Bonus-cap percentage (17%) moet zichtbaar zijn.")
    }

    /// Bottleneck=.both → "BEIDE metrics"-formulering.
    func testCoachContext_BottleneckBoth_FlagsBothBehind() {
        let goal = marathonGoal(weeksAhead: 20)
        let result = FutureProjectionService.calculateProjection(for: goal, activities: [])
        let context = result?.coachContext ?? ""

        XCTAssertEqual(result?.bottleneck, .both)
        XCTAssertTrue(context.contains("BEIDE metrics"))
    }

    /// Cycling-doel: kmLabel moet "fiets-km" zijn (i.p.v. hardloop-km).
    func testCoachContext_CyclingGoal_UsesFietsKmLabel() {
        let goal = cyclingGoal(weeksAhead: 26)
        let result = FutureProjectionService.calculateProjection(for: goal, activities: [])
        let context = result?.coachContext ?? ""

        XCTAssertTrue(context.contains("fiets-km"))
        XCTAssertFalse(context.contains("hardloop-km"))
    }

    // MARK: - 10. buildCoachContext aggregator

    func testBuildCoachContext_EmptyProjections_ReturnsEmptyString() {
        let result = FutureProjectionService.buildCoachContext(from: [])
        XCTAssertEqual(result, "")
    }

    func testBuildCoachContext_SingleProjection_WrapsWithHeaderAndGedragsregel() {
        let goal = marathonGoal(weeksAhead: 26)
        let result = FutureProjectionService.calculateProjection(for: goal, activities: [])
        let combined = FutureProjectionService.buildCoachContext(from: [result!])

        XCTAssertTrue(combined.contains("[PROGNOSE — TOEKOMSTPROJECTIE"),
                      "Header moet aanwezig zijn.")
        XCTAssertTrue(combined.contains("Gedragsregel:"))
        XCTAssertTrue(combined.contains("bottleneck .km"),
                      "Gedragsregel-blok moet de coach-instructies bevatten.")
    }

    // MARK: - 11. ProjectionStatus visuele attributen

    func testProjectionStatus_IconsAndColors_AreUnique() {
        let allStatuses: [ProjectionStatus] = [
            .alreadyPeaking, .onTrack, .atRisk, .catchUpNeeded, .unreachable,
        ]
        let icons = allStatuses.map(\.icon)
        let labels = allStatuses.map(\.label)

        XCTAssertEqual(Set(icons).count, icons.count, "Elke status moet een unieke icon hebben.")
        XCTAssertEqual(Set(labels).count, labels.count, "Elke status moet een uniek label hebben.")

        // Color-mapping conform UI-conventie (groen = OK, oranje = waarschuwing, rood = kritiek)
        XCTAssertEqual(ProjectionStatus.alreadyPeaking.color, "green")
        XCTAssertEqual(ProjectionStatus.onTrack.color, "green")
        XCTAssertEqual(ProjectionStatus.atRisk.color, "orange")
        XCTAssertEqual(ProjectionStatus.catchUpNeeded.color, "orange")
        XCTAssertEqual(ProjectionStatus.unreachable.color, "red")
    }
}
