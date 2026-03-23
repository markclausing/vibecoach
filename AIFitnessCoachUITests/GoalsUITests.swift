import XCTest

final class GoalsUITests: XCTestCase {

    override func setUpWithError() throws {
        // Zorg dat het testen direct stopt bij de eerste fout
        continueAfterFailure = false
    }

    func testCreateNewGoal_Success() throws {
        // 1. Lanceer de app.
        let app = XCUIApplication()
        app.launch()

        // 2. Navigeer naar de 'Doelen' (Goals) tab.
        // We zoeken naar het TabBar icoon met label "Doelen".
        let goalsTab = app.tabBars.buttons["Doelen"]
        if goalsTab.exists {
            goalsTab.tap()
        }

        // 3. Tik op de '+' knop (Toolbar Add-knop)
        let addGoalButton = app.navigationBars.buttons["Add"] // Vaak gemapt als 'Add' bij een plus-icoon
        XCTAssertTrue(addGoalButton.waitForExistence(timeout: 2.0), "De toevoegen-knop (+) is niet zichtbaar op het doelen scherm.")
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
