import XCTest

final class GoalsUITests: XCTestCase {

    override func setUpWithError() throws {
        // Stop on first failure
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testCreateNewGoal_Success() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // 1. Navigeer naar de 'Doelen' (Goals) tab.
        // Zorg ervoor dat de TabBar item de tekst "Doelen" (of vergelijkbaar, afhankelijk van ContentView) heeft.
        // We zoeken naar de knop in de TabBar.
        let goalsTab = app.tabBars.buttons["Doelen"]
        if goalsTab.exists {
            goalsTab.tap()
        }

        // 2. Tik op de '+' knop in de navigatiebalk om het formulier te openen.
        // De navigation bar bevat waarschijnlijk de "Add" knop (systemImage: "plus").
        let addGoalButton = app.navigationBars.buttons["Add"] // Of app.navigationBars.buttons.firstMatch
        XCTAssertTrue(addGoalButton.waitForExistence(timeout: 2.0), "De toevoegen-knop (+) moet zichtbaar zijn op het doelen scherm.")
        addGoalButton.tap()

        // Wacht tot de AddGoalView present is (door te checken op de formuliervelden of de titel).
        XCTAssertTrue(app.navigationBars["Nieuw Doel"].waitForExistence(timeout: 2.0), "Het Nieuw Doel formulier moet openen.")

        // 3. Vul een test-doel in
        let titleTextField = app.textFields["Titel (bijv. Marathon onder 3:30)"]
        XCTAssertTrue(titleTextField.exists, "Titel veld moet bestaan.")

        titleTextField.tap()
        titleTextField.typeText("UI Test Marathon")

        // (Optioneel: vul extra notities of sport type in)
        // let detailsField = app.textViews["Extra notities (optioneel)"]
        // ...

        // 4. Tik op 'Opslaan'
        let saveButton = app.navigationBars["Nieuw Doel"].buttons["Opslaan"]
        XCTAssertTrue(saveButton.exists, "Opslaan knop moet bestaan.")
        saveButton.tap()

        // 5. Verifieer dat de tekst 'UI Test Marathon' in de lijst staat.
        // De app navigeert automatisch terug naar GoalsListView. We wachten even tot de reload klaar is.
        let newGoalCell = app.staticTexts["UI Test Marathon"]

        XCTAssertTrue(newGoalCell.waitForExistence(timeout: 3.0), "Het nieuwe doel 'UI Test Marathon' moet in de lijst op het hoofdscherm verschijnen nadat het is opgeslagen.")
    }
}
