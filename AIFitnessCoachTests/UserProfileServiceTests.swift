import XCTest
import HealthKit
@testable import AIFitnessCoach

/// Unit tests voor UserProfileService (Epic 27).
///
/// Dekt drie kernonderdelen:
///   1. UserPhysicalProfile struct — isComplete & coachSummary (pure logica)
///   2. BiologicalSex enum — rawValue mapping en Codable round-trip
///   3. cachedProfile() en checkAndUpdateAgeCache() — UserDefaults-backed logica
///
/// HealthKit-afhankelijke methoden (fetchProfile, saveWeight, saveHeight) zijn buiten scope:
/// deze vereisen een HKHealthStore-mock op protocol-niveau dat nu niet bestaat.
final class UserProfileServiceTests: XCTestCase {

    // MARK: - Setup / Teardown

    /// Verwijdert de UserDefaults-sleutels vóór en na elke test zodat tests niet van elkaar afhangen.
    override func setUp() {
        super.setUp()
        clearUserDefaultsKeys()
    }

    override func tearDown() {
        clearUserDefaultsKeys()
        super.tearDown()
    }

    private func clearUserDefaultsKeys() {
        UserDefaults.standard.removeObject(forKey: UserProfileService.weightKey)
        UserDefaults.standard.removeObject(forKey: UserProfileService.heightKey)
        UserDefaults.standard.removeObject(forKey: UserProfileService.cachedAgeKey)
    }

    // MARK: - 1. UserPhysicalProfile: isComplete

    func testIsComplete_AllValuesSet_ReturnsTrue() {
        // Given: een volledig ingevuld profiel
        let profile = UserPhysicalProfile(
            weightKg: 75.0, heightCm: 178.0, ageYears: 30,
            sex: .male, weightSource: .healthKit, heightSource: .healthKit
        )

        // Then: isComplete is true
        XCTAssertTrue(profile.isComplete)
    }

    func testIsComplete_ZeroWeight_ReturnsFalse() {
        // Given: gewicht = 0
        let profile = UserPhysicalProfile(
            weightKg: 0.0, heightCm: 178.0, ageYears: 30,
            sex: .male, weightSource: .defaultValue, heightSource: .healthKit
        )

        // Then: isComplete is false
        XCTAssertFalse(profile.isComplete)
    }

    func testIsComplete_ZeroHeight_ReturnsFalse() {
        // Given: lengte = 0
        let profile = UserPhysicalProfile(
            weightKg: 75.0, heightCm: 0.0, ageYears: 30,
            sex: .male, weightSource: .healthKit, heightSource: .defaultValue
        )

        // Then: isComplete is false
        XCTAssertFalse(profile.isComplete)
    }

    func testIsComplete_ZeroAge_ReturnsFalse() {
        // Given: leeftijd = 0
        let profile = UserPhysicalProfile(
            weightKg: 75.0, heightCm: 178.0, ageYears: 0,
            sex: .male, weightSource: .healthKit, heightSource: .healthKit
        )

        // Then: isComplete is false
        XCTAssertFalse(profile.isComplete)
    }

    func testIsComplete_UnknownSex_ReturnsFalse() {
        // Given: geslacht onbekend
        let profile = UserPhysicalProfile(
            weightKg: 75.0, heightCm: 178.0, ageYears: 30,
            sex: .unknown, weightSource: .healthKit, heightSource: .healthKit
        )

        // Then: isComplete is false
        XCTAssertFalse(profile.isComplete)
    }

    // MARK: - 2. UserPhysicalProfile: coachSummary

    func testCoachSummary_MaleProfile_ContainsMan() {
        // Given: man-profiel
        let profile = UserPhysicalProfile(
            weightKg: 80.0, heightCm: 182.0, ageYears: 35,
            sex: .male, weightSource: .healthKit, heightSource: .healthKit
        )

        // When
        let summary = profile.coachSummary

        // Then: bevat het label "man"
        XCTAssertTrue(summary.contains("80"), "Gewicht ontbreekt in samenvatting.")
        XCTAssertTrue(summary.contains("182"), "Lengte ontbreekt in samenvatting.")
        XCTAssertTrue(summary.contains("35"), "Leeftijd ontbreekt in samenvatting.")
        XCTAssertTrue(summary.contains("man"), "Geslachtslabel 'man' ontbreekt.")
    }

    func testCoachSummary_FemaleProfile_ContainsVrouw() {
        // Given: vrouw-profiel
        let profile = UserPhysicalProfile(
            weightKg: 62.0, heightCm: 165.0, ageYears: 28,
            sex: .female, weightSource: .local, heightSource: .local
        )

        // Then
        XCTAssertTrue(profile.coachSummary.contains("vrouw"), "Geslachtslabel 'vrouw' ontbreekt.")
    }

    func testCoachSummary_OtherSex_ContainsDivers() {
        // Given: divers-profiel
        let profile = UserPhysicalProfile(
            weightKg: 70.0, heightCm: 172.0, ageYears: 25,
            sex: .other, weightSource: .defaultValue, heightSource: .defaultValue
        )

        // Then
        XCTAssertTrue(profile.coachSummary.contains("divers"), "Geslachtslabel 'divers' ontbreekt.")
    }

    func testCoachSummary_UnknownSex_ContainsOnbekend() {
        // Given: onbekend geslacht
        let profile = UserPhysicalProfile(
            weightKg: 70.0, heightCm: 172.0, ageYears: 25,
            sex: .unknown, weightSource: .defaultValue, heightSource: .defaultValue
        )

        // Then
        XCTAssertTrue(profile.coachSummary.contains("onbekend"), "Geslachtslabel 'onbekend' ontbreekt.")
    }

    // MARK: - 3. BiologicalSex: RawValue mapping

    func testBiologicalSex_RawValues_AreCorrectStrings() {
        // Given / Then: verifieer alle raw string-waarden
        XCTAssertEqual(BiologicalSex.male.rawValue,    "male")
        XCTAssertEqual(BiologicalSex.female.rawValue,  "female")
        XCTAssertEqual(BiologicalSex.other.rawValue,   "other")
        XCTAssertEqual(BiologicalSex.unknown.rawValue, "unknown")
    }

    func testBiologicalSex_InitFromRawValue_KnownValues_ReturnCorrectCase() {
        // Given / Then: init via rawValue slaagt voor alle bekende waarden
        XCTAssertEqual(BiologicalSex(rawValue: "male"),    .male)
        XCTAssertEqual(BiologicalSex(rawValue: "female"),  .female)
        XCTAssertEqual(BiologicalSex(rawValue: "other"),   .other)
        XCTAssertEqual(BiologicalSex(rawValue: "unknown"), .unknown)
    }

    func testBiologicalSex_InitFromRawValue_UnknownString_ReturnsNil() {
        // Given: een ongeldige rawValue
        // Then: init mislukt (retourneert nil) — geen crash
        XCTAssertNil(BiologicalSex(rawValue: "nonbinary"))
        XCTAssertNil(BiologicalSex(rawValue: ""))
        XCTAssertNil(BiologicalSex(rawValue: "MALE")) // case-sensitive
    }

    func testBiologicalSex_CodableRoundTrip_AllCases() throws {
        // Given: elke case encoderen en direct terug decoderen
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for sex in [BiologicalSex.male, .female, .other, .unknown] {
            // When
            let data  = try encoder.encode(sex)
            let decoded = try decoder.decode(BiologicalSex.self, from: data)

            // Then
            XCTAssertEqual(decoded, sex, "Codable round-trip mislukt voor \(sex).")
        }
    }

    // MARK: - 4. cachedProfile(): standaard fallbacks

    func testCachedProfile_NoUserDefaults_ReturnsDefaultValues() {
        // Given: lege UserDefaults (setUp heeft keys verwijderd)
        // When
        let profile = UserProfileService.cachedProfile()

        // Then: standaardwaarden worden teruggegeven
        XCTAssertEqual(profile.weightKg,  UserProfileService.defaultWeightKg, accuracy: 0.01)
        XCTAssertEqual(profile.heightCm,  UserProfileService.defaultHeightCm, accuracy: 0.01)
        XCTAssertEqual(profile.ageYears,  UserProfileService.defaultAgeYears)
        XCTAssertEqual(profile.sex,       UserProfileService.defaultSex)
        XCTAssertEqual(profile.weightSource, .local)
        XCTAssertEqual(profile.heightSource, .local)
    }

    func testCachedProfile_WithStoredWeight_ReturnsStoredWeight() {
        // Given: een gewicht opgeslagen in UserDefaults
        UserDefaults.standard.set(82.5, forKey: UserProfileService.weightKey)

        // When
        let profile = UserProfileService.cachedProfile()

        // Then: het opgeslagen gewicht wordt gebruikt
        XCTAssertEqual(profile.weightKg, 82.5, accuracy: 0.01)
    }

    func testCachedProfile_WithStoredHeight_ReturnsStoredHeight() {
        // Given: een lengte opgeslagen in UserDefaults
        UserDefaults.standard.set(190.0, forKey: UserProfileService.heightKey)

        // When
        let profile = UserProfileService.cachedProfile()

        // Then: de opgeslagen lengte wordt gebruikt
        XCTAssertEqual(profile.heightCm, 190.0, accuracy: 0.01)
    }

    func testCachedProfile_WithStoredAge_ReturnsStoredAge() {
        // Given: een leeftijd opgeslagen in UserDefaults
        UserDefaults.standard.set(42, forKey: UserProfileService.cachedAgeKey)

        // When
        let profile = UserProfileService.cachedProfile()

        // Then: de opgeslagen leeftijd wordt gebruikt
        XCTAssertEqual(profile.ageYears, 42)
    }

    func testCachedProfile_WithAllStoredValues_ReturnsAllCorrectly() {
        // Given: alle waarden opgeslagen
        UserDefaults.standard.set(70.0, forKey: UserProfileService.weightKey)
        UserDefaults.standard.set(165.0, forKey: UserProfileService.heightKey)
        UserDefaults.standard.set(29, forKey: UserProfileService.cachedAgeKey)

        // When
        let profile = UserProfileService.cachedProfile()

        // Then
        XCTAssertEqual(profile.weightKg,  70.0, accuracy: 0.01)
        XCTAssertEqual(profile.heightCm, 165.0, accuracy: 0.01)
        XCTAssertEqual(profile.ageYears,   29)
    }

    // MARK: - 5. checkAndUpdateAgeCache()

    func testCheckAndUpdateAgeCache_FirstCall_ReturnsFalse() {
        // Given: geen gecachte leeftijd (setUp heeft key verwijderd)
        let service = UserProfileService(healthStore: HKHealthStore())

        // When: eerste aanroep — er is geen vorige waarde om mee te vergelijken
        let changed = service.checkAndUpdateAgeCache(newAge: 30)

        // Then: geen wijziging gemeld (eerste keer registreren, niet bijwerken)
        XCTAssertFalse(changed, "Eerste aanroep moet false retourneren; er is geen vorige waarde.")
    }

    func testCheckAndUpdateAgeCache_SameAgeSecondCall_ReturnsFalse() {
        // Given: leeftijd al gecacht als 30
        UserDefaults.standard.set(30, forKey: UserProfileService.cachedAgeKey)
        let service = UserProfileService(healthStore: HKHealthStore())

        // When: zelfde leeftijd doorgeven
        let changed = service.checkAndUpdateAgeCache(newAge: 30)

        // Then: geen wijziging
        XCTAssertFalse(changed, "Gelijke leeftijd mag geen wijziging signaleren.")
    }

    func testCheckAndUpdateAgeCache_DifferentAgeSecondCall_ReturnsTrue() {
        // Given: leeftijd gecacht als 30
        UserDefaults.standard.set(30, forKey: UserProfileService.cachedAgeKey)
        let service = UserProfileService(healthStore: HKHealthStore())

        // When: nieuwe leeftijd doorgeven (verjaardag gehad)
        let changed = service.checkAndUpdateAgeCache(newAge: 31)

        // Then: wijziging gedetecteerd
        XCTAssertTrue(changed, "Gewijzigde leeftijd moet true retourneren.")
    }

    func testCheckAndUpdateAgeCache_UpdatesStoredValue() {
        // Given: geen vorige cache
        let service = UserProfileService(healthStore: HKHealthStore())

        // When: aanroep met leeftijd 28
        _ = service.checkAndUpdateAgeCache(newAge: 28)

        // Then: nieuwe waarde is opgeslagen
        let stored = UserDefaults.standard.object(forKey: UserProfileService.cachedAgeKey) as? Int
        XCTAssertEqual(stored, 28, "Nieuwe leeftijd moet worden opgeslagen in UserDefaults.")
    }
}
