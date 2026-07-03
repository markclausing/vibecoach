import Foundation

/// Story 65.3: pure parsing of the coach's raw model response.
///
/// Extracted from `ChatViewModel.fetchAIResponse` so the markdown-stripping,
/// brace-balancing and plan-decoding logic is unit-testable without a
/// `ChatViewModel` instance (CLAUDE.md §6). The view model keeps the side effects
/// (updating the plan manager, appending chat messages, storing the insight).
enum CoachResponseParser {

    /// The outcome of parsing one raw model response: the decoded plan (if any) plus
    /// the user-facing motivation text to show in the chat.
    struct ParsedResponse {
        let plan: SuggestedTrainingPlan?
        let motivation: String
    }

    /// Fetches a clean JSON string from an AI response that may contain markdown formatting.
    ///
    /// Strategy (in order):
    /// 1. Strip markdown code block tags (```json, ```JSON, ```) at the beginning and end.
    /// 2. Extract the first balanced top-level `{ ... }` object: scan from the first `{`
    ///    while tracking string context (so braces inside string values don't count) and
    ///    brace depth, then stop at the matching `}`. This discards any trailing junk —
    ///    most importantly a duplicated closing brace (`}}`), which the model occasionally
    ///    emits and which `JSONDecoder` rejects as malformed.
    /// 3. Trim whitespace.
    static func extractCleanJSON(from rawText: String) -> String {
        var text = rawText

        // Step 1: Strip markdown code block opening tag (```json or ```)
        // Use case-insensitive search so ```JSON also works
        if let startRange = text.range(of: "```json", options: .caseInsensitive) {
            text = String(text[startRange.upperBound...])
        } else if let startRange = text.range(of: "```") {
            text = String(text[startRange.upperBound...])
        }

        // Strip closing ``` (search from back to front)
        if let endRange = text.range(of: "```", options: .backwards) {
            text = String(text[..<endRange.lowerBound])
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Step 2: Extract the first balanced { ... } object. String-aware so a `{`/`}`
        // inside a description/reasoning value doesn't throw off the depth count, and
        // escape-aware so an escaped quote (\") inside a string isn't treated as the
        // string terminator.
        guard let start = text.firstIndex(of: "{") else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var depth = 0
        var inString = false
        var escaped = false
        var idx = start
        var balancedEnd: String.Index?
        while idx < text.endIndex {
            let ch = text[idx]
            if escaped {
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "\"" {
                inString.toggle()
            } else if !inString {
                if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        balancedEnd = idx
                        break
                    }
                }
            }
            idx = text.index(after: idx)
        }

        if let balancedEnd {
            // Found a complete object — drop anything after the matching brace.
            text = String(text[start...balancedEnd])
        } else if !text.hasPrefix("{") {
            // Unbalanced (e.g. a truncated response) and there was leading prose:
            // fall back to the old first-{ … last-} slice so we still attempt a parse.
            if let lastBrace = text.lastIndex(of: "}") {
                text = String(text[start...lastBrace])
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decodes the raw model response into a plan + user-facing motivation.
    ///
    /// - `plan` is non-nil only when the JSON decoded into a `SuggestedTrainingPlan`.
    /// - `motivation` is always present: the plan's motivation, or the `fallbackMessage`
    ///   (for hidden system calls, so raw JSON never leaks into the chat), or the cleaned
    ///   prose for a regular chat reply that carried no JSON.
    static func parse(rawResponse: String?, fallbackMessage: String?) -> ParsedResponse {
        let cleanedJSON = extractCleanJSON(from: rawResponse ?? "{}")

        guard let data = cleanedJSON.data(using: .utf8) else {
            return ParsedResponse(
                plan: nil,
                motivation: fallbackMessage ?? String(localized: "Ik kon de reactie niet verwerken. Probeer het opnieuw.")
            )
        }

        do {
            let plan = try JSONDecoder().decode(SuggestedTrainingPlan.self, from: data)

            // SPRINT 13.4: motivation always visible in the chat. If the AI returns an
            // empty field, show the fallbackMessage so there is always a human confirmation.
            let trimmedMotivation = plan.motivation.trimmingCharacters(in: .whitespacesAndNewlines)
            let motivation = trimmedMotivation.isEmpty
                ? (fallbackMessage ?? String(localized: "Ik heb je schema bijgewerkt! Bekijk je overzicht."))
                : trimmedMotivation
            return ParsedResponse(plan: plan, motivation: motivation)
        } catch {
            // JSON parsing failed: use the fallbackMessage if provided (recovery plan /
            // skip-workout calls), so raw JSON is never visible in the chat. For regular
            // chat messages we show the cleaned text (prose without JSON blocks).
            AppLoggers.coach.warning("JSON parsing failed: \(error.localizedDescription, privacy: .public)")
            let motivation: String
            if let fallback = fallbackMessage {
                motivation = fallback
            } else {
                motivation = cleanedJSON.hasPrefix("{")
                    ? String(localized: "Ik kon het schema niet correct verwerken. Probeer het opnieuw.")
                    : cleanedJSON
            }
            return ParsedResponse(plan: nil, motivation: motivation)
        }
    }
}
