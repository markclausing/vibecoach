import Foundation

// MARK: - Story 61.4 (security-review follow-up): sanitize external free text for the prompt
//
// Synced data the user does not author directly — most notably Strava
// `activity.name`, which can be set by connected devices, third-party apps or
// shared/club scenarios — flows verbatim into the coach prompt (review L-1 /
// LLM01 prompt-injection). External data should be treated as untrusted before
// it enters an LLM context, especially since the model's structured output is
// acted upon (plan persistence). This helper neutralises the cheap injection
// vectors at the interpolation site:
//   • control characters and newlines → spaces (no fake "new instruction" lines),
//   • runs of whitespace collapsed,
//   • length capped (a pathologically long name can't crowd out the prompt),
//   • blank input → a neutral placeholder.
//
// Pure value-in/value-out (§6) — unit-testable, no I/O.
enum PromptInputSanitizer {

    /// Default cap for an interpolated external label (e.g. a workout name).
    static let defaultMaxLength = 80

    static func sanitizeExternalText(_ raw: String, maxLength: Int = defaultMaxLength) -> String {
        let strip = CharacterSet.controlCharacters.union(.newlines)

        // Replace control/newline scalars with spaces.
        var cleaned = String(String.UnicodeScalarView(
            raw.unicodeScalars.map { strip.contains($0) ? " " : $0 }
        ))

        // Collapse whitespace runs and trim.
        cleaned = cleaned.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        if cleaned.isEmpty { return "(unnamed)" }

        if cleaned.count > maxLength {
            cleaned = String(cleaned.prefix(maxLength)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return cleaned
    }
}
