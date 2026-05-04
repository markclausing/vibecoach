import XCTest
@testable import AIFitnessCoach

final class SymptomContextFormatterTests: XCTestCase {

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    // MARK: - Empty case

    func test_format_noSymptomsNoPrefs_returnsEmpty() {
        XCTAssertEqual(SymptomContextFormatter.format(symptoms: [], preferences: []), "")
    }

    // MARK: - Active complaint with hard constraint

    func test_format_calfSeverity8_addsHardConstraint() {
        let s = Symptom(bodyArea: .calf, severity: 8, date: today)
        let output = SymptomContextFormatter.format(symptoms: [s], preferences: [])
        XCTAssertTrue(output.contains("Kuit: 8/10"))
        XCTAssertTrue(output.contains("ACTIEVE BEPERKINGEN"))
        XCTAssertTrue(output.contains("HARDLOPEN IS STRIKT VERBODEN"))
    }

    func test_format_kneeSeverity7_addsKneeHardConstraint() {
        let s = Symptom(bodyArea: .knee, severity: 7, date: today)
        let output = SymptomContextFormatter.format(symptoms: [s])
        XCTAssertTrue(output.contains("HARD CONSTRAINT Knie"))
        XCTAssertTrue(output.contains("Fietsen en zwemmen zijn veilig"))
    }

    func test_format_lightCalfSeverity2_offersAlternative() {
        let s = Symptom(bodyArea: .calf, severity: 2, date: today)
        let output = SymptomContextFormatter.format(symptoms: [s])
        XCTAssertTrue(output.contains("Kuit: 2/10"))
        XCTAssertTrue(output.contains("Score < 3"))
        XCTAssertFalse(output.contains("HARD CONSTRAINT"))
    }

    // MARK: - Recovery message

    func test_format_score0WithMatchingPref_showsRecovery() {
        let s = Symptom(bodyArea: .calf, severity: 0, date: today)
        let pref = UserPreference(preferenceText: "Last van mijn kuit deze week",
                                  isActive: true)
        let output = SymptomContextFormatter.format(symptoms: [s], preferences: [pref])
        XCTAssertTrue(output.contains("HERSTELD"))
        XCTAssertTrue(output.contains("HERSTEL MELDINGEN"))
    }

    func test_format_score0WithoutMatchingPref_returnsEmpty() {
        // Score 0 voor een gebied dat nooit een actieve klacht had → geen output.
        let s = Symptom(bodyArea: .knee, severity: 0, date: today)
        let output = SymptomContextFormatter.format(symptoms: [s], preferences: [])
        XCTAssertEqual(output, "")
    }

    // MARK: - Active pref without today's score

    func test_format_activePrefWithoutScore_warnsWithoutScore() {
        let pref = UserPreference(preferenceText: "Rugklachten sinds vorige week",
                                  isActive: true)
        let output = SymptomContextFormatter.format(symptoms: [], preferences: [pref])
        XCTAssertTrue(output.contains("score nog niet ingevuld"))
    }

    // MARK: - Expired prefs are filtered

    func test_format_expiredInjuryPref_isIgnored() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let pref = UserPreference(preferenceText: "Hand pijn",
                                  isActive: true, expirationDate: yesterday)
        let output = SymptomContextFormatter.format(symptoms: [], preferences: [pref])
        XCTAssertEqual(output, "", "Verlopen blessure-pref hoort niet meer in de coach-context te staan.")
    }
}
