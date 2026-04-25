import XCTest
@testable import AIFitnessCoach

/// Epic #36 sub-task 36.4 — dekt de pure logica van `ProactiveNotificationService`.
/// De singleton zelf doet HKObserverQuery + BGTaskScheduler + UNUserNotificationCenter
/// werk dat alleen op een echt device geoorloofd is. Daarom zijn de notificatie-
/// content-compositie, cooldown-check en Banister TRIMP-berekening geëxtraheerd
/// als static helpers — die testen we hier exhaustief.
final class ProactiveNotificationServiceTests: XCTestCase {

    // MARK: - Engine A content

    /// Hoge TRIMP (≥50) + één doel op rood → prijzende toon met doelnaam.
    func testEngineA_HighTRIMP_SingleGoal_PraisesAndCitesGoal() {
        let result = ProactiveNotificationService.composeEngineAContent(
            recentTRIMP: 80,
            atRiskTitles: ["Marathon Amsterdam"]
        )
        XCTAssertEqual(result.title, "Lekker getraind! 💪")
        XCTAssertTrue(result.body.contains("80 TRIMP"))
        XCTAssertTrue(result.body.contains("Marathon Amsterdam"),
                      "Doelnaam moet expliciet in de body staan bij precies één doel.")
        XCTAssertTrue(result.body.contains("vervolgstap"),
                      "Bij hoge TRIMP wijst de body naar de vervolgstap, niet naar 'inhalen'.")
    }

    /// Hoge TRIMP + meerdere doelen op rood → telt aantal doelen, geen specifieke titel.
    func testEngineA_HighTRIMP_MultipleGoals_CountsGoals() {
        let result = ProactiveNotificationService.composeEngineAContent(
            recentTRIMP: 100,
            atRiskTitles: ["Marathon", "Halve Marathon", "Fietstocht"]
        )
        XCTAssertEqual(result.title, "Lekker getraind! 💪")
        XCTAssertTrue(result.body.contains("3 doelen"),
                      "Body moet het aantal doelen noemen i.p.v. een specifieke titel.")
        XCTAssertFalse(result.body.contains("Marathon Amsterdam"),
                       "Geen specifieke doelnaam wanneer er meerdere op rood staan.")
    }

    /// Lichte TRIMP (>0 maar <50) + één doel → neutrale toon met advies tot zwaardere sessie.
    func testEngineA_LowTRIMP_SingleGoal_NeutralWithUpsell() {
        let result = ProactiveNotificationService.composeEngineAContent(
            recentTRIMP: 25,
            atRiskTitles: ["Marathon Amsterdam"]
        )
        XCTAssertTrue(result.title.contains("25 TRIMP"),
                      "Titel toont de TRIMP-waarde voor lichte workouts.")
        XCTAssertTrue(result.body.contains("zwaardere sessie"),
                      "Body adviseert een zwaardere sessie bij lichte workout met enkel doel op rood.")
    }

    /// Lichte TRIMP + meerdere doelen → neutraal met aantal-doelen.
    func testEngineA_LowTRIMP_MultipleGoals_NeutralWithCount() {
        let result = ProactiveNotificationService.composeEngineAContent(
            recentTRIMP: 30,
            atRiskTitles: ["A", "B"]
        )
        XCTAssertTrue(result.body.contains("2 doelen"))
        XCTAssertFalse(result.body.contains("zwaardere sessie"),
                       "Bij meerdere doelen ligt de focus op planning, niet op upsell van zwaardere training.")
    }

    /// Geen TRIMP-data + één doel → fallback-tekst zonder TRIMP-waarde in titel.
    func testEngineA_NilTRIMP_SingleGoal_FallbackTitle() {
        let result = ProactiveNotificationService.composeEngineAContent(
            recentTRIMP: nil,
            atRiskTitles: ["Marathon Amsterdam"]
        )
        XCTAssertEqual(result.title, "Workout geregistreerd",
                       "Titel mag GEEN TRIMP-getal bevatten als er geen data is.")
        XCTAssertTrue(result.body.contains("Marathon Amsterdam"))
        XCTAssertTrue(result.body.contains("volgende stap"))
    }

    /// Geen TRIMP + meerdere doelen → fallback-tekst met aantal.
    func testEngineA_NilTRIMP_MultipleGoals_FallbackWithCount() {
        let result = ProactiveNotificationService.composeEngineAContent(
            recentTRIMP: nil,
            atRiskTitles: ["A", "B", "C"]
        )
        XCTAssertEqual(result.title, "Workout geregistreerd")
        XCTAssertTrue(result.body.contains("3 doelen"))
    }

    /// TRIMP exact op de grenswaarde 50 — moet in de "hoog"-tak vallen.
    func testEngineA_TRIMPAtFiftyBoundary_FallsInHighBranch() {
        let result = ProactiveNotificationService.composeEngineAContent(
            recentTRIMP: 50,
            atRiskTitles: ["Test"]
        )
        XCTAssertEqual(result.title, "Lekker getraind! 💪",
                       "TRIMP exact 50 moet in de hoog-tak vallen (>= 50).")
    }

    /// TRIMP=0 valt door de "hoog"-tak (>=50) en "midden"-tak (>0) heen — fallback.
    func testEngineA_ZeroTRIMP_TreatedAsNoData() {
        let result = ProactiveNotificationService.composeEngineAContent(
            recentTRIMP: 0,
            atRiskTitles: ["Test"]
        )
        XCTAssertEqual(result.title, "Workout geregistreerd",
                       "TRIMP=0 valt in de fallback-tak omdat trimp > 0 niet matcht.")
    }

    // MARK: - Engine B content

    private func date(daysAgo: Double, from now: Date = Date()) -> Date {
        now.addingTimeInterval(-daysAgo * 86400)
    }

    /// Geen doelen op rood → engine vuurt niet.
    func testEngineB_NoAtRiskGoals_ReturnsNil() {
        let result = ProactiveNotificationService.composeEngineBContent(
            atRiskTitles: [],
            lastWorkoutDate: nil
        )
        XCTAssertNil(result)
    }

    /// Recente activiteit (1 dag geleden) → onder de 2-dagen drempel → niet vuren.
    func testEngineB_RecentlyActive_ReturnsNil() {
        let now = Date()
        let result = ProactiveNotificationService.composeEngineBContent(
            atRiskTitles: ["Marathon"],
            lastWorkoutDate: date(daysAgo: 1, from: now),
            now: now
        )
        XCTAssertNil(result, "1 dag inactief zit onder de 2-dagen drempel.")
    }

    /// 2 dagen inactief → vriendelijke toon ("Je doel heeft je nodig").
    func testEngineB_TwoDaysInactive_FriendlyTone() {
        let now = Date()
        let result = ProactiveNotificationService.composeEngineBContent(
            atRiskTitles: ["Marathon Amsterdam"],
            lastWorkoutDate: date(daysAgo: 2, from: now),
            now: now
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.title, "Je doel heeft je nodig 👟")
        XCTAssertTrue(result?.body.contains("2 dagen") ?? false)
        XCTAssertTrue(result?.body.contains("Marathon Amsterdam") ?? false)
        XCTAssertTrue(result?.body.contains("korte sessie helpt") ?? false,
                      "2-3 dagen-tak moet vriendelijk zijn met 'korte sessie helpt'.")
    }

    /// 3 dagen inactief → nog steeds in de vriendelijke tak (drempel = 4 voor urgent).
    func testEngineB_ThreeDaysInactive_StillFriendlyTone() {
        let now = Date()
        let result = ProactiveNotificationService.composeEngineBContent(
            atRiskTitles: ["Marathon"],
            lastWorkoutDate: date(daysAgo: 3, from: now),
            now: now
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.title, "Je doel heeft je nodig 👟")
        XCTAssertTrue(result?.body.contains("3 dagen") ?? false)
    }

    /// 4+ dagen inactief → urgente toon ("Tijd voor actie!").
    func testEngineB_FourDaysInactive_UrgentTone() {
        let now = Date()
        let result = ProactiveNotificationService.composeEngineBContent(
            atRiskTitles: ["Marathon Amsterdam"],
            lastWorkoutDate: date(daysAgo: 5, from: now),
            now: now
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.title, "Tijd voor actie! ⚠️")
        XCTAssertTrue(result?.body.contains("5 dagen") ?? false)
        XCTAssertTrue(result?.body.contains("gevaarlijk achter") ?? false,
                      "4+ dagen-tak gebruikt strengere woordkeus.")
        XCTAssertTrue(result?.body.contains("herstelplan") ?? false)
    }

    /// Geen lastWorkoutDate (nieuwe gebruiker) → behandeld als 3 dagen inactief.
    func testEngineB_NoWorkoutHistory_AssumesThreeDaysInactive() {
        let result = ProactiveNotificationService.composeEngineBContent(
            atRiskTitles: ["Marathon"],
            lastWorkoutDate: nil
        )
        XCTAssertNotNil(result, "Geen historie hoort als 3 dagen behandeld te worden — engine vuurt.")
        XCTAssertEqual(result?.title, "Je doel heeft je nodig 👟",
                       "3 dagen valt onder de vriendelijke tak.")
    }

    /// Engine B noemt alleen het EERSTE doel, niet de hele lijst.
    func testEngineB_PrimaryGoalOnly_OmitsOthers() {
        let now = Date()
        let result = ProactiveNotificationService.composeEngineBContent(
            atRiskTitles: ["Marathon", "Halve Marathon", "Fietstocht"],
            lastWorkoutDate: date(daysAgo: 3, from: now),
            now: now
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.body.contains("Marathon") ?? false,
                      "Eerste doel moet vermeld worden.")
        XCTAssertFalse(result?.body.contains("Fietstocht") ?? true,
                       "Andere doelen mogen niet genoemd worden — focus op de primaire.")
    }

    // MARK: - Cooldown

    func testCooldown_NoPreviousNotification_NotActive() {
        XCTAssertFalse(
            ProactiveNotificationService.isCooldownActive(lastNotificationDate: nil),
            "Bij ontbrekende lastNotificationDate is er geen cooldown."
        )
    }

    func testCooldown_WithinWindow_Active() {
        let now = Date()
        let lastSent = now.addingTimeInterval(-3600) // 1 uur geleden
        XCTAssertTrue(
            ProactiveNotificationService.isCooldownActive(
                lastNotificationDate: lastSent,
                now: now
            ),
            "Een uur geleden valt binnen de 24-uurs cooldown."
        )
    }

    func testCooldown_PastWindow_NotActive() {
        let now = Date()
        let lastSent = now.addingTimeInterval(-90_000) // 25 uur geleden
        XCTAssertFalse(
            ProactiveNotificationService.isCooldownActive(
                lastNotificationDate: lastSent,
                now: now
            ),
            "25 uur geleden zit voorbij het 24-uurs venster."
        )
    }

    func testCooldown_ExactlyAtBoundary_NotActive() {
        let now = Date()
        let lastSent = now.addingTimeInterval(-86400) // Exact 24 uur geleden
        XCTAssertFalse(
            ProactiveNotificationService.isCooldownActive(
                lastNotificationDate: lastSent,
                now: now
            ),
            "Cooldown is < cooldownSeconds (strict less-than) — exact 24u betekent: weer toegestaan."
        )
    }

    // MARK: - Banister TRIMP

    func testBanisterTRIMP_NilHeartRate_FallsBackToZone2Estimate() {
        let trimp = ProactiveNotificationService.banisterTRIMP(
            durationMinutes: 60,
            averageHeartRate: nil
        )
        XCTAssertEqual(trimp, 90, accuracy: 0.001,
                       "60 min × 1.5 TRIMP/min = 90 (Zone 2 schatting).")
    }

    func testBanisterTRIMP_HeartRateBelowResting_FallsBackToZone2Estimate() {
        // hr <= restingHR (60) zorgt dat de Banister-formule niet kan draaien
        // (deltaHR zou negatief zijn) — fallback naar de Zone 2-schatting.
        let trimp = ProactiveNotificationService.banisterTRIMP(
            durationMinutes: 30,
            averageHeartRate: 55
        )
        XCTAssertEqual(trimp, 45, accuracy: 0.001)
    }

    /// Bij een gemiddelde hartslag van 145 bpm (Zone 2), een typische duurloop:
    /// deltaHR = (145 - 60) / (190 - 60) ≈ 0.654
    /// trimp = 60 × 0.654 × 0.64 × exp(1.92 × 0.654) ≈ 60 × 0.654 × 0.64 × 3.524 ≈ 88.6
    func testBanisterTRIMP_Zone2HeartRate_ProducesExpectedValue() {
        let trimp = ProactiveNotificationService.banisterTRIMP(
            durationMinutes: 60,
            averageHeartRate: 145
        )
        XCTAssertEqual(trimp, 88.6, accuracy: 1.0,
                       "Zone 2-loop van 60 min @ 145 bpm hoort rond 88-89 TRIMP te zitten.")
    }

    /// Zone 4 (170 bpm): hogere deltaHR exponentieel → veel hogere TRIMP per minuut.
    func testBanisterTRIMP_HighIntensity_ProducesHigherTRIMPThanZone2() {
        let zone2 = ProactiveNotificationService.banisterTRIMP(
            durationMinutes: 30,
            averageHeartRate: 145
        )
        let zone4 = ProactiveNotificationService.banisterTRIMP(
            durationMinutes: 30,
            averageHeartRate: 170
        )
        XCTAssertGreaterThan(zone4, zone2,
                             "Hogere HR moet exponentieel hogere TRIMP geven (Banister gewichtsfunctie).")
    }

    /// Custom rusthartslag (bijv. atletische gebruiker met RHR 50) verandert de uitkomst.
    func testBanisterTRIMP_CustomRestingHR_ChangesResult() {
        let defaultRHR = ProactiveNotificationService.banisterTRIMP(
            durationMinutes: 30,
            averageHeartRate: 130,
            restingHR: 60
        )
        let athleteRHR = ProactiveNotificationService.banisterTRIMP(
            durationMinutes: 30,
            averageHeartRate: 130,
            restingHR: 50
        )
        XCTAssertNotEqual(defaultRHR, athleteRHR, accuracy: 0.001,
                          "Lagere rusthartslag bij dezelfde HR verandert deltaHR en dus de TRIMP-uitkomst.")
    }

    // MARK: - Engine B drempelwaarden

    func testEngineBInactivityThreshold_IsTwoDays() {
        XCTAssertEqual(
            ProactiveNotificationService.engineBInactivityThresholdDays,
            2,
            "Drempelwaarde voor inactiviteit is gepind op 2 dagen — dit is een UX-keuze die we vastpinnen."
        )
    }

    func testCooldownWindow_IsTwentyFourHours() {
        XCTAssertEqual(
            ProactiveNotificationService.proactiveCooldownSeconds,
            86400,
            "Cooldown is gepind op 24 uur (1 notificatie per dag)."
        )
    }
}
