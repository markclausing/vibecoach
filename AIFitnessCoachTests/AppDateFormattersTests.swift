import XCTest
@testable import AIFitnessCoach

/// `AppDateFormatters` — the centralised, cached `DateFormatter` factory
/// (chore/date-formatter-helper). Guards:
///  • the three locale intents: `display` = current app language, `prompt` = nl_NL, `fixed` = POSIX
///  • the `utc:` flag anchors fixed parsers to UTC
///  • the cache keys display formatters on the active locale, so a language switch yields a
///    correctly re-localised formatter (the whole reason the cache is locale-keyed)
///  • identical requests reuse one instance (the performance win)
final class AppDateFormattersTests: XCTestCase {

    private let langKey = AppLanguage.storageKey
    private var savedLang: String?

    override func setUp() {
        super.setUp()
        savedLang = UserDefaults.standard.string(forKey: langKey)
    }

    override func tearDown() {
        if let savedLang {
            UserDefaults.standard.set(savedLang, forKey: langKey)
        } else {
            UserDefaults.standard.removeObject(forKey: langKey)
        }
        super.tearDown()
    }

    // A fixed reference date (2026-07-01, a Wednesday) for language-dependent assertions.
    private let refDate: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 1
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    // MARK: - Locale intents

    func testFixed_UsesPosixLocale() {
        let f = AppDateFormatters.fixed("yyyy-MM-dd")
        XCTAssertEqual(f.locale.identifier, "en_US_POSIX")
        XCTAssertEqual(f.dateFormat, "yyyy-MM-dd")
    }

    func testFixed_UTCFlag_SetsZeroOffsetTimeZone() {
        // "UTC" may normalise to the equivalent "GMT" on some OS versions; assert the
        // invariant that matters — a zero offset from GMT — rather than the identifier string.
        let utc = AppDateFormatters.fixed("yyyy-MM-dd'T'HH:mm", utc: true)
        XCTAssertEqual(utc.timeZone.secondsFromGMT(), 0)
    }

    func testPrompt_StaysDutch_RegardlessOfAppLanguage() {
        // Prompt terms stay Dutch (CLAUDE.md §13), even when the UI language is English.
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: langKey)
        XCTAssertEqual(AppDateFormatters.prompt("EEEE d MMM").locale.identifier, "nl_NL")
        XCTAssertEqual(AppDateFormatters.promptStyle(.medium).locale.identifier, "nl_NL")
    }

    // MARK: - Display follows the app language

    func testDisplay_FollowsSelectedLanguage() {
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: langKey)
        XCTAssertEqual(AppDateFormatters.display("d MMM").locale.identifier, "en_US")

        UserDefaults.standard.set(AppLanguage.german.rawValue, forKey: langKey)
        XCTAssertEqual(AppDateFormatters.display("d MMM").locale.identifier, "de_DE")
    }

    func testDisplay_RebuildsAfterLanguageSwitch() {
        UserDefaults.standard.set(AppLanguage.dutch.rawValue, forKey: langKey)
        let nl = AppDateFormatters.display("EEEE").string(from: refDate)

        UserDefaults.standard.set(AppLanguage.spanish.rawValue, forKey: langKey)
        let es = AppDateFormatters.display("EEEE").string(from: refDate)

        // "woensdag" vs "miércoles" — a stale cached locale would return the Dutch value twice.
        XCTAssertNotEqual(nl.lowercased(), es.lowercased())
    }

    // MARK: - Caching

    func testCache_ReturnsSameInstanceForSameKey() {
        let a = AppDateFormatters.fixed("yyyy-MM-dd")
        let b = AppDateFormatters.fixed("yyyy-MM-dd")
        XCTAssertTrue(a === b, "identical requests should reuse one cached formatter")
    }

    func testCache_DistinctInstancePerLocale() {
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: langKey)
        let en = AppDateFormatters.display("d MMM")
        UserDefaults.standard.set(AppLanguage.german.rawValue, forKey: langKey)
        let de = AppDateFormatters.display("d MMM")
        XCTAssertFalse(en === de, "different locales must not share one formatter instance")
    }
}
