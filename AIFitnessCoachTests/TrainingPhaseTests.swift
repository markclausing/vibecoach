import XCTest
@testable import AIFitnessCoach

/// Unit tests voor TrainingPhase (Epic 16) en de fase-afhankelijke TRIMP-berekening.
///
/// TrainingPhase en FitnessGoal zijn pure modellen — geen SwiftData container nodig
/// voor de rekenlogica zelf. Alle tests draaien synchroon en in milliseconden.
final class TrainingPhaseTests: XCTestCase {

    // MARK: - Fase-detectie via calculate(weeksRemaining:)

    /// Meer dan 12 weken resterend → Base Building fase.
    func testCalculate_MoreThan12Weeks_IsBaseBuilding() {
        XCTAssertEqual(TrainingPhase.calculate(weeksRemaining: 13), .baseBuilding)
        XCTAssertEqual(TrainingPhase.calculate(weeksRemaining: 52), .baseBuilding,
                       "Ook een volledig jaar vooruit moet Base Building zijn.")
    }

    /// Exact 12 weken resterend valt nog binnen Base Building (grens is >12, niet ≥12).
    func testCalculate_Exactly12Weeks_IsBaseBuilding() {
        XCTAssertEqual(TrainingPhase.calculate(weeksRemaining: 12), .baseBuilding,
                       "12 weken exact = bovenkant van Build, maar de range is 4..<12 — dus 12 = baseBuilding.")
    }

    /// Tussen 4 en 12 weken → Build Phase.
    func testCalculate_Between4And12Weeks_IsBuildPhase() {
        XCTAssertEqual(TrainingPhase.calculate(weeksRemaining: 8),  .buildPhase)
        XCTAssertEqual(TrainingPhase.calculate(weeksRemaining: 4),  .buildPhase,
                       "4 weken exact = onderkant van Build Phase.")
        XCTAssertEqual(TrainingPhase.calculate(weeksRemaining: 11.9), .buildPhase)
    }

    /// Tussen 2 en 4 weken → Peak Phase.
    func testCalculate_Between2And4Weeks_IsPeakPhase() {
        XCTAssertEqual(TrainingPhase.calculate(weeksRemaining: 3),   .peakPhase)
        XCTAssertEqual(TrainingPhase.calculate(weeksRemaining: 2),   .peakPhase,
                       "2 weken exact = onderkant van Peak Phase.")
        XCTAssertEqual(TrainingPhase.calculate(weeksRemaining: 3.9), .peakPhase)
    }

    /// Minder dan 2 weken resterend → Tapering fase.
    func testCalculate_LessThan2Weeks_IsTapering() {
        XCTAssertEqual(TrainingPhase.calculate(weeksRemaining: 1),   .tapering)
        XCTAssertEqual(TrainingPhase.calculate(weeksRemaining: 0),   .tapering,
                       "0 weken resterend (wedstrijddag) = Tapering.")
        XCTAssertEqual(TrainingPhase.calculate(weeksRemaining: 1.9), .tapering)
    }

    // MARK: - Multipliers

    /// Elke fase heeft de fysiologisch correcte multiplier.
    func testMultipliers_AreCorrect() {
        XCTAssertEqual(TrainingPhase.baseBuilding.multiplier, 1.00,
                       "Base Building: geen aanpassing van de lineaire target.")
        XCTAssertEqual(TrainingPhase.buildPhase.multiplier,   1.15,
                       "Build Phase: 15% extra belasting.")
        XCTAssertEqual(TrainingPhase.peakPhase.multiplier,    1.30,
                       "Peak Phase: 30% extra belasting (maximale adaptatie).")
        XCTAssertEqual(TrainingPhase.tapering.multiplier,     0.60,
                       "Tapering: 40% minder belasting — rust is de training.")
    }

    /// De tapering multiplier moet strikt kleiner zijn dan alle andere multipliers.
    func testTaperingMultiplier_IsLowestOfAll() {
        let allMultipliers = TrainingPhase.allCases.map { $0.multiplier }
        let taperingMultiplier = TrainingPhase.tapering.multiplier
        XCTAssertTrue(
            allMultipliers.filter { $0 != taperingMultiplier }.allSatisfy { $0 > taperingMultiplier },
            "Tapering multiplier (0.60) moet de laagste van alle fases zijn."
        )
    }

    /// De peak multiplier moet de hoogste zijn — dit is de zwaarste trainingsfase.
    func testPeakMultiplier_IsHighestOfAll() {
        let allMultipliers = TrainingPhase.allCases.map { $0.multiplier }
        let peakMultiplier = TrainingPhase.peakPhase.multiplier
        XCTAssertTrue(
            allMultipliers.filter { $0 != peakMultiplier }.allSatisfy { $0 < peakMultiplier },
            "Peak multiplier (1.30) moet de hoogste van alle fases zijn."
        )
    }

    // MARK: - Fase-gecorrigeerde TRIMP target

    /// In de Peak fase moet de gecorrigeerde wekelijkse TRIMP-target hoger zijn dan in Tapering.
    /// Dit is de kernregel van Epic 16: periodisering stuurt de belasting.
    func testAdjustedTRIMPTarget_PeakIsHigherThanTapering() {
        let totalTRIMP = 2000.0
        let weeksRemaining = 3.0
        let linearRate = totalTRIMP / weeksRemaining  // ~667 TRIMP/week

        let peakTarget    = linearRate * TrainingPhase.peakPhase.multiplier
        let taperingTarget = linearRate * TrainingPhase.tapering.multiplier

        XCTAssertGreaterThan(
            peakTarget, taperingTarget,
            "Peak target (\(Int(peakTarget)) TRIMP/wk) moet hoger zijn dan tapering target (\(Int(taperingTarget)) TRIMP/wk)."
        )
    }

    /// In de Build fase moet de gecorrigeerde target hoger zijn dan de lineaire baseline.
    func testAdjustedTRIMPTarget_BuildPhaseExceedsLinearBaseline() {
        let totalTRIMP = 1400.0
        let weeksRemaining = 8.0
        let linearRate = totalTRIMP / weeksRemaining  // 175 TRIMP/week

        let buildTarget = linearRate * TrainingPhase.buildPhase.multiplier
        XCTAssertGreaterThan(
            buildTarget, linearRate,
            "Build Phase target moet hoger zijn dan de ongewogen lineaire target."
        )
    }

    /// In de Tapering fase moet de gecorrigeerde target lager zijn dan de lineaire baseline.
    func testAdjustedTRIMPTarget_TaperingIsBelowLinearBaseline() {
        let totalTRIMP = 400.0
        let weeksRemaining = 1.5
        let linearRate = totalTRIMP / weeksRemaining

        let taperingTarget = linearRate * TrainingPhase.tapering.multiplier
        XCTAssertLessThan(
            taperingTarget, linearRate,
            "Tapering target moet lager zijn dan de ongewogen lineaire target."
        )
    }

    // MARK: - AI-instructies aanwezig

    /// Elke fase moet een niet-lege AI-instructie hebben voor injectie in de prompt.
    func testAIInstructions_AreNonEmptyForAllPhases() {
        for phase in TrainingPhase.allCases {
            XCTAssertFalse(
                phase.aiInstruction.isEmpty,
                "Fase \(phase.rawValue) heeft een lege aiInstruction — AI-injectie zou mislukken."
            )
        }
    }

    /// Elke fase moet een niet-lege displayName hebben voor de UI-badge.
    func testDisplayNames_AreNonEmptyForAllPhases() {
        for phase in TrainingPhase.allCases {
            XCTAssertFalse(
                phase.displayName.isEmpty,
                "Fase \(phase.rawValue) heeft een lege displayName — badge zou leeg zijn in de UI."
            )
        }
    }
}
