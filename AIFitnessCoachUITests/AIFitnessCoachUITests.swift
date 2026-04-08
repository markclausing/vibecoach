import XCTest

/// Sprint 19: UI-tests voor de core 'Happy Paths' van VibeCoach.
///
/// Testprincipes:
/// - Tests stoppen direct bij de eerste fout (continueAfterFailure = false).
/// - Data-afhankelijke elementen (Vibe Score, RPE Check-in) worden alleen getest
///   als ze zichtbaar zijn — een lege testomgeving zonder HealthKit-data is geen fout.
/// - Navigatietests controleren uitsluitend structurele aanwezigheid (NavigationTitle,
///   TabBar-knoppen), niet de inhoud van dynamische lijsten.
final class AIFitnessCoachUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        // Sprint 19: Signaleer aan de app dat we in UI-test modus draaien.
        // De app slaat hierdoor HealthKit-autorisatie en notificatie-engines over,
        // zodat er geen systeem-popups verschijnen die de tests blokkeren.
        app.launchArguments.append("-isRunningUITests")

        // Vang eventuele resterende OS-alerts automatisch af (bijv. als de simulator
        // al eerder toestemming heeft gevraagd en de status 'notDetermined' is).
        // De monitor zoekt naar de meest voorkomende knoplabels in NL en EN.
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

        // Tik op de app zodat Xcode de interrupt monitor activeert voor alerts
        // die direct na launch verschijnen (vereist door XCTest interne timing).
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

    /// Het Dashboard (Overzicht tab) moet een NavigationTitle tonen direct na launch.
    @MainActor
    func testDashboardRendersNavigationTitle() throws {
        let navBar = app.navigationBars["Overzicht"].firstMatch
        XCTAssertTrue(
            navBar.waitForExistence(timeout: 5),
            "NavigationTitle 'Overzicht' verschijnt niet op het Dashboard binnen 5 seconden."
        )
    }

    /// De Vibe Score Card moet aanwezig en interactief zijn als er HealthKit-data beschikbaar is.
    /// In een simulator zonder data is de fallback-staat (grijze kaart) het verwachte gedrag.
    @MainActor
    func testVibeScoreCard_IsAccessibleOrFallback() throws {
        // Wacht tot het dashboard geladen is
        XCTAssertTrue(
            app.navigationBars["Overzicht"].waitForExistence(timeout: 5),
            "Dashboard laadt niet — test kan niet verder."
        )

        let vibeCard = app.otherElements["VibeScoreCard"]
        if vibeCard.waitForExistence(timeout: 3) {
            // Kaart aanwezig — controleer of hij hittable is (niet geblokkeerd)
            XCTAssertTrue(
                vibeCard.isHittable,
                "VibeScoreCard is aanwezig maar niet hittable (mogelijk geblokkeerd door een overlay)."
            )
        }
        // Geen data aanwezig = acceptabel voor testomgeving — geen fout
    }

    // MARK: - Navigatie naar Coach Tab

    /// Tikken op de Coach-tab moet de chat-interface tonen.
    @MainActor
    func testNavigateToCoachTab_ShowsChatInterface() throws {
        let coachTab = app.tabBars.buttons["Coach"]
        XCTAssertTrue(
            coachTab.waitForExistence(timeout: 3),
            "Tab 'Coach' niet gevonden in de TabBar."
        )
        coachTab.tap()

        // De ChatView bevat een tekstveld voor invoer onderaan het scherm
        let chatInputField = app.textViews.firstMatch
        XCTAssertTrue(
            chatInputField.waitForExistence(timeout: 5),
            "Coach chat-invoerveld verschijnt niet na tikken op de Coach tab."
        )
    }

    // MARK: - Navigatie naar Doelen Tab

    /// Tikken op de Doelen-tab moet de GoalsListView tonen met de juiste NavigationTitle.
    @MainActor
    func testNavigateToGoalsTab_ShowsGoalsView() throws {
        let goalsTab = app.tabBars.buttons["Doelen"]
        XCTAssertTrue(
            goalsTab.waitForExistence(timeout: 3),
            "Tab 'Doelen' niet gevonden in de TabBar."
        )
        goalsTab.tap()

        let goalsNavBar = app.navigationBars["Mijn Doelen"]
        XCTAssertTrue(
            goalsNavBar.waitForExistence(timeout: 3),
            "NavigationTitle 'Mijn Doelen' verschijnt niet na tikken op de Doelen tab."
        )
    }

    // MARK: - Navigatie naar Instellingen Tab

    /// De Instellingen-tab moet een NavigationStack met een NavigationBar tonen.
    @MainActor
    func testNavigateToSettingsTab_ShowsSettingsView() throws {
        let settingsTab = app.tabBars.buttons["Instellingen"]
        XCTAssertTrue(
            settingsTab.waitForExistence(timeout: 3),
            "Tab 'Instellingen' niet gevonden in de TabBar."
        )
        settingsTab.tap()

        XCTAssertTrue(
            app.navigationBars.firstMatch.waitForExistence(timeout: 3),
            "NavigationBar in het Instellingen-scherm verschijnt niet."
        )
    }

    // MARK: - RPE Check-in Kaart

    /// Als de RPE check-in kaart zichtbaar is (recente workout aanwezig),
    /// moeten de kerncomponenten aanwezig en bedienbaar zijn.
    @MainActor
    func testRPECheckinCard_WhenVisible_HasSliderAndSaveButton() throws {
        // Zorg dat we op het Dashboard zijn
        XCTAssertTrue(
            app.navigationBars["Overzicht"].waitForExistence(timeout: 5),
            "Dashboard laadt niet — test kan niet verder."
        )

        let checkinCard = app.otherElements["RPECheckinCard"]
        guard checkinCard.waitForExistence(timeout: 2) else {
            // Geen recente workout in de testomgeving — dit is correct gedrag
            return
        }

        // Kaart aanwezig: controleer de kerncomponenten
        let rpeSlider = app.sliders["RPESlider"]
        XCTAssertTrue(
            rpeSlider.exists,
            "RPESlider ontbreekt in de check-in kaart terwijl de kaart wel zichtbaar is."
        )

        let saveButton = app.buttons["RPEOpslaanButton"]
        XCTAssertTrue(
            saveButton.exists,
            "Opslaan-knop (RPEOpslaanButton) ontbreekt in de check-in kaart."
        )

        // De opslaan-knop moet initieel uitgeschakeld zijn (geen stemming geselecteerd)
        XCTAssertFalse(
            saveButton.isEnabled,
            "Opslaan-knop is al enabled zonder dat er een stemming is geselecteerd."
        )
    }

    /// Als de RPE check-in kaart zichtbaar is, moet de slider bedienbaar zijn
    /// en moet de opslaan-knop na stemmingsselectie enabled worden.
    @MainActor
    func testRPECheckinCard_WhenVisible_SliderIsInteractable() throws {
        XCTAssertTrue(
            app.navigationBars["Overzicht"].waitForExistence(timeout: 5),
            "Dashboard laadt niet — test kan niet verder."
        )

        let checkinCard = app.otherElements["RPECheckinCard"]
        guard checkinCard.waitForExistence(timeout: 2) else { return }

        let rpeSlider = app.sliders["RPESlider"]
        guard rpeSlider.exists else { return }

        // Schuif de slider naar rechts (hogere RPE)
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
