import XCTest
@testable import AIFitnessCoach

/// Epic #37 story 37.5: locks down the language-preference resolution so the picker,
/// the app-root `.environment(\.locale, …)` and the service-side `AppLanguage.currentLocale`
/// stay in agreement.
final class AppLanguageTests: XCTestCase {

    private let key = AppLanguage.storageKey

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func testCurrent_DefaultsToSystem_WhenUnset() {
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(AppLanguage.current, .system)
    }

    func testCurrent_DefaultsToSystem_OnUnknownRawValue() {
        UserDefaults.standard.set("klingon", forKey: key)
        XCTAssertEqual(AppLanguage.current, .system)
    }

    func testCurrent_ReadsStoredValue() {
        UserDefaults.standard.set(AppLanguage.german.rawValue, forKey: key)
        XCTAssertEqual(AppLanguage.current, .german)
    }

    func testSystem_ResolvesToDeviceLocale() {
        XCTAssertEqual(AppLanguage.system.resolvedLocale.identifier, Locale.current.identifier)
    }

    func testSpecificLanguages_ResolveToFixedLocales() {
        XCTAssertEqual(AppLanguage.dutch.resolvedLocale.identifier, "nl_NL")
        XCTAssertEqual(AppLanguage.english.resolvedLocale.identifier, "en_US")
        XCTAssertEqual(AppLanguage.german.resolvedLocale.identifier, "de_DE")
        XCTAssertEqual(AppLanguage.spanish.resolvedLocale.identifier, "es_ES")
    }

    func testLanguageCode_NilForSystem_CodeForSpecific() {
        XCTAssertNil(AppLanguage.system.languageCode)
        XCTAssertEqual(AppLanguage.dutch.languageCode, "nl")
        XCTAssertEqual(AppLanguage.english.languageCode, "en")
        XCTAssertEqual(AppLanguage.german.languageCode, "de")
        XCTAssertEqual(AppLanguage.spanish.languageCode, "es")
    }

    func testCurrentLocale_FollowsStoredPreference() {
        UserDefaults.standard.set(AppLanguage.spanish.rawValue, forKey: key)
        XCTAssertEqual(AppLanguage.currentLocale.identifier, "es_ES")
    }

    func testEverySelectableCaseHasANonEmptyDisplayName() {
        for language in AppLanguage.selectableCases {
            XCTAssertFalse(language.displayName.isEmpty, "\(language) mist een displayName")
        }
    }

    // MARK: - applyToBundleOverride (story 37.1)

    func testApplyToBundleOverride_SpecificLanguage_SetsAppleLanguages() {
        let defaults = UserDefaults(suiteName: "AppLanguageTests.override")!
        defaults.removeObject(forKey: AppLanguage.appleLanguagesKey)
        AppLanguage.german.applyToBundleOverride(defaults)
        XCTAssertEqual(defaults.stringArray(forKey: AppLanguage.appleLanguagesKey), ["de"])
        defaults.removePersistentDomain(forName: "AppLanguageTests.override")
    }

    func testApplyToBundleOverride_System_ClearsAppleLanguages() {
        let defaults = UserDefaults(suiteName: "AppLanguageTests.override")!
        defaults.set(["de"], forKey: AppLanguage.appleLanguagesKey)
        XCTAssertEqual(defaults.stringArray(forKey: AppLanguage.appleLanguagesKey), ["de"])
        AppLanguage.system.applyToBundleOverride(defaults)
        // `.system` removes the app-level override. Reads then fall back to the global
        // domain (the device language list), so the value is no longer the forced ["de"].
        XCTAssertNotEqual(defaults.stringArray(forKey: AppLanguage.appleLanguagesKey), ["de"])
        defaults.removePersistentDomain(forName: "AppLanguageTests.override")
    }
}
