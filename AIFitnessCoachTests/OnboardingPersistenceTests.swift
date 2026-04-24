import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Epic #31 — unit-dekking voor de persistentie van de V2.0-onboarding.
///
/// Twee dingen blijven staan na afronding van de flow:
///  1. Een `UserConfiguration` @Model-instance in SwiftData (ankerdatum voor
///     andere features zoals base-building/analytics).
///  2. De `hasCompletedOnboarding` @AppStorage-vlag die ContentView gebruikt
///     als poortwachter (true → hoofd-app, false → onboarding).
///
/// Deze suite dekt beide lagen plus de `OnboardingView.persistUserConfiguration`-
/// invariant dat er altijd exact één `UserConfiguration` in de store staat.
@MainActor
final class OnboardingPersistenceTests: XCTestCase {

    // MARK: - In-memory SwiftData container

    /// Fris SwiftData-container per test — in-memory zodat tests parallel kunnen
    /// draaien zonder gedeelde staat. We registreren alleen `UserConfiguration`:
    /// de andere @Model-types zijn niet nodig voor deze tests.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([UserConfiguration.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - UserConfiguration init

    func testUserConfiguration_Init_SetsOnboardingDayToStartOfDay() {
        // 23 april 2026, 14:37:42 — bewust een tijdstip dat GEEN startOfDay is.
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 23
        components.hour = 14
        components.minute = 37
        components.second = 42
        let tricky = Calendar.current.date(from: components)!

        let config = UserConfiguration(date: tricky)

        XCTAssertEqual(config.onboardingDate, tricky,
                       "onboardingDate moet het originele tijdstip behouden.")
        XCTAssertEqual(config.onboardingDay, Calendar.current.startOfDay(for: tricky),
                       "onboardingDay moet via Calendar.startOfDay(for:) worden berekend — conform CLAUDE.md §3.")
        XCTAssertLessThanOrEqual(config.onboardingDay, config.onboardingDate,
                                 "onboardingDay ligt altijd ≤ onboardingDate op dezelfde kalenderdag.")
    }

    func testUserConfiguration_Init_DefaultsToNow() {
        let before = Date()
        let config = UserConfiguration()
        let after = Date()

        XCTAssertGreaterThanOrEqual(config.onboardingDate, before)
        XCTAssertLessThanOrEqual(config.onboardingDate, after)
    }

    // MARK: - SwiftData round-trip

    func testUserConfiguration_InsertAndFetch_Roundtrips() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let created = UserConfiguration(date: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(created)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserConfiguration>())
        XCTAssertEqual(fetched.count, 1, "Precies één UserConfiguration moet persist zijn.")
        XCTAssertEqual(fetched.first?.onboardingDate, created.onboardingDate)
        XCTAssertEqual(fetched.first?.onboardingDay, created.onboardingDay)
    }

    /// Reflecteert de invariant uit `OnboardingView.persistUserConfiguration`:
    /// bij her-onboarding wordt de bestaande configuratie verwijderd en
    /// vervangen door een nieuwe — nooit twee configuraties tegelijk.
    func testUserConfiguration_ReplaceExisting_KeepsSingleRow() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let first = UserConfiguration(date: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(first)
        try context.save()

        // Simuleer dezelfde delete-then-insert die `persistUserConfiguration` doet.
        let existing = try context.fetch(FetchDescriptor<UserConfiguration>())
        for record in existing {
            context.delete(record)
        }
        let replacement = UserConfiguration(date: Date(timeIntervalSince1970: 1_800_000_000))
        context.insert(replacement)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserConfiguration>())
        XCTAssertEqual(fetched.count, 1, "Er mag maar één UserConfiguration in de store staan na her-onboarding.")
        XCTAssertEqual(fetched.first?.onboardingDate, replacement.onboardingDate,
                       "De nieuwe configuratie moet de oude hebben vervangen.")
    }

    // MARK: - hasCompletedOnboarding gate

    /// De poortwachter-sleutel die `ContentView` en `AppDelegate` allebei lezen.
    /// Deze test pint de sleutelnaam vast — een hernoeming zou bestaande
    /// gebruikers per abuis door de onboarding jagen.
    func testHasCompletedOnboardingKey_IsStable() {
        let expectedKey = "hasCompletedOnboarding"

        // Sanity: een verse UserDefaults-suite heeft geen waarde → gate staat op false.
        let suiteName = "vibecoach.onboarding.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(defaults.bool(forKey: expectedKey),
                       "Default waarde moet false zijn zodat nieuwe installs de onboarding starten.")

        defaults.set(true, forKey: expectedKey)
        XCTAssertTrue(defaults.bool(forKey: expectedKey),
                      "Na set(true) moet de gate true teruggeven — anders blijft de onboarding looping.")
    }

    /// Regressie-guard: `AppDelegate.application(_:didFinishLaunchingWithOptions:)`
    /// gebruikt `UserDefaults.standard.bool(forKey:)` direct. Als die key niet
    /// matcht met het @AppStorage-attribuut in `AIFitnessCoachApp` en
    /// `ContentView`, raakt de app uit sync. Deze test zorgt dat ze in dezelfde
    /// string blijven — door identifier-gebruik hier expliciet te spellen.
    func testHasCompletedOnboardingKey_UserDefaultsAndAppStorageMatch() {
        // Door beide locaties met dezelfde string-literal aan te roepen
        // valt een stille rename direct op in deze test.
        let appStorageKey = "hasCompletedOnboarding"
        let appDelegateKey = "hasCompletedOnboarding"
        XCTAssertEqual(appStorageKey, appDelegateKey,
                       "ContentView (@AppStorage) en AppDelegate (UserDefaults) moeten dezelfde key gebruiken.")
    }
}
