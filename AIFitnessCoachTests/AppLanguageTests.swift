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
}
