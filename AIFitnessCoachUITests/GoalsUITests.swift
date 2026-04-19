import XCTest

/// V2.0: UI-test voor doel aanmaken via de GoalsListView.
/// V2.0 heeft geen NavigationBar meer — check via GoalsScrollView identifier.
final class GoalsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCreateNewGoal_Success() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-isRunningUITests")
        app.launchArguments.append("-UITesting")
        app.launch()

        // Navigeer naar de 'Doelen' tab
        let goalsTab = app.tabBars.buttons["Doelen"]
        XCTAssertTrue(goalsTab.waitForExistence(timeout: 5), "Tab 'Doelen' niet gevonden in de TabBar.")
        goalsTab.tap()

        // V2.0: GoalsListView heeft geen NavigationBar meer — check via GoalsScrollView
        XCTAssertTrue(
            app.scrollViews["GoalsScrollView"].waitForExistence(timeout: 3),
            "GoalsScrollView laadt niet na tikken op de Doelen tab."
        )

        let addGoalButton = app.buttons["AddGoalButton"]
        XCTAssertTrue(
            addGoalButton.waitForExistence(timeout: 3),
            "De toevoegen-knop (AddGoalButton) is niet zichtbaar op het doelen scherm."
        )
        addGoalButton.tap()

        // AddGoalView is een sheet met een NavigationBar
        XCTAssertTrue(
            app.navigationBars["Nieuw Doel"].waitForExistence(timeout: 2.0),
            "Het formulier 'Nieuw Doel' opent niet."
        )

        // Vul het titel-veld in
        let titleTextField = app.textFields["Titel (bijv. Marathon onder 3:30)"]
        XCTAssertTrue(titleTextField.exists, "Titel TextField werd niet gevonden in het formulier.")
        titleTextField.tap()
        titleTextField.typeText("UI Test Marathon")

        let saveButton = app.navigationBars["Nieuw Doel"].buttons["Opslaan"]
        XCTAssertTrue(saveButton.exists, "Opslaan knop bestaat niet of is niet bereikbaar.")
        saveButton.tap()

        // Het nieuwe doel moet zichtbaar zijn als kaart-titel
        let newGoalText = app.staticTexts["UI Test Marathon"]
        XCTAssertTrue(
            newGoalText.waitForExistence(timeout: 5),
            "Het nieuwe doel 'UI Test Marathon' verschijnt na het opslaan niet in de lijst."
        )
    }
}
