import Foundation

/// Epic #62 story 62.2 — pure-Swift hardening for the BYOK API-key field.
///
/// AppStorage-free (§6). The View calls `sanitize` on every change to auto-trim a pasted
/// key, and `isProviderMismatch` to warn when a key's prefix belongs to a different provider
/// than the one selected (e.g. an `sk-…` OpenAI key pasted under Gemini).
enum APIKeyInputValidator {

    /// Strips all surrounding and embedded whitespace/newlines a paste may carry. Provider API
    /// keys never contain internal whitespace, so collapsing it is safe and avoids a silent auth
    /// failure from a stray space or a line-wrapped newline.
    static func sanitize(_ raw: String) -> String {
        raw.components(separatedBy: .whitespacesAndNewlines).joined()
    }

    /// The provider a key most likely belongs to, inferred from its prefix. `nil` when the prefix
    /// is not distinctive (Mistral keys carry no standard prefix, and we never guess on those).
    ///
    /// Prefixes mirror `AIProvider.keyPlaceholder`: `sk-ant-` (Anthropic) is checked before the
    /// broader `sk-` (OpenAI, incl. `sk-proj-`); `AIza` is Google/Gemini.
    static func inferredProvider(forKey key: String) -> AIProvider? {
        let k = sanitize(key)
        if k.hasPrefix("sk-ant-") { return .anthropic }
        if k.hasPrefix("sk-")     { return .openAI }
        if k.hasPrefix("AIza")    { return .gemini }
        return nil
    }

    /// True when the key's prefix clearly belongs to a *different* provider than `selected`.
    /// Only fires on a confident inference — an unrecognised prefix never warns (avoids false
    /// positives on Mistral keys or future formats).
    static func isProviderMismatch(key: String, selected: AIProvider) -> Bool {
        guard let inferred = inferredProvider(forKey: key) else { return false }
        return inferred != selected
    }
}
