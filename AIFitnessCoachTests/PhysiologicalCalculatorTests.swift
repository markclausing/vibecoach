import XCTest
@testable import AIFitnessCoach

/// Unit tests voor PhysiologicalCalculator en InjuryImpactMatrix (Epic 27).
///
/// Dekt twee kernonderdelen:
///   1. PhysiologicalCalculator.calculateTSS — Banister TRIMP-formule en edge cases
///   2. InjuryImpactMatrix — penaltyMultiplier per blessure/sport combinatie + injuryDescription
///
/// Beide structs zijn pure rekenkunde (geen SwiftData, geen HealthKit) en worden direct getest.
final class PhysiologicalCalculatorTests: XCTestCase {

    // MARK: - Shared instance

    private let calculator = PhysiologicalCalculator()

    // MARK: - Helper

    /// Maakt een UserPreference aan met de gegeven tekst (geen ModelContext nodig voor instantiatie).
    private func pref(_ text: String) -> UserPreference {
        UserPreference(preferenceText: text)
    }

    // MARK: - 1. PhysiologicalCalculator: calculateTSS (Banister TRIMP)

    func testCalculateTSS_TypicalRun_ReturnsExpectedTRIMP() {
        // Given: 60 min (3600s), gemiddeld HR 150, max HR 200, rust HR 60
        // hrDelta = (150-60)/(200-60) = 90/140 ≈ 0.6429
        // TRIMP = 60 × 0.6429 × 0.64 × exp(1.92 × 0.6429) ≈ 84.8
        let result = calculator.calculateTSS(
            durationInSeconds: 3600,
            averageHeartRate: 150,
            maxHeartRate: 200,
            restingHeartRate: 60
        )

        XCTAssertEqual(result, 84.8, accuracy: 1.0,
                       "TRIMP voor typische 60-minuten run moet ≈ 84.8 zijn.")
    }

    func testCalculateTSS_ShortEasyRun_ReturnsLowTRIMP() {
        // Given: 30 min (1800s), lage belasting (HR 120, max 190, rust 55)
        // hrDelta = (120-55)/(190-55) = 65/135 ≈ 0.4815
        // TRIMP = 30 × 0.4815 × 0.64 × exp(1.92 × 0.4815) ≈ lager dan standaard run
        let result = calculator.calculateTSS(
            durationInSeconds: 1800,
            averageHeartRate: 120,
            maxHeartRate: 190,
            restingHeartRate: 55
        )

        XCTAssertGreaterThan(result, 0, "TRIMP moet positief zijn voor een geldige workout.")
        XCTAssertLessThan(result, 84.8, "Kortere, lichtere workout moet minder TRIMP geven dan standaard run.")
    }

    func testCalculateTSS_ZeroHRR_ReturnsZero() {
        // Given: maxHR == restingHR → HRR = 0 → geen geldige berekening
        let result = calculator.calculateTSS(
            durationInSeconds: 3600,
            averageHeartRate: 150,
            maxHeartRate: 60,   // gelijk aan restingHR
            restingHeartRate: 60
        )

        // Then: guard hrr > 0 → vroeg retourneren met 0
        XCTAssertEqual(result, 0.0, accuracy: 0.001,
                       "HRR van 0 (maxHR == restingHR) moet 0 TRIMP geven.")
    }

    func testCalculateTSS_NegativeHRR_ReturnsZero() {
        // Given: maxHR < restingHR (ongeldige input)
        let result = calculator.calculateTSS(
            durationInSeconds: 3600,
            averageHeartRate: 150,
            maxHeartRate: 50,   // lager dan restingHR
            restingHeartRate: 60
        )

        // Then: guard hrr > 0 vangt dit op
        XCTAssertEqual(result, 0.0, accuracy: 0.001,
                       "Negatieve HRR (maxHR < restingHR) moet 0 TRIMP geven.")
    }

    func testCalculateTSS_ZeroDuration_ReturnsZero() {
        // Given: duur = 0 seconden
        let result = calculator.calculateTSS(
            durationInSeconds: 0,
            averageHeartRate: 150,
            maxHeartRate: 200,
            restingHeartRate: 60
        )

        // Then: durationInMinutes = 0 → TRIMP = 0
        XCTAssertEqual(result, 0.0, accuracy: 0.001,
                       "Nul duur moet 0 TRIMP geven.")
    }

    func testCalculateTSS_HighIntensityInterval_ReturnsHighTRIMP() {
        // Given: 45 min (2700s) hoge intensiteit (HR 175, max 200, rust 55)
        // hrDelta = (175-55)/(200-55) = 120/145 ≈ 0.8276
        // TRIMP ≈ hoog door exp-term bij hoge hrDelta
        let result = calculator.calculateTSS(
            durationInSeconds: 2700,
            averageHeartRate: 175,
            maxHeartRate: 200,
            restingHeartRate: 55
        )

        XCTAssertGreaterThan(result, 84.8, "Hoge intensiteit workout van 45 min moet meer TRIMP geven dan standaard 60-min easy run.")
    }

    func testCalculateTSS_ResultIsNotNaNOrInfinite() {
        // Given: normale parameters
        let result = calculator.calculateTSS(
            durationInSeconds: 5400,
            averageHeartRate: 160,
            maxHeartRate: 195,
            restingHeartRate: 58
        )

        // Then: geen NaN of Infinity
        XCTAssertFalse(result.isNaN,      "TRIMP mag geen NaN zijn.")
        XCTAssertFalse(result.isInfinite, "TRIMP mag geen Infinity zijn.")
        XCTAssertGreaterThanOrEqual(result, 0, "TRIMP mag nooit negatief zijn.")
    }

    // MARK: - 2. InjuryImpactMatrix: penaltyMultiplier

    func testPenaltyMultiplier_NoPreferences_ReturnsOne() {
        // Given: geen actieve blessures
        let result = InjuryImpactMatrix.penaltyMultiplier(for: .running, given: [])

        // Then: geen extra belasting
        XCTAssertEqual(result, 1.0, accuracy: 0.001,
                       "Zonder blessures is de multiplier altijd 1.0.")
    }

    func testPenaltyMultiplier_KuitBlessure_Running_Returns1_4() {
        // Given: kuitklacht + hardlopen
        let result = InjuryImpactMatrix.penaltyMultiplier(for: .running, given: [pref("kuit pijn links")])

        // Then: 40% extra fysiologische belasting
        XCTAssertEqual(result, 1.4, accuracy: 0.001,
                       "Kuitklacht bij hardlopen moet multiplier 1.4 geven.")
    }

    func testPenaltyMultiplier_ScheenBlessure_Running_Returns1_4() {
        // Given: scheenbeenpijn (scheen-keyword) + hardlopen
        let result = InjuryImpactMatrix.penaltyMultiplier(for: .running, given: [pref("scheenpijn rechts")])

        XCTAssertEqual(result, 1.4, accuracy: 0.001,
                       "Scheenklacht bij hardlopen moet multiplier 1.4 geven.")
    }

    func testPenaltyMultiplier_ShinKeyword_Running_Returns1_4() {
        // Given: Engelstalig "shin" keyword + hardlopen
        let result = InjuryImpactMatrix.penaltyMultiplier(for: .running, given: [pref("shin splints")])

        XCTAssertEqual(result, 1.4, accuracy: 0.001,
                       "Engelse 'shin' keyword moet ook 1.4 geven bij hardlopen.")
    }

    func testPenaltyMultiplier_KuitBlessure_Walking_Returns1_1() {
        // Given: kuitklacht + wandelen
        let result = InjuryImpactMatrix.penaltyMultiplier(for: .walking, given: [pref("kuit")])

        XCTAssertEqual(result, 1.1, accuracy: 0.001,
                       "Kuitklacht bij wandelen moet lichte multiplier 1.1 geven.")
    }

    func testPenaltyMultiplier_KuitBlessure_Cycling_ReturnsOne() {
        // Given: kuitklacht + fietsen — geen match in switch
        let result = InjuryImpactMatrix.penaltyMultiplier(for: .cycling, given: [pref("kuit")])

        XCTAssertEqual(result, 1.0, accuracy: 0.001,
                       "Kuitklacht heeft geen impact op fietsen — multiplier moet 1.0 zijn.")
    }

    func testPenaltyMultiplier_RugBlessure_Running_Returns1_2() {
        // Given: rugpijn + hardlopen
        let result = InjuryImpactMatrix.penaltyMultiplier(for: .running, given: [pref("rugpijn")])

        XCTAssertEqual(result, 1.2, accuracy: 0.001,
                       "Rugklacht bij hardlopen moet multiplier 1.2 geven.")
    }

    func testPenaltyMultiplier_RugBlessure_Strength_Returns1_2() {
        // Given: rugpijn + krachttraining
        let result = InjuryImpactMatrix.penaltyMultiplier(for: .strength, given: [pref("rug klachten")])

        XCTAssertEqual(result, 1.2, accuracy: 0.001,
                       "Rugklacht bij krachttraining moet multiplier 1.2 geven.")
    }

    func testPenaltyMultiplier_RugBlessure_Cycling_Returns1_1() {
        // Given: rugpijn + fietsen
        let result = InjuryImpactMatrix.penaltyMultiplier(for: .cycling, given: [pref("back pain")])

        XCTAssertEqual(result, 1.1, accuracy: 0.001,
                       "Rugklacht bij fietsen moet lichte multiplier 1.1 geven.")
    }

    func testPenaltyMultiplier_RugBlessure_Swimming_ReturnsOne() {
        // Given: rugpijn + zwemmen — geen match
        let result = InjuryImpactMatrix.penaltyMultiplier(for: .swimming, given: [pref("rugpijn")])

        XCTAssertEqual(result, 1.0, accuracy: 0.001,
                       "Rugklacht heeft geen impact op zwemmen — multiplier moet 1.0 zijn.")
    }

    func testPenaltyMultiplier_MultipleInjuries_ReturnsMax() {
        // Given: kuit (1.4 bij running) én rug (1.2 bij running) tegelijk
        let prefs = [pref("kuit klachten"), pref("rugpijn")]
        let result = InjuryImpactMatrix.penaltyMultiplier(for: .running, given: prefs)

        // Then: max van beide multipliers → 1.4
        XCTAssertEqual(result, 1.4, accuracy: 0.001,
                       "Meerdere blessures: het maximum van alle multipliers moet worden teruggegeven.")
    }

    func testPenaltyMultiplier_IrrelevantPreference_ReturnsOne() {
        // Given: een voorkeur zonder blessure-trefwoorden
        let result = InjuryImpactMatrix.penaltyMultiplier(for: .running, given: [pref("geen vlees eten")])

        XCTAssertEqual(result, 1.0, accuracy: 0.001,
                       "Niet-blessure voorkeuren mogen geen impact hebben op de multiplier.")
    }

    // MARK: - 3. InjuryImpactMatrix: injuryDescription

    func testInjuryDescription_KuitRunning_ReturnsKuitklachten() {
        // Given
        let desc = InjuryImpactMatrix.injuryDescription(for: .running, given: [pref("kuit pijn")])

        XCTAssertEqual(desc, "kuitklachten",
                       "Kuitklacht bij hardlopen moet 'kuitklachten' teruggeven.")
    }

    func testInjuryDescription_KuitWalking_ReturnsKuitklachten() {
        // Given: wandelen valt ook binnen de kuit-match
        let desc = InjuryImpactMatrix.injuryDescription(for: .walking, given: [pref("kuit")])

        XCTAssertEqual(desc, "kuitklachten")
    }

    func testInjuryDescription_KuitCycling_ReturnsNil() {
        // Given: fietsen valt buiten de kuit-match
        let desc = InjuryImpactMatrix.injuryDescription(for: .cycling, given: [pref("kuit")])

        XCTAssertNil(desc, "Kuitklacht + fietsen heeft geen beschrijving — moet nil zijn.")
    }

    func testInjuryDescription_RugRunning_ReturnsRugklachten() {
        // Given
        let desc = InjuryImpactMatrix.injuryDescription(for: .running, given: [pref("rugpijn")])

        XCTAssertEqual(desc, "rugklachten")
    }

    func testInjuryDescription_RugCycling_ReturnsRugklachten() {
        // Given
        let desc = InjuryImpactMatrix.injuryDescription(for: .cycling, given: [pref("rug")])

        XCTAssertEqual(desc, "rugklachten")
    }

    func testInjuryDescription_RugStrength_ReturnsRugklachten() {
        // Given
        let desc = InjuryImpactMatrix.injuryDescription(for: .strength, given: [pref("rugpijn")])

        XCTAssertEqual(desc, "rugklachten")
    }

    func testInjuryDescription_NoPreferences_ReturnsNil() {
        // Given: geen blessures actief
        let desc = InjuryImpactMatrix.injuryDescription(for: .running, given: [])

        XCTAssertNil(desc, "Zonder blessures moet injuryDescription nil retourneren.")
    }

    func testInjuryDescription_IrrelevantPreference_ReturnsNil() {
        // Given: voorkeur zonder blessure-trefwoord
        let desc = InjuryImpactMatrix.injuryDescription(for: .running, given: [pref("vegetarisch")])

        XCTAssertNil(desc)
    }
}
