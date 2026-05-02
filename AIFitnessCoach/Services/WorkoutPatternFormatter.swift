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
    /// i.p.v. `\n` zodat een hele workout op één prompt-regel past.
    static func inlineSnippet(for patterns: [WorkoutPattern]) -> String? {
        guard !patterns.isEmpty else { return nil }
        return patterns.map { line(for: $0) }.joined(separator: " / ")
    }

    /// One-liner per patroon. Format: `[severity] kind: numerieke waarde + uitleg`.
    private static func line(for pattern: WorkoutPattern) -> String {
        let severityToken: String
        switch pattern.severity {
        case .mild:        severityToken = "MILD"
        case .moderate:    severityToken = "MODERATE"
        case .significant: severityToken = "SIGNIFICANT"
        }
        let kindToken: String
        switch pattern.kind {
        case .aerobicDecoupling: kindToken = "aerobic_decoupling"
        case .cardiacDrift:      kindToken = "cardiac_drift"
        case .cadenceFade:       kindToken = "cadence_fade"
        case .heartRateRecovery: kindToken = "hr_recovery"
        }
        return "[\(severityToken)] \(kindToken): \(pattern.detail)"
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
