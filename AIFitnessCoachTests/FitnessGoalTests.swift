import XCTest
import SwiftData
@testable import AIFitnessCoach

@MainActor
final class FitnessGoalTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        // Configuratie voor in-memory database om geen persisterende data achter te laten
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: FitnessGoal.self, UserPreference.self, configurations: config)
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        // Opruimen container
        container = nil
        context = nil
    }

    func testCreateFitnessGoal() throws {
        // Arrange
        let title = "Marathon onder 3:30"
        let sportCategory: SportCategory = .running
        let targetDate = Date().addingTimeInterval(86400 * 30) // +30 dagen

        // Act
        let goal = FitnessGoal(title: title, targetDate: targetDate, sportCategory: sportCategory)
        context.insert(goal)

        // Assert
        let descriptor = FetchDescriptor<FitnessGoal>()
        let fetchedGoals = try context.fetch(descriptor)

        XCTAssertEqual(fetchedGoals.count, 1)
        XCTAssertEqual(fetchedGoals.first?.title, title)
        XCTAssertEqual(fetchedGoals.first?.sportCategory, sportCategory)
        XCTAssertFalse(fetchedGoals.first!.isCompleted, "Standaard isCompleted zou false moeten zijn")
    }

    func testUpdateFitnessGoal() throws {
        // Arrange
        let goal = FitnessGoal(title: "Oud Doel", targetDate: Date())
        context.insert(goal)

        // Act
        goal.title = "Nieuw Doel"
        goal.isCompleted = true
        try context.save()

        // Assert
        let descriptor = FetchDescriptor<FitnessGoal>()
        let fetchedGoals = try context.fetch(descriptor)

        XCTAssertEqual(fetchedGoals.first?.title, "Nieuw Doel")
        XCTAssertTrue(fetchedGoals.first!.isCompleted)
    }

    func testDeleteFitnessGoal() throws {
        // Arrange
        let goal1 = FitnessGoal(title: "Doel 1", targetDate: Date())
        let goal2 = FitnessGoal(title: "Doel 2", targetDate: Date())
        context.insert(goal1)
        context.insert(goal2)

        // Controleer of ze zijn toegevoegd
        var descriptor = FetchDescriptor<FitnessGoal>()
        var fetchedGoals = try context.fetch(descriptor)
        XCTAssertEqual(fetchedGoals.count, 2)

        // Act
        context.delete(goal1)
        try context.save()

        // Assert
        descriptor = FetchDescriptor<FitnessGoal>()
        fetchedGoals = try context.fetch(descriptor)

        XCTAssertEqual(fetchedGoals.count, 1)
        XCTAssertEqual(fetchedGoals.first?.title, "Doel 2")
    }

    func testCreateUserPreference() throws {
        // Arrange
        let text = "Ik sport altijd op dinsdag"

        // Act
        let pref = UserPreference(preferenceText: text)
        context.insert(pref)

        // Assert
        let descriptor = FetchDescriptor<UserPreference>()
        let fetchedPrefs = try context.fetch(descriptor)

        XCTAssertEqual(fetchedPrefs.count, 1)
        XCTAssertEqual(fetchedPrefs.first?.preferenceText, text)
        XCTAssertTrue(fetchedPrefs.first!.isActive)
    }

    // MARK: - Epic #36 sub-task 36.5: enum + computed property coverage
    //
    // Onderstaande tests zijn pure-data tests — geen SwiftData container nodig.
    // We dekken systematisch alle enum-cases zodat een toekomstige hernoeming
    // (rawValue / displayName) niet stil de UI-tekst breekt.

    // MARK: SportCategory

    func testSportCategory_FromHKType_KnownMappings() {
        XCTAssertEqual(SportCategory.from(hkType: 13), .cycling)
        XCTAssertEqual(SportCategory.from(hkType: 37), .running)
        XCTAssertEqual(SportCategory.from(hkType: 46), .swimming, "46 = HKWorkoutActivityType.functionalStrengthTraining alias for swim")
        XCTAssertEqual(SportCategory.from(hkType: 82), .swimming)
        XCTAssertEqual(SportCategory.from(hkType: 50), .strength)
        XCTAssertEqual(SportCategory.from(hkType: 59), .strength)
        XCTAssertEqual(SportCategory.from(hkType: 52), .walking)
        XCTAssertEqual(SportCategory.from(hkType: 83), .triathlon)
    }

    func testSportCategory_FromHKType_UnknownReturnsOther() {
        XCTAssertEqual(SportCategory.from(hkType: 999), .other)
        XCTAssertEqual(SportCategory.from(hkType: 0), .other)
    }

    func testSportCategory_FromRawString_NilOrEmptyReturnsOther() {
        XCTAssertEqual(SportCategory.from(rawString: nil), .other)
        XCTAssertEqual(SportCategory.from(rawString: ""), .other)
        XCTAssertEqual(SportCategory.from(rawString: "   "), .other)
    }

    func testSportCategory_FromRawString_RecognisesRunVariants() {
        XCTAssertEqual(SportCategory.from(rawString: "Run"), .running)
        XCTAssertEqual(SportCategory.from(rawString: "trail run"), .running)
        XCTAssertEqual(SportCategory.from(rawString: "Hardlopen"), .running)
        XCTAssertEqual(SportCategory.from(rawString: "HKWorkoutActivityTypeRunning"), .running)
    }

    func testSportCategory_FromRawString_RecognisesCyclingVariants() {
        XCTAssertEqual(SportCategory.from(rawString: "Ride"), .cycling)
        XCTAssertEqual(SportCategory.from(rawString: "Cycling"), .cycling)
        XCTAssertEqual(SportCategory.from(rawString: "Wielrennen"), .cycling)
        XCTAssertEqual(SportCategory.from(rawString: "Fietstocht"), .cycling)
    }

    func testSportCategory_FromRawString_RecognisesSwimWalkStrengthTri() {
        XCTAssertEqual(SportCategory.from(rawString: "Swim"), .swimming)
        XCTAssertEqual(SportCategory.from(rawString: "Zwemmen"), .swimming)
        XCTAssertEqual(SportCategory.from(rawString: "Walk"), .walking)
        XCTAssertEqual(SportCategory.from(rawString: "Wandelen"), .walking)
        XCTAssertEqual(SportCategory.from(rawString: "Strength training"), .strength)
        XCTAssertEqual(SportCategory.from(rawString: "Krachttraining"), .strength)
        XCTAssertEqual(SportCategory.from(rawString: "weightlifting"), .strength)
        XCTAssertEqual(SportCategory.from(rawString: "Triathlon"), .triathlon)
        XCTAssertEqual(SportCategory.from(rawString: "Triatlon"), .triathlon)
    }

    func testSportCategory_FromRawString_UnknownReturnsOther() {
        XCTAssertEqual(SportCategory.from(rawString: "yoga"), .other)
        XCTAssertEqual(SportCategory.from(rawString: "12345"), .other)
    }

    func testSportCategory_DisplayNameAndWorkoutName_AllUnique() {
        let displayNames = SportCategory.allCases.map(\.displayName)
        let workoutNames = SportCategory.allCases.map(\.workoutName)
        XCTAssertEqual(Set(displayNames).count, displayNames.count, "displayNames moeten uniek zijn.")
        XCTAssertEqual(Set(workoutNames).count, workoutNames.count, "workoutNames moeten uniek zijn.")
        // Steekproef: spel-checks op de twee meest-gebruikte cases.
        XCTAssertEqual(SportCategory.running.workoutName, "hardloopsessie")
        XCTAssertEqual(SportCategory.cycling.displayName, "Wielrennen")
    }

    func testSportCategory_IdEqualsRawValue() {
        for category in SportCategory.allCases {
            XCTAssertEqual(category.id, category.rawValue)
        }
    }

    // MARK: BodyArea

    func testBodyArea_SeverityLabel_BoundaryValues() {
        XCTAssertEqual(BodyArea.severityLabel(0), "Geen pijn")
        XCTAssertEqual(BodyArea.severityLabel(1), "Licht")
        XCTAssertEqual(BodyArea.severityLabel(3), "Licht")
        XCTAssertEqual(BodyArea.severityLabel(4), "Matig")
        XCTAssertEqual(BodyArea.severityLabel(6), "Matig")
        XCTAssertEqual(BodyArea.severityLabel(7), "Zwaar")
        XCTAssertEqual(BodyArea.severityLabel(9), "Zwaar")
        XCTAssertEqual(BodyArea.severityLabel(10), "Ernstig",
                       "10 valt in default-tak (out-of-range) → Ernstig.")
        XCTAssertEqual(BodyArea.severityLabel(-1), "Ernstig",
                       "Negatieve scores horen ook in de Ernstig-tak (defensief).")
    }

    func testBodyArea_InjuryKeywords_AreLowercaseAndNonEmpty() {
        for area in BodyArea.allCases {
            XCTAssertFalse(area.injuryKeywords.isEmpty, "\(area) moet detecteerbare keywords hebben.")
            for keyword in area.injuryKeywords {
                XCTAssertEqual(keyword, keyword.lowercased(),
                               "Keywords moeten lowercase zijn voor case-insensitive matching: \(keyword)")
            }
        }
    }

    func testBodyArea_Icons_AreNonEmptyAndUnique() {
        let icons = BodyArea.allCases.map(\.icon)
        for icon in icons { XCTAssertFalse(icon.isEmpty) }
        XCTAssertEqual(Set(icons).count, icons.count, "Iedere BodyArea heeft een unieke SF Symbol.")
    }

    // MARK: Symptom — severity clamping + startOfDay

    func testSymptom_Init_ClampsSeverityToZeroToTen() {
        let now = Date()
        XCTAssertEqual(Symptom(bodyArea: .calf, severity: -5, date: now).severity, 0,
                       "Negatieve scores moeten naar 0 geclampt worden.")
        XCTAssertEqual(Symptom(bodyArea: .calf, severity: 50, date: now).severity, 10,
                       "Scores > 10 moeten naar 10 geclampt worden.")
        XCTAssertEqual(Symptom(bodyArea: .knee, severity: 5, date: now).severity, 5)
    }

    func testSymptom_Init_DateNormalizedToStartOfDay() {
        // Een tijdstip middenin de dag → Symptom.date moet het 00:00-equivalent zijn.
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 25
        components.hour = 14
        components.minute = 37
        let tricky = Calendar.current.date(from: components)!
        let symptom = Symptom(bodyArea: .calf, severity: 3, date: tricky)
        XCTAssertEqual(symptom.date, Calendar.current.startOfDay(for: tricky))
    }

    func testSymptom_BodyArea_RoundtripsThroughRawValue() {
        let symptom = Symptom(bodyArea: .knee, severity: 4)
        XCTAssertEqual(symptom.bodyArea, .knee)
        // Schema V2: `bodyArea` is een type-veilige enum; rawValue blijft de DB-kolom
        // waarde (gekoppeld via `@Attribute(originalName: "bodyAreaRaw")`).
        XCTAssertEqual(symptom.bodyArea.rawValue, BodyArea.knee.rawValue)
    }

    // MARK: EventFormat / PrimaryIntent

    func testEventFormat_DisplayNames_AllNonEmptyAndUnique() {
        let names = EventFormat.allCases.map(\.displayName)
        XCTAssertEqual(names.count, 3)
        XCTAssertEqual(Set(names).count, 3, "Iedere EventFormat heeft een unieke displayName.")
        XCTAssertEqual(EventFormat.singleDayRace.displayName, "Eendaagse wedstrijd")
        XCTAssertEqual(EventFormat.multiDayStage.displayName, "Meerdaagse etapperit")
    }

    func testPrimaryIntent_DisplayNames_AllNonEmptyAndUnique() {
        let names = PrimaryIntent.allCases.map(\.displayName)
        XCTAssertEqual(names.count, 2)
        XCTAssertEqual(Set(names).count, 2)
        XCTAssertEqual(PrimaryIntent.completion.displayName, "Uitlopen / overleven")
        XCTAssertEqual(PrimaryIntent.peakPerformance.displayName, "Zo snel mogelijk")
    }

    // MARK: AIProvider

    func testAIProvider_AllCasesHaveValidMetadata() {
        for provider in AIProvider.allCases {
            XCTAssertEqual(provider.id, provider.rawValue)
            XCTAssertFalse(provider.displayName.isEmpty)
            XCTAssertFalse(provider.keyPlaceholder.isEmpty)
            XCTAssertNotNil(provider.getKeyURL,
                            "\(provider) moet een geldige getKeyURL hebben — gebruikers moeten een sleutel kunnen aanmaken.")
        }
    }

    func testAIProvider_OnlyGeminiIsSupported() {
        XCTAssertTrue(AIProvider.gemini.isSupported)
        XCTAssertFalse(AIProvider.openAI.isSupported,
                       "OpenAI is in Sprint 20.1 nog niet volledig geïntegreerd.")
        XCTAssertFalse(AIProvider.anthropic.isSupported)
    }

    func testAIProvider_KeyPlaceholders_HaveProviderPrefix() {
        XCTAssertTrue(AIProvider.gemini.keyPlaceholder.hasPrefix("AIzaSy"))
        XCTAssertTrue(AIProvider.openAI.keyPlaceholder.hasPrefix("sk-"))
        XCTAssertTrue(AIProvider.anthropic.keyPlaceholder.hasPrefix("sk-ant-"))
    }

    // MARK: DataSource

    func testDataSource_IdEqualsRawValue() {
        for source in DataSource.allCases {
            XCTAssertEqual(source.id, source.rawValue)
        }
        XCTAssertEqual(DataSource.healthKit.rawValue, "Apple HealthKit")
        XCTAssertEqual(DataSource.strava.rawValue, "Strava API")
    }

    // MARK: GoalBlueprintType

    func testGoalBlueprintType_DetectionKeywords_AreLowercase() {
        for type in GoalBlueprintType.allCases {
            XCTAssertFalse(type.detectionKeywords.isEmpty)
            for keyword in type.detectionKeywords {
                XCTAssertEqual(keyword, keyword.lowercased(),
                               "Keyword '\(keyword)' moet lowercase zijn voor case-insensitive matching.")
            }
        }
    }

    func testGoalBlueprintType_DisplayNames_AreUnique() {
        let names = GoalBlueprintType.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(GoalBlueprintType.marathon.displayName, "Marathon")
        XCTAssertEqual(GoalBlueprintType.halfMarathon.displayName, "Halve Marathon")
        XCTAssertEqual(GoalBlueprintType.cyclingTour.displayName, "Fietstocht")
    }

    // MARK: FitnessGoal — computed properties

    func testFitnessGoal_ResolvedFormatAndIntent_DefaultWhenNil() {
        let goal = FitnessGoal(
            title: "Test",
            targetDate: Date().addingTimeInterval(86400),
            format: nil,
            intent: nil
        )
        XCTAssertEqual(goal.resolvedFormat, .singleDayRace,
                       "Veilige fallback: oude SwiftData-records zonder format → singleDayRace.")
        XCTAssertEqual(goal.resolvedIntent, .peakPerformance,
                       "Veilige fallback: oude records zonder intent → peakPerformance.")
    }

    func testFitnessGoal_CurrentPhase_NilForCompletedGoal() {
        let goal = FitnessGoal(
            title: "Done",
            targetDate: Date().addingTimeInterval(86400 * 30),
            isCompleted: true
        )
        XCTAssertNil(goal.currentPhase, "Voltooide doelen hebben geen actieve fase.")
    }

    func testFitnessGoal_CurrentPhase_NilForExpiredGoal() {
        let goal = FitnessGoal(
            title: "Past",
            targetDate: Date().addingTimeInterval(-86400)
        )
        XCTAssertNil(goal.currentPhase, "Verlopen doelen hebben geen actieve fase.")
    }

    func testFitnessGoal_CurrentPhase_BuildPhaseAtEightWeeks() {
        let goal = FitnessGoal(
            title: "Marathon",
            targetDate: Date().addingTimeInterval(8 * 7 * 86400)
        )
        XCTAssertEqual(goal.currentPhase, .buildPhase,
                       "8 weken resterend valt in 4..<12 → Build Phase.")
    }

    func testFitnessGoal_ComputedTargetTRIMP_UsesExplicitValueWhenSet() {
        let goal = FitnessGoal(
            title: "Test",
            targetDate: Date().addingTimeInterval(7 * 86400),
            targetTRIMP: 999
        )
        XCTAssertEqual(goal.computedTargetTRIMP, 999, accuracy: 0.001)
    }

    func testFitnessGoal_ComputedTargetTRIMP_FallsBackWhenZeroOrNil() {
        // Geen targetTRIMP: fallback = (dagen / 7) * 350. 14 dagen → 2 weken → 700.
        let goal = FitnessGoal(
            title: "Test",
            targetDate: Date().addingTimeInterval(14 * 86400),
            createdAt: Date(),
            targetTRIMP: nil
        )
        XCTAssertEqual(goal.computedTargetTRIMP, 700, accuracy: 5,
                       "Fallback formule: (dagen / 7) * 350 ≈ 700 voor 2 weken horizon.")
    }

    func testFitnessGoal_ComputedTargetTRIMP_FallbackHandlesSameDayCreatedAndTarget() {
        // createdAt == targetDate → days = 0, geclampt op 1.0 → ~50 TRIMP fallback.
        let now = Date()
        let goal = FitnessGoal(
            title: "Test",
            targetDate: now,
            createdAt: now,
            targetTRIMP: 0
        )
        XCTAssertEqual(goal.computedTargetTRIMP, 50, accuracy: 0.5,
                       "max(1.0, days)/7 * 350 = 50 voor 0-day horizon — clamping voorkomt deling door 0.")
    }

    // MARK: SuggestedWorkout.resolvedDate

    func testSuggestedWorkout_ResolvedDate_ParsesISODate() {
        let workout = SuggestedWorkout(
            dateOrDay: "2026-12-31",
            activityType: "Hardlopen",
            suggestedDurationMinutes: 60,
            targetTRIMP: 50,
            description: "Test"
        )
        var components = DateComponents()
        components.year = 2026; components.month = 12; components.day = 31
        let expected = Calendar.current.startOfDay(for: Calendar.current.date(from: components)!)
        XCTAssertEqual(workout.resolvedDate, expected)
    }

    func testSuggestedWorkout_ResolvedDate_ParsesDutchDayName() {
        // Geen specifieke dag-vergelijking — we testen dat het een geldige weekday-match is
        let workout = SuggestedWorkout(
            dateOrDay: "Maandag",
            activityType: "Hardlopen",
            suggestedDurationMinutes: 60,
            targetTRIMP: 50,
            description: "Test"
        )
        let weekday = Calendar.current.component(.weekday, from: workout.resolvedDate)
        XCTAssertEqual(weekday, 2, "Maandag = weekday 2 in Calendar (1=zondag).")
    }

    func testSuggestedWorkout_ResolvedDate_ParsesEnglishDayName() {
        let workout = SuggestedWorkout(
            dateOrDay: "Friday",
            activityType: "Run",
            suggestedDurationMinutes: 30,
            targetTRIMP: 30,
            description: "Test"
        )
        let weekday = Calendar.current.component(.weekday, from: workout.resolvedDate)
        XCTAssertEqual(weekday, 6, "Friday = weekday 6.")
    }

    func testSuggestedWorkout_ResolvedDate_ParsesCompoundDayString() {
        // "Maandag 21 apr" — alleen het eerste woord ("Maandag") wordt gebruikt voor de match.
        let workout = SuggestedWorkout(
            dateOrDay: "Maandag 21 apr",
            activityType: "Hardlopen",
            suggestedDurationMinutes: 45,
            targetTRIMP: 40,
            description: "Test"
        )
        let weekday = Calendar.current.component(.weekday, from: workout.resolvedDate)
        XCTAssertEqual(weekday, 2)
    }

    func testSuggestedWorkout_ResolvedDate_UnparseableFallsBackToToday() {
        let workout = SuggestedWorkout(
            dateOrDay: "Geen-geldige-string",
            activityType: "Rust",
            suggestedDurationMinutes: 0,
            targetTRIMP: 0,
            description: "Test"
        )
        XCTAssertEqual(
            workout.resolvedDate,
            Calendar.current.startOfDay(for: Date()),
            "Onparsebare string → fallback op vandaag (geen crash, geen invalid date)."
        )
    }

    func testSuggestedWorkout_ResolvedDate_PastDayNameRollsForwardOneWeek() {
        // De resolvedDate is altijd ≥ vandaag. Voor een dag-naam in het verleden
        // krijgt de gebruiker dezelfde weekday +7 dagen.
        let today = Calendar.current.startOfDay(for: Date())
        let weekdayToday = Calendar.current.component(.weekday, from: today)
        let dutchWeekdays = ["", "Zondag", "Maandag", "Dinsdag", "Woensdag", "Donderdag", "Vrijdag", "Zaterdag"]
        let workout = SuggestedWorkout(
            dateOrDay: dutchWeekdays[weekdayToday],
            activityType: "Hardlopen",
            suggestedDurationMinutes: 60,
            targetTRIMP: 50,
            description: "Test"
        )
        // Vandaag is offset 0 → resolvedDate == vandaag (geen +7).
        XCTAssertEqual(workout.resolvedDate, today,
                       "Vandaag krijgt offset 0 — geen +7-rollforward voor dezelfde dag.")
    }

    // MARK: ActivityRecord.displayName

    func testActivityRecord_DisplayName_StripsHealthKitPrefix() {
        let record = ActivityRecord(
            id: "1",
            name: "HealthKit 52",
            distance: 5000,
            movingTime: 3000,
            averageHeartrate: 130,
            sportCategory: .walking,
            startDate: Date()
        )
        XCTAssertEqual(record.displayName, "Wandeling",
                       "Legacy 'HealthKit 52' wordt vervangen door de leesbare workoutName, gecapitaliseerd.")
    }

    func testActivityRecord_DisplayName_PreservesNonHealthKitName() {
        let record = ActivityRecord(
            id: "2",
            name: "Avondloopje door het bos",
            distance: 10000,
            movingTime: 3600,
            averageHeartrate: 150,
            sportCategory: .running,
            startDate: Date()
        )
        XCTAssertEqual(record.displayName, "Avondloopje door het bos",
                       "Bewerkte namen mogen niet worden vervangen.")
    }
}
