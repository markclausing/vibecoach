import XCTest
@testable import AIFitnessCoach

/// Epic 32 Story 32.3b — `WorkoutPatternFormatter`.
/// Borgt:
///  • Lege patronen-lijst → nil snippet
///  • Format-stabiliteit (severity-token + kind-token + detail)
///  • Fingerprint-stabiliteit en invalidatie
///  • `chatContextLine` toont alleen significante patronen
final class WorkoutPatternFormatterTests: XCTestCase {

    private func makePattern(kind: WorkoutPatternKind,
                             severity: WorkoutPattern.Severity,
                             value: Double = 7.0,
                             detail: String? = nil) -> WorkoutPattern {
        let now = Date()
        return WorkoutPattern(
            kind: kind,
            severity: severity,
            range: now ... now.addingTimeInterval(60),
            value: value,
            detail: detail ?? "Test detail voor \(kind.rawValue)"
        )
    }

    // MARK: promptSnippet

    func testPromptSnippet_EmptyPatterns_ReturnsNil() {
        XCTAssertNil(WorkoutPatternFormatter.promptSnippet(for: []))
    }

    func testPromptSnippet_SinglePattern_FormatsExpected() {
        let pattern = makePattern(kind: .cardiacDrift, severity: .moderate,
                                  detail: "Cardiac drift: HR-gemiddelde steeg 6.2%")
        let snippet = WorkoutPatternFormatter.promptSnippet(for: [pattern])
        XCTAssertEqual(snippet, "[MODERATE] cardiac_drift: Cardiac drift: HR-gemiddelde steeg 6.2%")
    }

    func testPromptSnippet_MultiplePatterns_JoinsWithNewline() {
        let patterns = [
            makePattern(kind: .aerobicDecoupling, severity: .significant, detail: "decoupling 13%"),
            makePattern(kind: .cardiacDrift, severity: .moderate, detail: "drift 6%"),
        ]
        let snippet = WorkoutPatternFormatter.promptSnippet(for: patterns)
        let lines = snippet?.split(separator: "\n").map(String.init) ?? []
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("SIGNIFICANT"))
        XCTAssertTrue(lines[0].contains("aerobic_decoupling"))
        XCTAssertTrue(lines[1].contains("MODERATE"))
        XCTAssertTrue(lines[1].contains("cardiac_drift"))
    }

    func testPromptSnippet_AllFourKinds_FormatsAll() {
        let patterns: [WorkoutPattern] = [
            makePattern(kind: .aerobicDecoupling, severity: .significant),
            makePattern(kind: .cardiacDrift, severity: .moderate),
            makePattern(kind: .cadenceFade, severity: .mild),
            makePattern(kind: .heartRateRecovery, severity: .significant),
        ]
        let snippet = WorkoutPatternFormatter.promptSnippet(for: patterns)
        XCTAssertNotNil(snippet)
        XCTAssertTrue(snippet?.contains("aerobic_decoupling") ?? false)
        XCTAssertTrue(snippet?.contains("cardiac_drift") ?? false)
        XCTAssertTrue(snippet?.contains("cadence_fade") ?? false)
        XCTAssertTrue(snippet?.contains("hr_recovery") ?? false)
    }

    // MARK: fingerprint

    func testFingerprint_EmptyPatterns_ReturnsSentinel() {
        XCTAssertEqual(WorkoutPatternFormatter.fingerprint(for: []), "empty")
    }

    func testFingerprint_SortsKindsForStability() {
        let a = [
            makePattern(kind: .cardiacDrift, severity: .moderate, value: 6),
            makePattern(kind: .aerobicDecoupling, severity: .significant, value: 13),
        ]
        let b = [
            makePattern(kind: .aerobicDecoupling, severity: .significant, value: 13),
            makePattern(kind: .cardiacDrift, severity: .moderate, value: 6),
        ]
        // Volgorde-onafhankelijk: zelfde patronen → zelfde fingerprint.
        XCTAssertEqual(WorkoutPatternFormatter.fingerprint(for: a),
                       WorkoutPatternFormatter.fingerprint(for: b))
    }

    func testFingerprint_RoundsValueToInt_IgnoresMicroDrift() {
        let baseline = makePattern(kind: .cardiacDrift, severity: .moderate, value: 6.2)
        let nudged   = makePattern(kind: .cardiacDrift, severity: .moderate, value: 6.4)
        XCTAssertEqual(WorkoutPatternFormatter.fingerprint(for: [baseline]),
                       WorkoutPatternFormatter.fingerprint(for: [nudged]),
                       "Drift-waardes binnen 1 punt mogen de cache-key niet invalideren")
    }

    func testFingerprint_DifferentSeverity_InvalidatesCache() {
        let mild     = makePattern(kind: .cardiacDrift, severity: .mild, value: 4)
        let moderate = makePattern(kind: .cardiacDrift, severity: .moderate, value: 6)
        XCTAssertNotEqual(WorkoutPatternFormatter.fingerprint(for: [mild]),
                          WorkoutPatternFormatter.fingerprint(for: [moderate]))
    }

    func testFingerprint_DifferentKind_InvalidatesCache() {
        let drift     = makePattern(kind: .cardiacDrift, severity: .moderate, value: 6)
        let cadence   = makePattern(kind: .cadenceFade, severity: .moderate, value: 6)
        XCTAssertNotEqual(WorkoutPatternFormatter.fingerprint(for: [drift]),
                          WorkoutPatternFormatter.fingerprint(for: [cadence]))
    }

    // MARK: chatContextLine

    func testChatContextLine_NoSignificantPatterns_ReturnsNil() {
        let mild = [makePattern(kind: .cardiacDrift, severity: .mild)]
        XCTAssertNil(WorkoutPatternFormatter.chatContextLine(for: mild),
                     "Mild patronen mogen de chat-context niet vervuilen")
    }

    func testChatContextLine_SingleSignificantPattern_ReturnsLabel() {
        let patterns = [makePattern(kind: .aerobicDecoupling, severity: .significant)]
        let line = WorkoutPatternFormatter.chatContextLine(for: patterns)
        XCTAssertEqual(line, "Recente workout(s) tonen: aerobic decoupling.")
    }

    func testChatContextLine_MultipleSignificantPatterns_JoinsLabels() {
        let patterns = [
            makePattern(kind: .aerobicDecoupling, severity: .significant),
            makePattern(kind: .heartRateRecovery, severity: .significant),
            makePattern(kind: .cadenceFade, severity: .mild), // wordt gefilterd
        ]
        let line = WorkoutPatternFormatter.chatContextLine(for: patterns)
        XCTAssertNotNil(line)
        XCTAssertTrue(line?.contains("aerobic decoupling") ?? false)
        XCTAssertTrue(line?.contains("trage HR-recovery") ?? false)
        XCTAssertFalse(line?.contains("cadence") ?? true,
                       "Mild cadence-patroon moet uit de chat-context blijven")
    }

    // MARK: inlineSnippet

    func testInlineSnippet_EmptyPatterns_ReturnsNil() {
        XCTAssertNil(WorkoutPatternFormatter.inlineSnippet(for: []))
    }

    func testInlineSnippet_AllKinds_RendersValueWithKindSpecificUnit() {
        let patterns: [WorkoutPattern] = [
            makePattern(kind: .aerobicDecoupling, severity: .significant, value: 9.1),
            makePattern(kind: .cardiacDrift, severity: .moderate, value: 6.4),
            makePattern(kind: .heartRateRecovery, severity: .mild, value: 24),
            makePattern(kind: .cadenceFade, severity: .moderate, value: 7),
        ]
        let snippet = WorkoutPatternFormatter.inlineSnippet(for: patterns)
        XCTAssertEqual(snippet,
                       "[SIGNIFICANT] aerobic_decoupling 9.1% / [MODERATE] cardiac_drift 6.4% / [MILD] hr_recovery 24 bpm / [MODERATE] cadence_fade 7")
    }

    func testInlineSnippet_OmitsProseDetail() {
        // Borgt dat de inline-variant géén verbose detail-tekst meer bevat — anders
        // krijgen we de oude redundantie "[KIND] kind: Kind: HR steeg ..." terug.
        let pattern = makePattern(kind: .cardiacDrift, severity: .significant, value: 8.2,
                                  detail: "Cardiac drift: HR-gemiddelde steeg 8.2% van helft 1 naar helft 2")
        let snippet = WorkoutPatternFormatter.inlineSnippet(for: [pattern])
        XCTAssertNotNil(snippet)
        XCTAssertFalse(snippet?.contains("HR-gemiddelde") ?? true,
                       "Inline-snippet mag geen prozaïsche detail-tekst bevatten")
        XCTAssertFalse(snippet?.contains(": Cardiac") ?? true,
                       "Inline-snippet mag de kind-naam niet dubbel renderen")
        XCTAssertEqual(snippet, "[SIGNIFICANT] cardiac_drift 8.2%")
    }
}
