import XCTest

// MARK: - Sprint 26.1 / Epic 30 V2.0: Onboarding UI Mock Tests — E2E Test Suite

/// V2.0 wijzigingen t.o.v. Sprint 26.1:
/// - Dashboard heeft geen NavigationBar meer → check via begroetingstekst ("Goede...")
/// - Goals heeft geen NavigationBar meer → check via grote "Doelen" statische tekst
/// - testGoalManagement vereenvoudigd: swipe-delete en GoalRow-identifiers verwijderd
///   (V2.0 card-layout heeft geen List meer met swipe-acties)
final class OnboardingE2ETests: XCTestCase {

    var app: XCUIApplication!

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
                if alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            }
            return false
        }
    }

    override func tearDownWithError() throws { app = nil }

    // MARK: - Helpers

    private func waitForDashboard(timeout: TimeInterval = 5) -> Bool {
        app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Goede'")
        ).firstMatch.waitForExistence(timeout: timeout)
    }

    private func waitForGoalsView(timeout: TimeInterval = 3) -> Bool {
        // "Doelen" als largeTitle Text (elementType 48 = staticText)
        let pred = NSPredicate(format: "elementType == 48 AND label == 'Doelen'")
        return app.descendants(matching: .any).matching(pred).firstMatch.waitForExistence(timeout: timeout)
    }

    // MARK: - Test 1: Full Onboarding Flow (Epic #31 Sprint 31.6 — V2.0 flow met 5 stappen)

    /// Doorloopt de V2.0 onboarding-flow volgens het UX-prototype. Alle vijf
    /// stappen gebruiken dezelfde `OnboardingPrimaryButton` identifier — de
    /// verschillen tussen stappen worden via titel-teksten geverifieerd.
    ///
    /// Stap 4 (Apple Health) vraagt twee taps in `-UITesting` mode: de eerste
    /// zet `healthKitState = .granted` (bypass van iOS-permissie-popup), de
    /// tweede roept `advance()` aan. Stap 5 (Notificaties) voltooit direct
    /// bij de eerste tap omdat `requestNotifications()` in UITesting mode
    /// meteen `completeOnboarding()` aanroept.
    @MainActor
    func testFullOnboardingFlow() throws {
        app.launchArguments = ["-UITesting", "-ResetState"]
        app.launch()
        app.tap()

        let primary = app.buttons["OnboardingPrimaryButton"]

        // ── Stap 1: Welkom ─────────────────────────────────────────────────
        XCTAssertTrue(
            app.staticTexts["Je lichaam stuurt, wij luisteren mee."].waitForExistence(timeout: 5),
            "Stap 1 (Welkom) verschijnt niet na launch met -ResetState."
        )
        XCTAssertTrue(primary.waitForExistence(timeout: 3), "Primaire knop niet gevonden op stap 1.")
        primary.tap()

        // ── Stap 2: Hoe het werkt ──────────────────────────────────────────
        XCTAssertTrue(
            app.staticTexts["Herstel meten, belasting plannen."].waitForExistence(timeout: 3),
            "Stap 2 (Hoe het werkt) verschijnt niet."
        )
        primary.tap()

        // ── Stap 3: Jouw AI ────────────────────────────────────────────────
        XCTAssertTrue(
            app.staticTexts["Jouw data, jouw AI-sleutel."].waitForExistence(timeout: 3),
            "Stap 3 (Jouw AI) verschijnt niet."
        )
        // De provider-picker moet aanwezig zijn; we hoeven hem niet aan te passen —
        // Gemini is de default en de sleutel-invoer is verplaatst naar Instellingen.
        XCTAssertTrue(
            app.otherElements["OnboardingProviderPicker"].waitForExistence(timeout: 2)
                || app.segmentedControls.firstMatch.waitForExistence(timeout: 2),
            "Provider-picker ontbreekt op stap 3."
        )
        primary.tap()

        // ── Stap 4: Apple Health ───────────────────────────────────────────
        XCTAssertTrue(
            app.staticTexts["Koppel met Apple Health."].waitForExistence(timeout: 3),
            "Stap 4 (Apple Health) verschijnt niet."
        )
        // Eerste tap → requestHealthKit() zet state op .granted (UITesting-bypass).
        primary.tap()
        // Tweede tap → handleHealthKitAction() ziet .granted en roept advance() aan.
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: primary)
        waitForExpectations(timeout: 3)
        primary.tap()

        // ── Stap 5: Notificaties ───────────────────────────────────────────
        XCTAssertTrue(
            app.staticTexts["Coach-signalen, niet meer."].waitForExistence(timeout: 3),
            "Stap 5 (Notificaties) verschijnt niet."
        )
        // Eén tap: requestNotifications() zet state op .granted én roept
        // completeOnboarding() direct aan (UITesting-bypass).
        primary.tap()

        // V2.0: geen NavigationBar meer — check TabBar + begroetingstekst
        XCTAssertTrue(
            app.tabBars.firstMatch.waitForExistence(timeout: 8),
            "TabBar verschijnt niet na afgeronde onboarding."
        )
        XCTAssertTrue(
            waitForDashboard(),
            "Dashboard begroetingstekst verschijnt niet na afgeronde onboarding."
        )
    }

    // MARK: - Test 2: Goal Management

    /// Voeg twee doelen toe en verifieer dat ze zichtbaar zijn.
    /// V2.0: Geen swipe-delete of GoalRow-identifiers — card-layout heeft geen List meer.
    @MainActor
    func testGoalManagement() throws {
        app.launch()
        app.tap()

        let goalsTab = app.tabBars.buttons["Doelen"]
        XCTAssertTrue(goalsTab.waitForExistence(timeout: 5), "Tab 'Doelen' niet gevonden.")
        goalsTab.tap()

        XCTAssertTrue(waitForGoalsView(), "Doelen-scherm laadt niet na tikken op tab.")

        try addGoal("E2E Marathon Doel")
        XCTAssertTrue(findGoalText("E2E Marathon Doel"), "Doel 'E2E Marathon Doel' verschijnt niet na opslaan.")

        try addGoal("E2E Fietsdoel")
        XCTAssertTrue(findGoalText("E2E Fietsdoel"), "Doel 'E2E Fietsdoel' verschijnt niet na opslaan.")
    }

    // MARK: - Helpers Goal Management

    private func addGoal(_ title: String) throws {
        let addButton = app.buttons["AddGoalButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "AddGoalButton niet gevonden.")
        addButton.tap()

        XCTAssertTrue(app.navigationBars["Nieuw Doel"].waitForExistence(timeout: 5), "AddGoalView opent niet.")

        let titleField = app.textFields["GoalTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3), "GoalTitleField niet gevonden.")
        titleField.tap()
        titleField.typeText(title)

        let saveButton = app.buttons["GoalSaveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3), "GoalSaveButton niet gevonden.")
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: saveButton)
        waitForExpectations(timeout: 3)
        saveButton.tap()

        XCTAssertTrue(waitForGoalsView(timeout: 6), "App keert niet terug naar doelen-lijst na opslaan van '\(title)'.")
    }

    private func findGoalText(_ title: String) -> Bool {
        let el = app.staticTexts[title].firstMatch
        if el.waitForExistence(timeout: 2) { return true }
        app.swipeUp()
        if el.waitForExistence(timeout: 3) { return true }
        app.swipeUp()
        return el.waitForExistence(timeout: 3)
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
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5), "ChatInputField verschijnt niet.")

        chatInput.tap()
        chatInput.typeText("Ik kan niet op maandag trainen.")
        app.buttons["ChatSendButton"].tap()

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'voorkeur opgeslagen'"))
                .firstMatch.waitForExistence(timeout: 8),
            "Coach bevestigt de maandag-voorkeur niet."
        )

        chatInput.tap()
        chatInput.typeText("Ik heb last van mijn kuit.")
        app.buttons["ChatSendButton"].tap()

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'kuit'"))
                .firstMatch.waitForExistence(timeout: 8),
            "Coach logt de kuit-blessure niet."
        )
    }

    // MARK: - Test 4: Dashboard & Post-Workout

    @MainActor
    func testDashboardAndPostWorkout() throws {
        app.launch()
        app.tap()

        XCTAssertTrue(waitForDashboard(), "Dashboard begroetingstekst verschijnt niet na app-launch.")

        // Vibe Score (optioneel)
        let vibeCard = app.otherElements["VibeScoreCard"]
        if vibeCard.waitForExistence(timeout: 3) {
            let scoreOrLabel = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS '82' OR label CONTAINS[c] 'Optimaal'")
            ).firstMatch
            app.swipeDown()
            XCTAssertTrue(
                scoreOrLabel.waitForExistence(timeout: 3) || vibeCard.isHittable,
                "Vibe Score kaart aanwezig maar 82/'Optimaal' niet zichtbaar."
            )
        }

        // Doelen tab
        app.tabBars.buttons["Doelen"].tap()
        XCTAssertTrue(waitForGoalsView(), "Doelen-scherm laadt niet.")

        let hasNoGoals = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'GEEN DOELEN'")
        ).firstMatch.waitForExistence(timeout: 2)
        if !hasNoGoals {
            let phaseBadge = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Build' OR label CONTAINS[c] 'Base' OR label CONTAINS[c] 'Peak' OR label CONTAINS[c] 'Taper'")
            ).firstMatch
            if !phaseBadge.waitForExistence(timeout: 3) {
                print("ℹ️ Fase-badge niet gevonden — goal heeft mogelijk nog geen blueprint-fase.")
            }
        }

        // Terug naar Dashboard voor RPE
        app.tabBars.buttons["Overzicht"].tap()
        XCTAssertTrue(waitForDashboard(), "Dashboard laadt niet na tab-wissel.")
        app.swipeDown()

        let rpeCard = app.otherElements["RPECheckinCard"]
        guard rpeCard.waitForExistence(timeout: 2) else { return }

        let rpeSlider = app.sliders["RPESlider"]
        XCTAssertTrue(rpeSlider.exists, "RPESlider ontbreekt in de check-in kaart.")
        rpeSlider.adjust(toNormalizedSliderPosition: 0.7)

        let moodButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'MoodButton'"))
        if moodButtons.count > 0 { moodButtons.firstMatch.tap() } else { rpeCard.buttons.firstMatch.tap() }

        let saveRpeButton = app.buttons["RPEOpslaanButton"]
        XCTAssertTrue(saveRpeButton.exists, "RPEOpslaanButton ontbreekt.")
        XCTAssertTrue(saveRpeButton.isEnabled, "Opslaan-knop niet actief na RPE + stemming.")
        saveRpeButton.tap()

        XCTAssertFalse(rpeCard.waitForExistence(timeout: 3), "RPE Check-in kaart blijft zichtbaar na opslaan.")
    }
}
