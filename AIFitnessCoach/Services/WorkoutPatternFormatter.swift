import Foundation

// MARK: - Epic 32 Story 32.3b: WorkoutPatternFormatter
//
// Pure-Swift helper that turns `[WorkoutPattern]` into two text forms:
//   • `promptSnippet`: structured context for AI prompts (per-workout
//     coach analysis and the global chat context prefix from story 32.3c).
//   • `fingerprint`: a stable cache key so regeneration only
//     happens when the patterns actually change (e.g. after reclassification).
//
// No UI, AppStorage or AI dependency — `[WorkoutPattern]` in,
// `String` out. That keeps all prompt-engineering choices in one file
// and fully unit-testable.

enum WorkoutPatternFormatter {

    /// Builds a prompt snippet the AI can read as context. Design:
    ///   • One-liner per pattern, prefixed with a severity token so the AI sees priority
    ///   • Include the numeric value (no "somewhere around 5%") — gives the coach something to hold on to
    ///   • Order matches the detector output (decoupling → drift → cadence → recovery)
    ///   • Empty patterns array → `nil` so the caller knows there is nothing to say
    static func promptSnippet(for patterns: [WorkoutPattern]) -> String? {
        guard !patterns.isEmpty else { return nil }
        let lines = patterns.map { line(for: $0) }
        return lines.joined(separator: "\n")
    }

    /// Story 45.1: a one-line variant of `promptSnippet` for an inline suffix in
    /// `WorkoutHistoryContextBuilder` output. Patterns are separated with ` / `
    /// instead of `\n`, and the detail field is replaced by a short `value`-with-
    /// unit rendering. This avoids the redundancy of `[SEVERITY] kind: Kind: …`
    /// in the detector's prose detail strings and saves ~60% tokens
    /// per pattern in the prompt. The full `detail` text remains available for
    /// the UI pins in `WorkoutAnalysisView` via `promptSnippet`.
    static func inlineSnippet(for patterns: [WorkoutPattern]) -> String? {
        guard !patterns.isEmpty else { return nil }
        return patterns.map { inlineLine(for: $0) }.joined(separator: " / ")
    }

    /// Inline format: `[SEVERITY] kind value+unit`. The unit depends on `kind`
    /// (see comment on `WorkoutPattern.value`): drift types in %, recovery in bpm,
    /// cadence fade unitless (sport-dependent: rpm for cycling, spm for running).
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

    /// One-liner per pattern. Format: `[severity] kind: numeric value + explanation`.
    private static func line(for pattern: WorkoutPattern) -> String {
        "[\(severityToken(for: pattern.severity))] \(kindToken(for: pattern.kind)): \(pattern.detail)"
    }

    /// Stable fingerprint for cache invalidation. Changes as soon as patterns,
    /// severity or the rounded value shifts; insensitive to microscopic
    /// drift differences after reclassification. Not a cryptographic hash —
    /// just collision-free enough for per-workout cache keys.
    static func fingerprint(for patterns: [WorkoutPattern]) -> String {
        guard !patterns.isEmpty else { return "empty" }
        let parts = patterns
            .sorted { lhs, rhs in lhs.kind.rawValue < rhs.kind.rawValue }
            .map { "\($0.kind.rawValue):\($0.severity.rawValue):\(Int($0.value.rounded()))" }
        return parts.joined(separator: "|")
    }

    /// Builds the user-facing direction of the prompt fragment for the chat context prefix
    /// (story 32.3c). Returns a short, readable sentence the coach can elaborate on in a normal
    /// turn without JSON structure. Returns `nil` if there are no significant
    /// patterns — mentioning mild patterns in every chat turn is too noisy.
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
