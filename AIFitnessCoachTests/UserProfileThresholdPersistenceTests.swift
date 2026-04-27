import XCTest
@testable import AIFitnessCoach

/// Epic 44 Story 44.1 — `UserProfileService` threshold-persistence.
/// Borgt:
///  • Threshold-blob roundtrip via `cachedThreshold` ↔ `saveThreshold`
///  • `storeAutoDetectedThresholds` overschrijft NOOIT een handmatige waarde
///  • `effectiveMaxHeartRate` valt terug op Tanaka(`ageYears`) bij ontbrekende waarde
///  • `effectiveRestingHeartRate` valt terug op 60 BPM
final class UserProfileThresholdPersistenceTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "UserProfileThresholdPersistenceTests"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: Roundtrip

    func testSaveAndCache_RoundtripsValueAndSource() {
        let original = ThresholdValue(value: 195, source: .manual)
        UserProfileService.saveThreshold(original,
                                         forKey: UserProfileService.maxHeartRateKey,
                                         defaults: defaults)
        let recovered = UserProfileService.cachedThreshold(forKey: UserProfileService.maxHeartRateKey,
                                                            defaults: defaults)
        XCTAssertEqual(recovered, original)
    }

    func testCached_NoData_ReturnsNil() {
        XCTAssertNil(UserProfileService.cachedThreshold(forKey: UserProfileService.ftpKey,
                                                         defaults: defaults))
    }

    func testSave_NilOverwritesEntry() {
        UserProfileService.saveThreshold(ThresholdValue(value: 175, source: .automatic),
                                         forKey: UserProfileService.lactateThresholdHRKey,
                                         defaults: defaults)
        UserProfileService.saveThreshold(nil,
                                         forKey: UserProfileService.lactateThresholdHRKey,
                                         defaults: defaults)
        XCTAssertNil(UserProfileService.cachedThreshold(forKey: UserProfileService.lactateThresholdHRKey,
                                                         defaults: defaults))
    }

    // MARK: Auto-detect respect for manual values

    func testStoreAutoDetected_PreservesManualValue() {
        // Gebruiker heeft handmatig 200 BPM ingevoerd.
        UserProfileService.saveThreshold(ThresholdValue(value: 200, source: .manual),
                                         forKey: UserProfileService.maxHeartRateKey,
                                         defaults: defaults)
        // Auto-detectie ziet 188 BPM. Mag de handmatige waarde niet overschrijven.
        let result = PhysiologicalThresholdEstimator.Result(
            maxHeartRate: 188, restingHeartRate: nil, lactateThresholdHR: nil
        )
        UserProfileService.storeAutoDetectedThresholds(result, defaults: defaults)
        let recovered = UserProfileService.cachedThreshold(forKey: UserProfileService.maxHeartRateKey,
                                                            defaults: defaults)
        XCTAssertEqual(recovered?.value, 200)
        XCTAssertEqual(recovered?.source, .manual)
    }

    func testStoreAutoDetected_OverwritesPreviousAutomaticValue() {
        // Eerdere auto-detectie zei 188 BPM.
        UserProfileService.saveThreshold(ThresholdValue(value: 188, source: .automatic),
                                         forKey: UserProfileService.maxHeartRateKey,
                                         defaults: defaults)
        // Nieuwe auto-detectie ziet 192 BPM (gebruiker is fitter geworden).
        let result = PhysiologicalThresholdEstimator.Result(
            maxHeartRate: 192, restingHeartRate: nil, lactateThresholdHR: nil
        )
        UserProfileService.storeAutoDetectedThresholds(result, defaults: defaults)
        XCTAssertEqual(
            UserProfileService.cachedThreshold(forKey: UserProfileService.maxHeartRateKey,
                                                defaults: defaults)?.value,
            192
        )
    }

    func testStoreAutoDetected_ForceTrue_OverridesManualValue() {
        UserProfileService.saveThreshold(ThresholdValue(value: 200, source: .manual),
                                         forKey: UserProfileService.maxHeartRateKey,
                                         defaults: defaults)
        let result = PhysiologicalThresholdEstimator.Result(
            maxHeartRate: 188, restingHeartRate: nil, lactateThresholdHR: nil
        )
        UserProfileService.storeAutoDetectedThresholds(result, force: true, defaults: defaults)
        // Met force=true wint de auto-detectie.
        XCTAssertEqual(
            UserProfileService.cachedThreshold(forKey: UserProfileService.maxHeartRateKey,
                                                defaults: defaults)?.value,
            188
        )
    }

    func testStoreAutoDetected_NilValuesIgnored() {
        UserProfileService.saveThreshold(ThresholdValue(value: 175, source: .automatic),
                                         forKey: UserProfileService.lactateThresholdHRKey,
                                         defaults: defaults)
        // Auto-detectie heeft geen LTHR meer kunnen schatten.
        let result = PhysiologicalThresholdEstimator.Result(
            maxHeartRate: nil, restingHeartRate: nil, lactateThresholdHR: nil
        )
        UserProfileService.storeAutoDetectedThresholds(result, defaults: defaults)
        // Bestaande LTHR mag niet worden gewist door een nil-resultaat.
        XCTAssertEqual(
            UserProfileService.cachedThreshold(forKey: UserProfileService.lactateThresholdHRKey,
                                                defaults: defaults)?.value,
            175
        )
    }

    // MARK: Effective fallbacks op UserPhysicalProfile

    func testEffectiveMaxHR_NoStoredValue_FallsBackToTanaka() {
        let profile = UserPhysicalProfile(
            weightKg: 75, heightCm: 178, ageYears: 35, sex: .male,
            weightSource: .local, heightSource: .local
        )
        // Tanaka 35j = 208 - 0.7 × 35 = 183.5
        XCTAssertEqual(profile.effectiveMaxHeartRate, 183.5)
    }

    func testEffectiveMaxHR_StoredValueWins() {
        let profile = UserPhysicalProfile(
            weightKg: 75, heightCm: 178, ageYears: 35, sex: .male,
            weightSource: .local, heightSource: .local,
            maxHeartRate: ThresholdValue(value: 200, source: .manual)
        )
        XCTAssertEqual(profile.effectiveMaxHeartRate, 200)
    }

    func testEffectiveRestingHR_NoStoredValue_DefaultsTo60() {
        let profile = UserPhysicalProfile(
            weightKg: 75, heightCm: 178, ageYears: 35, sex: .male,
            weightSource: .local, heightSource: .local
        )
        XCTAssertEqual(profile.effectiveRestingHeartRate, 60)
    }

    func testEffectiveRestingHR_StoredValueWins() {
        let profile = UserPhysicalProfile(
            weightKg: 75, heightCm: 178, ageYears: 35, sex: .male,
            weightSource: .local, heightSource: .local,
            restingHeartRate: ThresholdValue(value: 48, source: .automatic)
        )
        XCTAssertEqual(profile.effectiveRestingHeartRate, 48)
    }
}
