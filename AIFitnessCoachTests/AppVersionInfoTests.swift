import XCTest
@testable import AIFitnessCoach

/// Epic #51-H2: borgt de Settings-footer-string. Het Info.plist-pad blijft
/// de waarheidsbron — als een toekomstige refactor de keys hernoemt of de
/// formatter-string aanpast, faalt hier minstens één test.
final class AppVersionInfoTests: XCTestCase {

    func testReturnsFullStringWithAllKeysPresent() {
        let bundle = StubBundle(values: [
            "CFBundleDisplayName": "VibeCoach",
            "CFBundleShortVersionString": "2.0.0",
            "CFBundleVersion": "627"
        ])
        XCTAssertEqual(AppVersionInfo.displayString(in: bundle), "VibeCoach 2.0.0 (build 627)")
    }

    func testFallsBackToCFBundleNameWhenDisplayNameMissing() {
        let bundle = StubBundle(values: [
            "CFBundleName": "VibeCoach",
            "CFBundleShortVersionString": "2.0.0",
            "CFBundleVersion": "627"
        ])
        XCTAssertEqual(AppVersionInfo.displayString(in: bundle), "VibeCoach 2.0.0 (build 627)")
    }

    func testOmitsBuildWhenMissing() {
        let bundle = StubBundle(values: [
            "CFBundleDisplayName": "VibeCoach",
            "CFBundleShortVersionString": "2.0.0"
        ])
        XCTAssertEqual(AppVersionInfo.displayString(in: bundle), "VibeCoach 2.0.0")
    }

    func testOmitsVersionWhenMissing() {
        let bundle = StubBundle(values: [
            "CFBundleDisplayName": "VibeCoach",
            "CFBundleVersion": "627"
        ])
        XCTAssertEqual(AppVersionInfo.displayString(in: bundle), "VibeCoach (build 627)")
    }

    /// Bij een volledig kapotte Info.plist (zou nooit horen) tonen we minstens
    /// een schone app-naam — geen "VibeCoach (build )"-formatting-glitch.
    func testReturnsBareNameWhenAllKeysMissing() {
        let bundle = StubBundle(values: [:])
        XCTAssertEqual(AppVersionInfo.displayString(in: bundle), "VibeCoach")
    }

    /// Live `Bundle.main` mag nooit een lege string opleveren. Sanity-check op
    /// de productie-flow zonder fixture-mocking.
    func testProductionDisplayStringIsNonEmpty() {
        XCTAssertFalse(AppVersionInfo.displayString.isEmpty)
    }
}

/// Sub-class van `Bundle` die alleen de geïnjecteerde Info-keys teruggeeft.
/// Volstaat omdat `AppVersionInfo` enkel `object(forInfoDictionaryKey:)` raakt.
private final class StubBundle: Bundle {
    private let values: [String: String]

    init(values: [String: String]) {
        self.values = values
        super.init()
    }

    override func object(forInfoDictionaryKey key: String) -> Any? {
        values[key]
    }
}
