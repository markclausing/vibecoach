import XCTest

/// Sprint 19 / Epic 30 V2.0: UI-tests voor de core 'Happy Paths' van VibeCoach.
///
/// V2.0 heeft geen NavigationBars meer op Dashboard, Goals en Coach.
/// Dashboard-aanwezigheid wordt geverifieerd via de begroetingstekst ("Goede..."),
/// Goals via de grote "Doelen" statische tekst, Coach via ChatInputField.
final class AIFitnessCoachUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-isRunningUITests")
        app.launchArguments.append("-UITesting")

        addUIInterruptionMonitor(withDescription: "OS Toestemming Alert") { alert in
            let allowLabels = ["Allow", "Sta toe", "OK", "Allow While Using App",
                               "Allow Once", "Don't Allow", "Niet toestaan"]
            for label in allowLabels {
                if alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            }
            return false
        }

        app.launch()
        app.tap()
    }

    override func tearDownWithError() throws { app = nil }

    // MARK: - Helpers

    /// Wacht op de V2.0 dashboard-begroetingstekst ("Goedemorgen/middag/avond").
    @discardableResult
    private func waitForDashboard(timeout: TimeInterval = 5) -> Bool {
        app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Goede'")
        ).firstMatch.waitForExistence(timeout: timeout)
    }

    // MARK: - TabBar Structuur

    @MainActor
    func testAllTabsArePresent() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "TabBar is niet aanwezig binnen 5 seconden na app-launch.")

        for tabLabel in ["Overzicht", "Doelen", "Coach", "Geheugen", "Instellingen"] {
            XCTAssertTrue(tabBar.buttons[tabLabel].exists, "Tab '\(tabLabel)' ontbreekt in de TabBar.")
        }
    }

    // MARK: - Dashboard Rendering

    /// V2.0: geen NavigationBar meer — check de begroetingstekst van DashboardHeaderView.
    @MainActor
    func testDashboardHeaderIsVisible() throws {
        XCTAssertTrue(
            waitForDashboard(),
            "Begroetingstekst (Goedemorgen/middag/avond) verschijnt niet op het Dashboard binnen 5 seconden."
        )
    }

    @MainActor
    func testVibeScoreCard_IsAccessibleOrFallback() throws {
        XCTAssertTrue(waitForDashboard(), "Dashboard laadt niet — test kan niet verder.")

        let vibeCard = app.otherElements["VibeScoreCard"]
        if vibeCard.waitForExistence(timeout: 3) {
            XCTAssertTrue(vibeCard.isHittable, "VibeScoreCard is aanwezig maar niet hittable.")
        }
    }

    // MARK: - Navigatie naar Coach Tab

    @MainActor
    func testNavigateToCoachTab_ShowsChatInterface() throws {
        let coachTab = app.tabBars.buttons["Coach"]
        XCTAssertTrue(coachTab.waitForExistence(timeout: 5), "Tab 'Coach' niet gevonden in de TabBar.")
        coachTab.tap()

        // SwiftUI's `TextField(..., axis: .vertical)` rendert in iOS 17+ als `.textView`
        // (niet `.textField`) in de XCUI-hiërarchie. We zoeken daarom element-type-
        // agnostisch op de accessibilityIdentifier zodat dit op alle iOS-versies werkt.
        let chatInputField = app.descendants(matching: .any)
            .matching(identifier: "ChatInputField").firstMatch
        XCTAssertTrue(
            chatInputField.waitForExistence(timeout: 8),
            "Coach chat-invoerveld (ChatInputField) verschijnt niet na tikken op de Coach tab."
        )
    }

    // MARK: - Navigatie naar Doelen Tab

    /// V2.0: geen NavigationBar meer — check de grote "Doelen" title-tekst in de header.
    @MainActor
    func testNavigateToGoalsTab_ShowsGoalsView() throws {
        let goalsTab = app.tabBars.buttons["Doelen"]
        XCTAssertTrue(goalsTab.waitForExistence(timeout: 3), "Tab 'Doelen' niet gevonden in de TabBar.")
        goalsTab.tap()

        // "Doelen" als largeTitle Text in GoalsListView header (niet de tab-knop)
        let goalsTitlePredicate = NSPredicate(format: "elementType == 48 AND label == 'Doelen'")
        let goalsTitle = app.descendants(matching: .any).matching(goalsTitlePredicate).firstMatch
        XCTAssertTrue(
            goalsTitle.waitForExistence(timeout: 3),
            "Grote 'Doelen' titel verschijnt niet na tikken op de Doelen tab."
        )
    }

    // MARK: - Navigatie naar Instellingen Tab

    @MainActor
    func testNavigateToSettingsTab_ShowsSettingsView() throws {
        let settingsTab = app.tabBars.buttons["Instellingen"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 3), "Tab 'Instellingen' niet gevonden.")
        settingsTab.tap()

        XCTAssertTrue(
            app.navigationBars.firstMatch.waitForExistence(timeout: 3),
            "NavigationBar in het Instellingen-scherm verschijnt niet."
        )
    }

    // MARK: - RPE Check-in Kaart

    @MainActor
    func testRPECheckinCard_WhenVisible_HasSliderAndSaveButton() throws {
        XCTAssertTrue(waitForDashboard(), "Dashboard laadt niet — test kan niet verder.")

        let checkinCard = app.otherElements["RPECheckinCard"]
        guard checkinCard.waitForExistence(timeout: 2) else { return }

        XCTAssertTrue(app.sliders["RPESlider"].exists, "RPESlider ontbreekt in de check-in kaart.")
        let saveButton = app.buttons["RPEOpslaanButton"]
        XCTAssertTrue(saveButton.exists, "Opslaan-knop (RPEOpslaanButton) ontbreekt.")
        XCTAssertFalse(saveButton.isEnabled, "Opslaan-knop is al enabled zonder stemmingsselectie.")
    }

    @MainActor
    func testRPECheckinCard_WhenVisible_SliderIsInteractable() throws {
        XCTAssertTrue(waitForDashboard(), "Dashboard laadt niet — test kan niet verder.")

        let checkinCard = app.otherElements["RPECheckinCard"]
        guard checkinCard.waitForExistence(timeout: 2) else { return }

        let rpeSlider = app.sliders["RPESlider"]
        guard rpeSlider.exists else { return }
        rpeSlider.adjust(toNormalizedSliderPosition: 0.8)
        XCTAssertTrue(rpeSlider.isEnabled, "RPESlider is niet bedienbaar.")
    }

    // MARK: - Launch Performance

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) { XCUIApplication().launch() }
    }
}
