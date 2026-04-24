import XCTest

/// Epic #35 — E2E tests voor de dual-picker in "AI Coach Configuratie".
///
/// De `SettingsView`-ScrollView gebruikt custom `SettingsRowV2`-cells die
/// onder XCUITest niet betrouwbaar als tappable button worden aangeboden;
/// de navigatie-flow is architectonisch lastig te driven. Daarom gebruiken
/// deze tests een DEBUG-only launch-argument `-UITestOpenAICoachConfig` dat
/// `AIProviderSettingsView` als rootview rendert. Zo valideren we de
/// daadwerkelijke picker-UI zonder door de navigatie-keten te hoeven.
final class AIModelPickerUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-isRunningUITests",
            "-UITesting",
            "-UITestOpenAICoachConfig", // Epic #35: direct naar AIProviderSettingsView
        ]

        addUIInterruptionMonitor(withDescription: "OS Toestemming Alert") { alert in
            let allowLabels = [
                "Allow", "Sta toe", "OK", "Allow While Using App",
                "Allow Once", "Don't Allow", "Niet toestaan",
                "Sta toe bij gebruik van app",
            ]
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

    /// Wacht tot de pickers geladen zijn. `hasAttemptedInitialLoad` flipt
    /// naar `true` zodra de Worker-fetch klaar is (live response of fallback),
    /// waarna `PrimaryGeminiModelPicker` in de hiërarchie verschijnt.
    @discardableResult
    private func waitForPickers(timeout: TimeInterval = 10) -> Bool {
        let primary = app.descendants(matching: .any)["PrimaryGeminiModelPicker"]
        return primary.waitForExistence(timeout: timeout)
    }

    // MARK: - Tests

    /// Happy path: de pickers renderen na de initiële catalogus-load.
    /// Dekt de hoofdfunctie die een gebruiker gebruikt om een ander Gemini-
    /// model te kiezen.
    @MainActor
    func testBothModelPickersAreVisibleAfterInitialLoad() throws {
        XCTAssertTrue(
            app.navigationBars["AI Coach Configuratie"].waitForExistence(timeout: 5),
            "Launch-arg -UITestOpenAICoachConfig rendert AIProviderSettingsView niet."
        )

        XCTAssertTrue(
            waitForPickers(),
            "PrimaryGeminiModelPicker verschijnt niet binnen 10s — loader blijft hangen of pickers renderen niet."
        )

        let primary = app.descendants(matching: .any)["PrimaryGeminiModelPicker"]
        let fallback = app.descendants(matching: .any)["FallbackGeminiModelPicker"]
        XCTAssertTrue(primary.exists, "PrimaryGeminiModelPicker ontbreekt.")
        XCTAssertTrue(fallback.exists, "FallbackGeminiModelPicker ontbreekt.")
    }

    /// Verifieert dat de primaire picker standaard `gemini-flash-latest`
    /// selecteert — zowel in de live-catalogus als in de `builtInFallback`.
    @MainActor
    func testPrimaryPicker_ShowsGeminiFlashLatestByDefault() throws {
        XCTAssertTrue(waitForPickers(), "Pickers verschijnen niet na initiële load.")

        let primary = app.descendants(matching: .any)["PrimaryGeminiModelPicker"]
        let label = primary.label
        let matches = label.contains("gemini-flash-latest")
            || label.contains("Gemini Flash")
            || app.staticTexts["Gemini Flash (latest)"].exists
            || app.staticTexts["gemini-flash-latest"].exists

        XCTAssertTrue(
            matches,
            "Primaire picker toont niet de verwachte default 'gemini-flash-latest'. Label was: \(label)"
        )
    }

    /// Verifieert dat óf de loader-placeholder óf de pickers verschijnen —
    /// nooit beide afwezig. Bewaakt de `hasAttemptedInitialLoad` gate-logica.
    @MainActor
    func testLoaderOrPickersAreShown_NeverBothMissing() throws {
        let loader = app.descendants(matching: .any)["GeminiModelsLoading"]
        let primary = app.descendants(matching: .any)["PrimaryGeminiModelPicker"]

        let deadline = Date().addingTimeInterval(10)
        var everSaw = false
        while Date() < deadline {
            if loader.exists || primary.exists { everSaw = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(
            everSaw,
            "Noch de GeminiModelsLoading-placeholder noch de PrimaryGeminiModelPicker verscheen binnen 10s."
        )
    }
}
