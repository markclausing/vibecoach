import XCTest

final class GoalsUITests: XCTestCase {

    override func setUpWithError() throws {
        // Zorg dat het testen direct stopt bij de eerste fout
        continueAfterFailure = false
    }

    func testCreateNewGoal_Success() throws {
        // 1. Lanceer de app.
        let app = XCUIApplication()
        app.launchArguments.append("-isRunningUITests")
        // Sprint 26.1: -UITesting activeert UITestMockEnvironment (hasSeenOnboarding = true).
        app.launchArguments.append("-UITesting")
        app.launch()

        // 2. Navigeer naar de 'Doelen' tab — wacht tot de TabBar geladen is.
        let goalsTab = app.tabBars.buttons["Doelen"]
        XCTAssertTrue(goalsTab.waitForExistence(timeout: 5), "Tab 'Doelen' niet gevonden in de TabBar.")
        goalsTab.tap()

        // 3. Wacht op de NavigationTitle om zeker te zijn dat de view geladen is,
        //    en zoek dan de + knop via de expliciete accessibilityIdentifier.
        XCTAssertTrue(app.navigationBars["Doelen"].waitForExistence(timeout: 3), "'Doelen' laadt niet.")
        let addGoalButton = app.buttons["AddGoalButton"]
        XCTAssertTrue(addGoalButton.waitForExistence(timeout: 3), "De toevoegen-knop (AddGoalButton) is niet zichtbaar op het doelen scherm.")
        addGoalButton.tap()

        // Wacht tot de AddGoalView present is (bijv. op basis van de navigatie-titel)
        XCTAssertTrue(app.navigationBars["Nieuw Doel"].waitForExistence(timeout: 2.0), "Het formulier 'Nieuw Doel' opent niet.")

        // 4. Vul het test-doel in
        let titleTextField = app.textFields["Titel (bijv. Marathon onder 3:30)"]
        XCTAssertTrue(titleTextField.exists, "Titel TextField werd niet gevonden in het formulier.")
        
        titleTextField.tap()
        titleTextField.typeText("UI Test Marathon")

        // 5. Tik op 'Opslaan'
        let saveButton = app.navigationBars["Nieuw Doel"].buttons["Opslaan"]
        XCTAssertTrue(saveButton.exists, "Opslaan knop bestaat niet of is niet bereikbaar.")
        saveButton.tap()

        // 6. Verifieer: Wacht tot de lijst wordt vernieuwd en zoek naar de ingevoerde tekst
        let newGoalCell = app.staticTexts["UI Test Marathon"]
        
        XCTAssertTrue(newGoalCell.waitForExistence(timeout: 3.0), "Het nieuwe doel 'UI Test Marathon' verschijnt na het opslaan niet in de lijst! Mogelijk vergeten op te slaan (persist) of de query update niet goed.")
    }
}
