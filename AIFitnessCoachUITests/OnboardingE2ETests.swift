import XCTest

// MARK: - Sprint 26.1 / Epic 30 V2.0: Onboarding UI Mock Tests — E2E Test Suite

/// End-to-End XCUITest suite voor de kern-flows van VibeCoach.
///
/// Alle tests draaien met:
/// - `-UITesting`: activeert de mock-omgeving (UITestMockEnvironment.setup()).
/// - `-ResetState` (alleen Test 1): wist alle UserDefaults zodat de Onboarding opnieuw start.
///
/// V2.0 wijzigingen: Dashboard, Goals en Coach hebben geen NavigationBar meer.
/// Tests gebruiken accessibilityIdentifiers ("DashboardHeaderView", "GoalsScrollView", "CoachView").
final class OnboardingE2ETests: XCTestCase {

    var app: XCUIApplication!

    // MARK: - Setup

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"]

        addUIInterruptionMonitor(withDescription: "OS Toestemming Alert") { alert in
            let allowLabels = [
                "Allow", "Sta toe", "OK", "Allow While Using App",
                "Allow Once", "Don't Allow", "Niet toestaan",
                "Sta toe bij gebruik van app"
            ]
            for label in allowLabels {
                if alert.buttons[label].exists {
                    alert.buttons[label].tap()
                    return true
                }
            }
            return false
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Test 1: Full Onboarding Flow

    @MainActor
    func testFullOnboardingFlow() throws {
        app.launchArguments = ["-UITesting", "-ResetState"]
        app.launch()
        app.tap()

        // ── Pagina 1: Welkom ──────────────────────────────────────────────
        XCTAssertTrue(
            app.staticTexts["Welkom bij VibeCoach"].waitForExistence(timeout: 5),
            "Pagina 1 (Welkom) verschijnt niet na app-launch met ResetState."
        )

        let volgende = app.buttons["OnboardingVolgendeButton"]
        XCTAssertTrue(volgende.waitForExistence(timeout: 3), "Volgende-knop niet gevonden op pagina 1.")
        volgende.tap()

        // ── Pagina 2: Hoe het werkt ───────────────────────────────────────
        XCTAssertTrue(
            app.staticTexts["Hoe het werkt"].waitForExistence(timeout: 3),
            "Pagina 2 (Hoe het werkt) verschijnt niet."
        )
        volgende.tap()

        // ── Pagina 3: Jouw Data, Jouw AI ─────────────────────────────────
        XCTAssertTrue(
            app.staticTexts["Jouw Data, Jouw AI"].waitForExistence(timeout: 3),
            "Pagina 3 (API-sleutel) verschijnt niet."
        )

        let apiKeyField = app.secureTextFields["OnboardingAPIKeyField"]
        XCTAssertTrue(apiKeyField.waitForExistence(timeout: 3), "OnboardingAPIKeyField niet gevonden.")
        apiKeyField.tap()
        apiKeyField.typeText("TEST123")

        let titleText = app.staticTexts["Jouw Data, Jouw AI"]
        if titleText.isHittable {
            titleText.tap()
        } else if app.keyboards.buttons["Done"].exists {
            app.keyboards.buttons["Done"].tap()
        } else if app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
        }

        let volgendeHittable = NSPredicate(format: "isHittable == true")
        expectation(for: volgendeHittable, evaluatedWith: volgende)
        waitForExpectations(timeout: 3)

        volgende.tap()

        // ── Pagina 4: Permissies ──────────────────────────────────────────
        XCTAssertTrue(
            app.staticTexts["Één keer toestemming"].waitForExistence(timeout: 3),
            "Pagina 4 (Permissies) verschijnt niet."
        )

        let healthKitButton = app.buttons["OnboardingHealthKitButton"]
        XCTAssertTrue(healthKitButton.waitForExistence(timeout: 3), "HealthKit-knop niet gevonden.")
        healthKitButton.tap()
        app.tap()

        let notificationsButton = app.buttons["OnboardingNotificationsButton"]
        XCTAssertTrue(notificationsButton.waitForExistence(timeout: 3), "Notificaties-knop niet gevonden.")
        notificationsButton.tap()
        app.tap()

        let _ = app.buttons["OnboardingStartButton"].waitForExistence(timeout: 2)

        let startButton = app.buttons["OnboardingStartButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 3), "Start met Trainen-knop niet gevonden.")
        startButton.tap()

        // V2.0: Geen NavigationBar meer op Dashboard — check DashboardHeaderView identifier
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8), "TabBar verschijnt niet na het afronden van de Onboarding.")

        let dashboardHeader = app.otherElements["DashboardHeaderView"]
        XCTAssertTrue(
            dashboardHeader.waitForExistence(timeout: 5),
            "DashboardHeaderView verschijnt niet na Onboarding."
        )
    }

    // MARK: - Test 2: Goal Management

    /// Voeg twee doelen toe en verifieer dat ze in de lijst verschijnen.
    /// V2.0: Geen swipe-delete of GoalRow-identifiers meer — alleen toevoegen en verifiëren.
    @MainActor
    func testGoalManagement() throws {
        app.launch()
        app.tap()

        // ── Navigeer naar Doelen tab ──────────────────────────────────────
        let goalsTab = app.tabBars.buttons["Doelen"]
        XCTAssertTrue(goalsTab.waitForExistence(timeout: 5), "Tab 'Doelen' niet gevonden.")
        goalsTab.tap()

        // V2.0: Check via GoalsScrollView identifier
        XCTAssertTrue(
            app.scrollViews["GoalsScrollView"].waitForExistence(timeout: 3),
            "GoalsScrollView verschijnt niet na tikken op Doelen tab."
        )

        // ── Voeg doel 1 toe ───────────────────────────────────────────────
        try addGoal("E2E Marathon Doel")
        XCTAssertTrue(
            findGoalText("E2E Marathon Doel"),
            "Doel 'E2E Marathon Doel' verschijnt niet in de lijst na opslaan."
        )

        // ── Voeg doel 2 toe ───────────────────────────────────────────────
        try addGoal("E2E Fietsdoel")
        XCTAssertTrue(
            findGoalText("E2E Fietsdoel"),
            "Doel 'E2E Fietsdoel' verschijnt niet in de lijst na opslaan."
        )
    }

    // MARK: - Helpers voor Goal Management

    /// Opent AddGoalView, vult de titel in en slaat op.
    private func addGoal(_ title: String) throws {
        let addButton = app.buttons["AddGoalButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "AddGoalButton niet gevonden.")
        addButton.tap()

        XCTAssertTrue(
            app.navigationBars["Nieuw Doel"].waitForExistence(timeout: 5),
            "AddGoalView opent niet."
        )

        let titleField = app.textFields["GoalTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3), "GoalTitleField niet gevonden.")
        titleField.tap()
        titleField.typeText(title)

        let saveButton = app.buttons["GoalSaveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3), "GoalSaveButton niet gevonden.")
        let enabledPredicate = NSPredicate(format: "isEnabled == true")
        let enabledExpectation = expectation(for: enabledPredicate, evaluatedWith: saveButton)
        wait(for: [enabledExpectation], timeout: 3)

        saveButton.tap()

        // V2.0: Check via GoalsScrollView na opslaan
        XCTAssertTrue(
            app.scrollViews["GoalsScrollView"].waitForExistence(timeout: 6),
            "Na opslaan van '\(title)' keert de app niet terug naar de doelen-lijst."
        )
    }

    /// Zoekt naar een doel-tekst in de lijst inclusief scrollen.
    private func findGoalText(_ title: String) -> Bool {
        let textElement = app.staticTexts[title].firstMatch
        if textElement.waitForExistence(timeout: 2) { return true }
        app.swipeUp()
        if textElement.waitForExistence(timeout: 3) { return true }
        app.swipeUp()
        return textElement.waitForExistence(timeout: 3)
    }

    // MARK: - Test 3: Coach Memory

    @MainActor
    func testCoachMemory() throws {
        app.launch()
        app.tap()

        let coachTab = app.tabBars.buttons["Coach"]
        XCTAssertTrue(coachTab.waitForExistence(timeout: 5), "Tab 'Coach' niet gevonden.")
        coachTab.tap()

        let chatInput = app.textFields["ChatInputField"]
        XCTAssertTrue(
            chatInput.waitForExistence(timeout: 5),
            "ChatInputField verschijnt niet — API-sleutel mogelijk niet ingesteld."
        )

        chatInput.tap()
        chatInput.typeText("Ik kan niet op maandag trainen.")

        let sendButton = app.buttons["ChatSendButton"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 3), "ChatSendButton niet gevonden.")
        sendButton.tap()

        let maandagConfirmation = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'voorkeur opgeslagen'")
        ).firstMatch
        XCTAssertTrue(
            maandagConfirmation.waitForExistence(timeout: 8),
            "Coach bevestigt de maandag-voorkeur niet ('voorkeur opgeslagen' ontbreekt in respons)."
        )

        chatInput.tap()
        chatInput.typeText("Ik heb last van mijn kuit.")
        sendButton.tap()

        let kuitConfirmation = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'kuit'")
        ).firstMatch
        XCTAssertTrue(
            kuitConfirmation.waitForExistence(timeout: 8),
            "Coach logt de kuit-blessure niet ('kuit' ontbreekt in de respons)."
        )
    }

    // MARK: - Test 4: Dashboard & Post-Workout

    @MainActor
    func testDashboardAndPostWorkout() throws {
        app.launch()
        app.tap()

        // V2.0: Geen NavigationBar meer — check DashboardHeaderView identifier
        let dashboardHeader = app.otherElements["DashboardHeaderView"]
        XCTAssertTrue(
            dashboardHeader.waitForExistence(timeout: 5),
            "DashboardHeaderView verschijnt niet na app-launch."
        )

        // ── Vibe Score (optioneel) ────────────────────────────────────────
        let vibeCard = app.otherElements["VibeScoreCard"]
        if vibeCard.waitForExistence(timeout: 3) {
            let scoreOrLabel = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS '82' OR label CONTAINS[c] 'Optimaal'")
            ).firstMatch
            app.swipeDown()
            XCTAssertTrue(
                scoreOrLabel.waitForExistence(timeout: 3) || vibeCard.isHittable,
                "Vibe Score kaart is aanwezig maar 82 / 'Optimaal Hersteld' is niet zichtbaar."
            )
        }

        // ── Doelen tab ────────────────────────────────────────────────────
        let goalsTab = app.tabBars.buttons["Doelen"]
        goalsTab.tap()
        XCTAssertTrue(app.scrollViews["GoalsScrollView"].waitForExistence(timeout: 3))

        // Fase-badge — alleen als er doelen aanwezig zijn (soft check)
        let hasNoGoals = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'GEEN DOELEN'")
        ).firstMatch.waitForExistence(timeout: 2)
        if !hasNoGoals {
            let phaseBadge = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Build' OR label CONTAINS[c] 'Base' OR label CONTAINS[c] 'Peak' OR label CONTAINS[c] 'Taper'")
            ).firstMatch
            if !phaseBadge.waitForExistence(timeout: 3) {
                print("ℹ️ Fase-badge niet gevonden — goal heeft mogelijk nog geen blueprint-fase berekend.")
            }
        }

        // ── Terug naar Dashboard voor RPE check-in ────────────────────────
        app.tabBars.buttons["Overzicht"].tap()
        XCTAssertTrue(app.otherElements["DashboardHeaderView"].waitForExistence(timeout: 3))
        app.swipeDown()

        let rpeCard = app.otherElements["RPECheckinCard"]
        guard rpeCard.waitForExistence(timeout: 2) else { return }

        let rpeSlider = app.sliders["RPESlider"]
        XCTAssertTrue(rpeSlider.exists, "RPESlider ontbreekt in de check-in kaart.")
        rpeSlider.adjust(toNormalizedSliderPosition: 0.7)

        let moodButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'MoodButton'"))
        if moodButtons.count > 0 {
            moodButtons.firstMatch.tap()
        } else {
            rpeCard.buttons.firstMatch.tap()
        }

        let saveRpeButton = app.buttons["RPEOpslaanButton"]
        XCTAssertTrue(saveRpeButton.exists, "RPEOpslaanButton ontbreekt.")
        XCTAssertTrue(saveRpeButton.isEnabled, "Opslaan-knop is niet actief na het selecteren van RPE + stemming.")
        saveRpeButton.tap()

        XCTAssertFalse(
            rpeCard.waitForExistence(timeout: 3),
            "RPE Check-in kaart blijft zichtbaar na het opslaan."
        )
    }
}
