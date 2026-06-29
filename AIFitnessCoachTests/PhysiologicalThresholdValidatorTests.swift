import XCTest
@testable import AIFitnessCoach

/// Epic #51-C: borgt de pure-Swift validatie-laag die door de
/// `TrainingThresholdsSettingsView` wordt gebruikt om silent zone-calculator-
/// failures te voorkomen.
final class PhysiologicalThresholdValidatorTests: XCTestCase {

    typealias Sut = PhysiologicalThresholdValidator

    // MARK: - Per-veld range-checks

    func testNilValueIsAlwaysOK() {
        XCTAssertEqual(Sut.validateField(.maxHR, value: nil).severity, .ok)
        XCTAssertEqual(Sut.validateField(.ftp, value: nil).severity, .ok)
    }

    func testRealisticMaxHRIsOK() {
        XCTAssertEqual(Sut.validateField(.maxHR, value: 185).severity, .ok)
    }

    func testUnusualButPossibleMaxHRIsWarning() {
        // 115 BPM ligt buiten typisch (120-230) maar binnen absoluut (60-250)
        let issue = Sut.validateField(.maxHR, value: 115)
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertTrue(issue.message.contains("Max HR"))
    }

    func testAbsurdMaxHRIsError() {
        XCTAssertEqual(Sut.validateField(.maxHR, value: 50).severity, .error)
        XCTAssertEqual(Sut.validateField(.maxHR, value: 300).severity, .error)
    }

    func testFTPRangesAreReasonable() {
        XCTAssertEqual(Sut.validateField(.ftp, value: 250).severity, .ok)
        XCTAssertEqual(Sut.validateField(.ftp, value: 50).severity, .warning) // pro-track FTP zelden < 75
        XCTAssertEqual(Sut.validateField(.ftp, value: 5000).severity, .error) // absurd
        XCTAssertEqual(Sut.validateField(.ftp, value: 0).severity, .error)
    }

    func testRestingHRBoundaries() {
        XCTAssertEqual(Sut.validateField(.restingHR, value: 60).severity, .ok)
        XCTAssertEqual(Sut.validateField(.restingHR, value: 15).severity, .error)
        XCTAssertEqual(Sut.validateField(.restingHR, value: 150).severity, .error)
    }

    // MARK: - Cross-validatie

    func testMaxHRMustExceedRestingHR() {
        let profile = Sut.ProfileInput(maxHR: 100, restingHR: 120, lthr: nil, ftp: nil)
        let issues = Sut.validateProfile(profile)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.severity, .error)
        XCTAssertTrue(issues.first?.message.contains("Max HR") ?? false)
    }

    func testEqualMaxAndRestingHRIsError() {
        // Karvonen HRR = 0 → zone-calculator levert lege array → "—"
        let profile = Sut.ProfileInput(maxHR: 150, restingHR: 150, lthr: nil, ftp: nil)
        XCTAssertEqual(Sut.validateProfile(profile).first?.severity, .error)
    }

    func testLTHRMustBeBelowMaxHR() {
        let profile = Sut.ProfileInput(maxHR: 180, restingHR: 60, lthr: 185, ftp: nil)
        let issues = Sut.validateProfile(profile)
        XCTAssertTrue(issues.contains { $0.message.contains("LTHR") && $0.message.contains("Max HR") })
    }

    func testLTHRMustBeAboveRestingHR() {
        let profile = Sut.ProfileInput(maxHR: 200, restingHR: 100, lthr: 95, ftp: nil)
        let issues = Sut.validateProfile(profile)
        XCTAssertTrue(issues.contains { $0.message.contains("LTHR") && $0.message.contains("Rust HR") })
    }

    func testConsistentProfileHasNoIssues() {
        let profile = Sut.ProfileInput(maxHR: 190, restingHR: 55, lthr: 168, ftp: 280)
        XCTAssertTrue(Sut.validateProfile(profile).isEmpty)
        XCTAssertTrue(Sut.isSavable(profile))
    }

    func testFTPDoesNotCrossValidate() {
        // Een absurd hoge FTP triggert geen cross-fail — zit los van HR-drempels
        let profile = Sut.ProfileInput(maxHR: 190, restingHR: 55, lthr: nil, ftp: 99999)
        XCTAssertTrue(Sut.validateProfile(profile).isEmpty)
    }

    // MARK: - isSavable

    func testIsSavableFalseOnlyWhenErrorPresent() {
        let warningProfile = Sut.ProfileInput(maxHR: 115, restingHR: nil, lthr: nil, ftp: nil)
        // 115 is field-warning, geen cross-error
        XCTAssertTrue(Sut.isSavable(warningProfile))

        let errorProfile = Sut.ProfileInput(maxHR: 100, restingHR: 120, lthr: nil, ftp: nil)
        XCTAssertFalse(Sut.isSavable(errorProfile))
    }

    // MARK: - Zone-card-uitleg (C4)

    func testEmptyHRZonesExplanationPreferssCrossErrorOverGenericTip() {
        let profile = Sut.ProfileInput(maxHR: 100, restingHR: 120, lthr: nil, ftp: nil)
        let explanation = Sut.emptyHRZonesExplanation(for: profile)
        XCTAssertTrue(explanation.contains("Max HR"), "Cross-error moet voorrang krijgen op generieke tip.")
        XCTAssertTrue(explanation.contains("Corrigeer"))
    }

    func testEmptyHRZonesExplanationSuggestsMissingComplement() {
        // §13: the hint is now localised, so compare against String(localized:) of the same key
        // (locale-agnostic) instead of a Dutch substring like "Rust HR" (EN: "Rest HR").
        // Alleen Max HR ingevuld → moet Rust HR of LTHR suggereren.
        let onlyMax = Sut.ProfileInput(maxHR: 185, restingHR: nil, lthr: nil, ftp: nil)
        XCTAssertEqual(Sut.emptyHRZonesExplanation(for: onlyMax),
                       String(localized: "Vul Rust HR in om zones via Karvonen te berekenen, of gebruik LTHR voor de Friel-methode."))

        // Alleen Rust HR ingevuld → moet Max HR of LTHR suggereren.
        let onlyRest = Sut.ProfileInput(maxHR: nil, restingHR: 60, lthr: nil, ftp: nil)
        XCTAssertEqual(Sut.emptyHRZonesExplanation(for: onlyRest),
                       String(localized: "Vul Max HR in om zones via Karvonen te berekenen, of gebruik LTHR voor de Friel-methode."))
    }

    func testEmptyHRZonesExplanationFallsBackOnGenericTipWhenNothingSet() {
        let empty = Sut.ProfileInput()
        let explanation = Sut.emptyHRZonesExplanation(for: empty)
        XCTAssertTrue(explanation.contains("Karvonen") || explanation.contains("Friel"))
    }

    func testEmptyPowerZonesExplanationSuggestsFTPWhenMissing() {
        let empty = Sut.ProfileInput()
        XCTAssertTrue(Sut.emptyPowerZonesExplanation(for: empty).contains("FTP"))
    }
}
