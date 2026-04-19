import XCTest

/// Sprint 19 / Epic 30 V2.0: UI-tests voor de core 'Happy Paths' van VibeCoach.
///
/// Testprincipes:
/// - Tests stoppen direct bij de eerste fout (continueAfterFailure = false).
/// - V2.0: Dashboard, Goals en Coach hebben geen NavigationBar meer (toolbar hidden).
///   Tests gebruiken stabiele accessibilityIdentifiers in plaats van navigationBars["..."].
/// - Data-afhankelijke elementen (Vibe Score, RPE Check-in) worden alleen getest
///   als ze zichtbaar zijn — een lege testomgeving zonder HealthKit-data is geen fout.
final class AIFitnessCoachUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        // Sprint 19: Signaleer aan de app dat we in UI-test modus draaien.
        app.launchArguments.append("-isRunningUITests")

        // Sprint 26.1: Voeg -UITesting toe zodat UITestMockEnvironment.setup() actief is.
        app.launchArguments.append("-UITesting")

        addUIInterruptionMonitor(withDescription: "OS Toestemming Alert") { alert in
            let allowLabels = ["Allow", "Sta toe", "OK", "Allow While Using App",
                               "Allow Once", "Don't Allow", "Niet toestaan"]
            for label in allowLabels {
                if alert.buttons[label].exists {
                    alert.buttons[label].tap()
                    return true
                }
            }
            return false
        }

        app.launch()
        app.tap()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - TabBar Structuur

    /// Alle vijf TabBar-tabs moeten aanwezig zijn direct na app-launch.
    @MainActor
    func testAllTabsArePresent() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(
            tabBar.waitForExistence(timeout: 5),
            "TabBar is niet aanwezig binnen 5 seconden na app-launch."
        )

        let expectedTabs = ["Overzicht", "Doelen", "Coach", "Geheugen", "Instellingen"]
        for tabLabel in expectedTabs {
            XCTAssertTrue(
                tabBar.buttons[tabLabel].exists,
                "Tab '\(tabLabel)' ontbreekt in de TabBar."
            )
        }
    }

    // MARK: - Dashboard Rendering

    /// Het Dashboard (Overzicht tab) moet de V2.0 contextuele header tonen na launch.
    /// De V2.0 DashboardHeaderView heeft een accessibilityIdentifier "DashboardHeaderView".
    @MainActor
    func testDashboardHeaderIsVisible() throws {
        let dashboardHeader = app.otherElements["DashboardHeaderView"]
        XCTAssertTrue(
            dashboardHeader.waitForExistence(timeout: 5),
            "DashboardHeaderView verschijnt niet op het Dashboard binnen 5 seconden."
        )
    }

    /// De Vibe Score Card moet aanwezig en interactief zijn als er HealthKit-data beschikbaar is.
    @MainActor
    func testVibeScoreCard_IsAccessibleOrFallback() throws {
        XCTAssertTrue(
            app.otherElements["DashboardHeaderView"].waitForExistence(timeout: 5),
            "Dashboard laadt niet — test kan niet verder."
        )

        let vibeCard = app.otherElements["VibeScoreCard"]
        if vibeCard.waitForExistence(timeout: 3) {
            XCTAssertTrue(
                vibeCard.isHittable,
                "VibeScoreCard is aanwezig maar niet hittable (mogelijk geblokkeerd door een overlay)."
            )
        }
        // Geen data aanwezig = acceptabel voor testomgeving
    }

    // MARK: - Navigatie naar Coach Tab

    /// Tikken op de Coach-tab moet de V2.0 coach-header én het invoerveld tonen.
    @MainActor
    func testNavigateToCoachTab_ShowsChatInterface() throws {
        let coachTab = app.tabBars.buttons["Coach"]
        XCTAssertTrue(coachTab.waitForExistence(timeout: 3), "Tab 'Coach' niet gevonden in de TabBar.")
        coachTab.tap()

        // V2.0: CoachV2HeaderView heeft identifier "CoachView"
        let coachHeader = app.otherElements["CoachView"]
        XCTAssertTrue(
            coachHeader.waitForExistence(timeout: 5),
            "CoachView header (CoachView) verschijnt niet na tikken op de Coach tab."
        )

        let chatInputField = app.textFields["ChatInputField"]
        XCTAssertTrue(
            chatInputField.waitForExistence(timeout: 5),
            "Coach chat-invoerveld (ChatInputField) verschijnt niet na tikken op de Coach tab."
        )
    }

    // MARK: - Navigatie naar Doelen Tab

    /// Tikken op de Doelen-tab moet de V2.0 GoalsListView tonen.
    /// V2.0 heeft geen NavigationBar meer — check de "Doelen" grote titel in de header.
    @MainActor
    func testNavigateToGoalsTab_ShowsGoalsView() throws {
        let goalsTab = app.tabBars.buttons["Doelen"]
        XCTAssertTrue(goalsTab.waitForExistence(timeout: 3), "Tab 'Doelen' niet gevonden in de TabBar.")
        goalsTab.tap()

        // V2.0: GoalsListView heeft identifier "GoalsScrollView"
        let goalsScrollView = app.scrollViews["GoalsScrollView"]
        XCTAssertTrue(
            goalsScrollView.waitForExistence(timeout: 3),
            "GoalsScrollView verschijnt niet na tikken op de Doelen tab."
        )
    }

    // MARK: - Navigatie naar Instellingen Tab

    /// De Instellingen-tab heeft nog wel een NavigationBar.
    @MainActor
    func testNavigateToSettingsTab_ShowsSettingsView() throws {
        let settingsTab = app.tabBars.buttons["Instellingen"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 3), "Tab 'Instellingen' niet gevonden in de TabBar.")
        settingsTab.tap()

        XCTAssertTrue(
            app.navigationBars.firstMatch.waitForExistence(timeout: 3),
            "NavigationBar in het Instellingen-scherm verschijnt niet."
        )
    }

    // MARK: - RPE Check-in Kaart

    @MainActor
    func testRPECheckinCard_WhenVisible_HasSliderAndSaveButton() throws {
        XCTAssertTrue(
            app.otherElements["DashboardHeaderView"].waitForExistence(timeout: 5),
            "Dashboard laadt niet — test kan niet verder."
        )

        let checkinCard = app.otherElements["RPECheckinCard"]
        guard checkinCard.waitForExistence(timeout: 2) else { return }

        let rpeSlider = app.sliders["RPESlider"]
        XCTAssertTrue(rpeSlider.exists, "RPESlider ontbreekt in de check-in kaart terwijl de kaart wel zichtbaar is.")

        let saveButton = app.buttons["RPEOpslaanButton"]
        XCTAssertTrue(saveButton.exists, "Opslaan-knop (RPEOpslaanButton) ontbreekt in de check-in kaart.")

        XCTAssertFalse(
            saveButton.isEnabled,
            "Opslaan-knop is al enabled zonder dat er een stemming is geselecteerd."
        )
    }

    @MainActor
    func testRPECheckinCard_WhenVisible_SliderIsInteractable() throws {
        XCTAssertTrue(
            app.otherElements["DashboardHeaderView"].waitForExistence(timeout: 5),
            "Dashboard laadt niet — test kan niet verder."
        )

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
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
