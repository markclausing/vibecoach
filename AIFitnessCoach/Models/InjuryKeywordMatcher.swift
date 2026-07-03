import Foundation

/// Pure, AppStorage-free matcher deciding whether an injury keyword occurs in free text.
///
/// Epic 18 / #37.4 originally shipped a bare `text.contains(keyword)` check. Generic keywords
/// then matched *inside* innocent words: "rug" matched "te**rug**"/"vliegb**rug**", "back" matched
/// "feed**back**"/"come**back**". A maintainer saw a phantom "Back" symptom tracker on the
/// dashboard without ever recording a back complaint (on-device validation, 2026-07-03).
///
/// Fix: a keyword only matches when it starts on a **word boundary** — the start of the string or
/// right after a non-alphanumeric character. By default the keyword may still continue into a
/// longer word, so Dutch/German compounds keep matching ("rug" → "rugpijn"/"rugklachten",
/// "knie" → "knieblessure"). A few short keywords are too greedy for prefix matching
/// ("hand" → "handig"/"handleiding", "back" → "back-to-back"): those opt into whole-word-only
/// matching via `exactWordKeywords`.
///
/// Language-independent by construction (§13): it operates on Unicode word boundaries, so it works
/// identically for the NL + EN + DE + ES keyword unions defined on `BodyArea`.
enum InjuryKeywordMatcher {

    /// Keywords for which prefix matching is too greedy, so they must match a whole word only.
    /// - "hand": Dutch "handig" (handy) / "handleiding" (manual) share the "hand" prefix but are
    ///   never injuries. Whole-word "hand" still matches "last van mijn hand".
    /// - "back": English "feedback"/"comeback"/"setback" embed "back"; whole-word matching drops
    ///   them. (Accepted residual: "back-to-back" has "back" as a hyphen-bounded whole token and
    ///   still matches — hyphens count as word boundaries by design, and this English edge is rare
    ///   enough to leave rather than special-case.)
    ///
    /// The other short body-part keywords ("rug", "knie", "kuit", …) intentionally stay prefix
    /// matches: Dutch/German compounds built on them ("rugklachten", "knieblessure") are virtually
    /// always injury-related, unlike the "handig"/"handleiding" false-positive family.
    private static let exactWordKeywords: Set<String> = ["hand", "back"]

    /// True when any of `keywords` occurs at a word boundary in `text`.
    static func matches(anyOf keywords: [String], in text: String) -> Bool {
        let haystack = fold(text)
        return keywords.contains { matches(keyword: $0, foldedText: haystack) }
    }

    /// True when `keyword` occurs at a word boundary in `text`.
    static func matches(keyword: String, in text: String) -> Bool {
        matches(keyword: keyword, foldedText: fold(text))
    }

    // MARK: - Internals

    /// Locale-insensitive lowercasing + diacritic folding so "Muñeca"/"muneca" and
    /// "Rücken"/"rucken" compare equal regardless of how the user typed the accent.
    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func matches(keyword rawKeyword: String, foldedText haystack: String) -> Bool {
        let keyword = fold(rawKeyword)
        guard !keyword.isEmpty else { return false }
        let exactWordOnly = exactWordKeywords.contains(rawKeyword)

        var searchStart = haystack.startIndex
        while let range = haystack.range(of: keyword, range: searchStart..<haystack.endIndex) {
            // Boundary before the match: start of string OR a non-alphanumeric char precedes it.
            let boundaryBefore: Bool
            if range.lowerBound == haystack.startIndex {
                boundaryBefore = true
            } else {
                let prev = haystack[haystack.index(before: range.lowerBound)]
                boundaryBefore = !isWordCharacter(prev)
            }

            // Boundary after the match is only enforced for whole-word keywords; prefix keywords
            // may continue into a longer compound.
            let boundaryAfter: Bool
            if !exactWordOnly {
                boundaryAfter = true
            } else if range.upperBound == haystack.endIndex {
                boundaryAfter = true
            } else {
                boundaryAfter = !isWordCharacter(haystack[range.upperBound])
            }

            if boundaryBefore && boundaryAfter {
                return true
            }
            // Advance one character past this occurrence's start to find later occurrences
            // (e.g. a keyword embedded mid-word here but standing alone later in the text).
            searchStart = haystack.index(after: range.lowerBound)
        }
        return false
    }

    /// A word character is a letter or number. Everything else (space, punctuation, hyphen,
    /// slash) is treated as a word boundary.
    private static func isWordCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber
    }
}
