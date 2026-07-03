import Foundation

// MARK: - Epic #56 story 56.1: route extraction from a goal's free text
//
// Pure-Swift, AppStorage-free (CLAUDE.md §6). Extracts a (start, end) place-name pair
// from a goal title/notes such as "Fietsen van Arnhem naar Karlsruhe in 5 dagen".
// Multilingual (NL/EN/DE/ES) per the i18n scope (CLAUDE.md §13): the user writes the
// goal in their own language, so detection must be language-independent.
//
// The extracted strings are handed to CLGeocoder (integration layer) to resolve to
// coordinates. We keep the parser deliberately conservative: a clear "from X to Y"
// pattern yields a route, anything ambiguous returns nil and the app falls back to the
// home-location forecast. "Reasonable estimate", not GPS accuracy.

enum RouteParser {

    /// Unambiguous multi-letter connectors that separate start from end ("van X **naar** Y").
    /// Tried first. Lowercased, matched as whole words.
    private static let strongMidConnectors = [
        "naar", "tot", "richting",          // NL
        "to", "towards", "until",           // EN
        "nach", "bis",                      // DE
        "hasta", "hacia"                    // ES
    ]

    /// Spanish single-letter "a" ("de Madrid **a** Sevilla"). Far too greedy to try in
    /// general (it would split "from A to B" on the "A"), so it is only used as a fallback
    /// when no strong connector matched AND a Spanish start-connector ("de"/"desde") is present.
    private static let spanishStartContext = ["de", "desde"]

    /// Words that introduce the start location ("**van** X naar Y") — stripped from the
    /// left side so "Fietsen van Arnhem" becomes "Arnhem".
    private static let startConnectors = [
        "van", "vanaf",                     // NL
        "from",                             // EN
        "von", "ab",                        // DE
        "de", "desde"                       // ES
    ]

    /// Leading activity nouns/verbs to strip from the start candidate.
    private static let leadingNoise = [
        "fietsen", "fietstocht", "wielrennen", "tocht", "rit", "ronde", "etappe",
        "cycling", "ride", "bike", "tour", "stage", "run", "running", "walk",
        "radfahren", "radtour", "lauf", "etappenfahrt",
        "ciclismo", "ruta", "vuelta", "etapa"
    ]

    /// Extracts a `(start, end)` place-name pair, or `nil` when no clear route is found.
    static func parse(_ text: String) -> (start: String, end: String)? {
        let normalized = text
            .replacingOccurrences(of: "→", with: " naar ")
            .replacingOccurrences(of: "–", with: "-")

        // Split on the first mid-connector found as a whole word (or a spaced hyphen).
        guard let split = splitOnConnector(normalized) else { return nil }

        let start = cleanStart(split.left)
        let end   = cleanEnd(split.right)

        guard !start.isEmpty, !end.isEmpty else { return nil }
        return (start, end)
    }

    // MARK: - Helpers

    private static func splitOnConnector(_ text: String) -> (left: String, right: String)? {
        let lower = text.lowercased()

        // Pass 1: earliest strong (multi-letter) connector.
        var match: Range<String.Index>?
        for connector in strongMidConnectors {
            if let r = rangeOfWord(connector, in: lower) {
                // swiftlint:disable:next force_unwrapping
                if match == nil || r.lowerBound < match!.lowerBound { match = r } // `||` short-circuits: `match!` only reached when match != nil
            }
        }

        // Pass 2: spaced hyphen "Arnhem - Karlsruhe".
        if match == nil, let r = lower.range(of: " - ") {
            match = r
        }

        // Pass 3: Spanish "a", only in a "de/desde …" context to stay unambiguous.
        if match == nil,
           spanishStartContext.contains(where: { rangeOfWord($0, in: lower) != nil }),
           let r = rangeOfWord("a", in: lower) {
            match = r
        }

        guard let m = match else { return nil }
        let left  = String(text[text.startIndex..<m.lowerBound])
        let right = String(text[m.upperBound...])
        return (left, right)
    }

    /// Whole-word range of `word` in `text`, requiring non-letter boundaries on both sides.
    private static func rangeOfWord(_ word: String, in text: String) -> Range<String.Index>? {
        var searchStart = text.startIndex
        while let r = text.range(of: word, range: searchStart..<text.endIndex) {
            let beforeOK = r.lowerBound == text.startIndex
                || !text[text.index(before: r.lowerBound)].isLetter
            let afterOK = r.upperBound == text.endIndex
                || !text[r.upperBound].isLetter
            if beforeOK && afterOK { return r }
            searchStart = r.upperBound
        }
        return nil
    }

    private static func cleanStart(_ raw: String) -> String {
        var words = tokenize(raw)
        // Drop everything up to and including the last start-connector ("van").
        if let idx = words.lastIndex(where: { startConnectors.contains($0.lowercased()) }) {
            words = Array(words[(idx + 1)...])
        }
        // Strip leading activity noise ("Fietsen", "Tour", …).
        while let first = words.first, leadingNoise.contains(first.lowercased()) {
            words.removeFirst()
        }
        return words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    private static func cleanEnd(_ raw: String) -> String {
        var words = tokenize(raw)
        // Cut a trailing "in N dagen / in 5 etappes / over 3 days …" tail: stop at a token
        // that is a known tail-connector ("in", "over", "binnen") directly followed by a number.
        let tailConnectors: Set<String> = ["in", "over", "binnen", "within", "voor", "for"]
        if let cut = words.firstIndex(where: { tailConnectors.contains($0.lowercased()) }) {
            // Only cut if a number appears somewhere after it (e.g. "in 5 dagen").
            let rest = words[(cut + 1)...]
            if rest.contains(where: { $0.contains(where: \.isNumber) }) {
                words = Array(words[..<cut])
            }
        }
        return words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Splits on whitespace and punctuation, dropping empty tokens and standalone commas.
    private static func tokenize(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: " ,;\n\t"))
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }
}
