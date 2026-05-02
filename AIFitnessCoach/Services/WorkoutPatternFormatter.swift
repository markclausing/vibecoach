import Foundation

// MARK: - Epic 32 Story 32.3b: WorkoutPatternFormatter
//
// Pure-Swift helper die `[WorkoutPattern]` omzet in twee tekstvormen:
//   • `promptSnippet`: gestructureerde context voor AI-prompts (per-workout
//     coach-analyse én de globale chat-context-prefix uit story 32.3c).
//   • `fingerprint`: stabiele cache-sleutel zodat opnieuw genereren alleen
//     gebeurt als de patronen daadwerkelijk veranderen (bv. na re-classificatie).
//
// Geen UI-, AppStorage- of AI-afhankelijkheid — `[WorkoutPattern]` in,
// `String` uit. Dat houdt alle prompt-engineering-keuzes in één bestand
// en volledig unit-testbaar.

enum WorkoutPatternFormatter {

    /// Bouwt een prompt-snippet die de AI als context kan lezen. Ontwerp:
    ///   • One-liner per patroon, prefix met severity-token zodat de AI prioriteit ziet
    ///   • Numerieke waarde meegeven (geen "ergens rond 5%") — geeft de coach houvast
    ///   • Volgorde matcht de detector-output (decoupling → drift → cadence → recovery)
    ///   • Lege patronen-array → `nil` zodat caller weet dat er niets te zeggen is
    static func promptSnippet(for patterns: [WorkoutPattern]) -> String? {
        guard !patterns.isEmpty else { return nil }
        let lines = patterns.map { line(for: $0) }
        return lines.joined(separator: "\n")
    }

    /// Story 45.1: één-regel-variant van `promptSnippet` voor inline-suffix in
    /// `WorkoutHistoryContextBuilder`-output. Patronen worden met ` / ` gescheiden
    /// i.p.v. `\n`, en het detail-veld wordt vervangen door een korte `value`-met-
    /// eenheid-rendering. Dat voorkomt de redundantie van `[SEVERITY] kind: Kind: …`
    /// die in de prozaïsche detail-strings van de detector zit en bespaart ~60% tokens
    /// per patroon op de prompt. De volledige `detail`-tekst blijft beschikbaar voor
    /// de UI-pins in `WorkoutAnalysisView` via `promptSnippet`.
    static func inlineSnippet(for patterns: [WorkoutPattern]) -> String? {
        guard !patterns.isEmpty else { return nil }
        return patterns.map { inlineLine(for: $0) }.joined(separator: " / ")
    }

    /// Inline-format: `[SEVERITY] kind value+eenheid`. Eenheid hangt af van `kind`
    /// (zie comment op `WorkoutPattern.value`): drift-types in %, recovery in bpm,
    /// cadence-fade unitless (sport-afhankelijk: rpm voor cycling, spm voor running).
    private static func inlineLine(for pattern: WorkoutPattern) -> String {
        let severityToken = severityToken(for: pattern.severity)
        let kindToken = kindToken(for: pattern.kind)
        let valueLabel: String
        switch pattern.kind {
        case .aerobicDecoupling, .cardiacDrift:
            valueLabel = String(format: "%.1f%%", pattern.value)
        case .heartRateRecovery:
            valueLabel = "\(Int(pattern.value.rounded())) bpm"
        case .cadenceFade:
            valueLabel = "\(Int(pattern.value.rounded()))"
        }
        return "[\(severityToken)] \(kindToken) \(valueLabel)"
    }

    private static func severityToken(for severity: WorkoutPattern.Severity) -> String {
        switch severity {
        case .mild:        return "MILD"
        case .moderate:    return "MODERATE"
        case .significant: return "SIGNIFICANT"
        }
    }

    private static func kindToken(for kind: WorkoutPatternKind) -> String {
        switch kind {
        case .aerobicDecoupling: return "aerobic_decoupling"
        case .cardiacDrift:      return "cardiac_drift"
        case .cadenceFade:       return "cadence_fade"
        case .heartRateRecovery: return "hr_recovery"
        }
    }

    /// One-liner per patroon. Format: `[severity] kind: numerieke waarde + uitleg`.
    private static func line(for pattern: WorkoutPattern) -> String {
        "[\(severityToken(for: pattern.severity))] \(kindToken(for: pattern.kind)): \(pattern.detail)"
    }

    /// Stabiele fingerprint voor cache-invalidatie. Verandert zodra patronen,
    /// severity óf afgeronde value verschuift; ongevoelig voor microscopische
    /// drift-verschillen na hernieuwde classificatie. Geen cryptografische hash —
    /// alleen botsings-vrij genoeg voor cache-keys per workout.
    static func fingerprint(for patterns: [WorkoutPattern]) -> String {
        guard !patterns.isEmpty else { return "empty" }
        let parts = patterns
            .sorted { lhs, rhs in lhs.kind.rawValue < rhs.kind.rawValue }
            .map { "\($0.kind.rawValue):\($0.severity.rawValue):\(Int($0.value.rounded()))" }
        return parts.joined(separator: "|")
    }

    /// Bouwt de gebruikers-richting van het prompt-fragment voor de chat-context-prefix
    /// (story 32.3c). Geeft een korte, leesbare zin terug die de coach in een gewone
    /// turn kan toelichten zonder JSON-structuur. Returnt `nil` als er geen significante
    /// patronen zijn — mild patronen vermelden in elke chat-turn is té druk.
    static func chatContextLine(for patterns: [WorkoutPattern]) -> String? {
        let significant = patterns.filter { $0.severity == .significant }
        guard !significant.isEmpty else { return nil }
        let kinds = significant.map(humanLabel(for:))
        return "Recente workout(s) tonen: \(kinds.joined(separator: ", "))."
    }

    private static func humanLabel(for pattern: WorkoutPattern) -> String {
        switch pattern.kind {
        case .aerobicDecoupling: return "aerobic decoupling"
        case .cardiacDrift:      return "cardiac drift"
        case .cadenceFade:       return "cadence fade"
        case .heartRateRecovery: return "trage HR-recovery"
        }
    }
}
