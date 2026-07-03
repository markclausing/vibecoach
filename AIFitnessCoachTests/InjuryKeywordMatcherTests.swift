import XCTest
@testable import AIFitnessCoach

/// Word-boundary injury-keyword matching (fix/injury-keyword-word-boundaries).
///
/// Regression source: on-device validation (2026-07-03) surfaced a phantom "Back" symptom tracker
/// on the dashboard because the old bare `contains` matched "rug" inside "terug". These tests lock
/// the must-match / must-not-match matrix per language.
final class InjuryKeywordMatcherTests: XCTestCase {

    // MARK: - Core false positives that started this fix (NL)

    func test_rug_doesNotMatch_terug() {
        XCTAssertFalse(BodyArea.back.matchesInjuryKeyword(in: "Ik wil terug naar mijn oude schema"))
    }

    func test_rug_doesNotMatch_vliegbrug() {
        XCTAssertFalse(BodyArea.back.matchesInjuryKeyword(in: "training bij de vliegbrug"))
    }

    func test_rug_matches_standaloneWord() {
        XCTAssertTrue(BodyArea.back.matchesInjuryKeyword(in: "last van mijn rug"))
    }

    func test_rug_matches_dutchCompound_prefix() {
        // Prefix matching keeps Dutch compounds working — the keyword is at a word boundary.
        XCTAssertTrue(BodyArea.back.matchesInjuryKeyword(in: "ik heb rugpijn na het hardlopen"))
        XCTAssertTrue(BodyArea.back.matchesInjuryKeyword(in: "rugklachten sinds gisteren"))
    }

    // MARK: - "back" is whole-word-only (EN)

    func test_back_doesNotMatch_feedbackComebackSetback() {
        XCTAssertFalse(BodyArea.back.matchesInjuryKeyword(in: "thanks for the feedback"))
        XCTAssertFalse(BodyArea.back.matchesInjuryKeyword(in: "planning my comeback"))
        XCTAssertFalse(BodyArea.back.matchesInjuryKeyword(in: "a small setback this week"))
    }

    func test_back_matches_standaloneAndPhrase() {
        XCTAssertTrue(BodyArea.back.matchesInjuryKeyword(in: "back pain after squats"))
        XCTAssertTrue(BodyArea.back.matchesInjuryKeyword(in: "pain in my lower back"))
    }

    func test_back_hyphenBoundary_isAcceptedResidual() {
        // Documented residual: "back-to-back" has "back" as a hyphen-bounded whole token, so the
        // whole-word rule still matches it. Hyphens are word boundaries by design; this rare
        // English edge is left rather than special-cased. This test pins the known behaviour.
        XCTAssertTrue(BodyArea.back.matchesInjuryKeyword(in: "two back-to-back sessions"))
    }

    // MARK: - "hand" is whole-word-only (NL false-positive family)

    func test_hand_doesNotMatch_handigHandleiding() {
        XCTAssertFalse(BodyArea.hand.matchesInjuryKeyword(in: "dat is wel handig"))
        XCTAssertFalse(BodyArea.hand.matchesInjuryKeyword(in: "lees de handleiding"))
    }

    func test_hand_matches_standaloneWord() {
        XCTAssertTrue(BodyArea.hand.matchesInjuryKeyword(in: "pijn in mijn hand"))
        XCTAssertTrue(BodyArea.hand.matchesInjuryKeyword(in: "hand doet zeer"))
    }

    // MARK: - Other prefix keywords keep matching compounds

    func test_knie_matches_compound() {
        XCTAssertTrue(BodyArea.knee.matchesInjuryKeyword(in: "knieblessure links"))
        XCTAssertTrue(BodyArea.knee.matchesInjuryKeyword(in: "mijn knie is stijf"))
    }

    func test_kuit_matches_compound() {
        XCTAssertTrue(BodyArea.calf.matchesInjuryKeyword(in: "kuitkramp tijdens de run"))
    }

    // MARK: - German (DE)

    func test_de_rucken_matches_butZuruckDoesNot() {
        // "Rücken" (back) must match; "zurück" (back/again) must NOT — the keyword does not start
        // at a word boundary inside "zurück".
        XCTAssertTrue(BodyArea.back.matchesInjuryKeyword(in: "Schmerzen im Rücken"))
        XCTAssertTrue(BodyArea.back.matchesInjuryKeyword(in: "meine ruckenschmerzen"))
        XCTAssertFalse(BodyArea.back.matchesInjuryKeyword(in: "ich will zurück zum Plan"))
    }

    func test_de_knie_matches() {
        XCTAssertTrue(BodyArea.knee.matchesInjuryKeyword(in: "Problem mit dem Knie"))
    }

    // MARK: - Spanish (ES) — accents fold both ways

    func test_es_espalda_matches() {
        XCTAssertTrue(BodyArea.back.matchesInjuryKeyword(in: "dolor de espalda"))
    }

    func test_es_muneca_matches_withAndWithoutAccent() {
        // Diacritic folding: the user may or may not type the tilde.
        XCTAssertTrue(BodyArea.hand.matchesInjuryKeyword(in: "dolor en la muñeca"))
        XCTAssertTrue(BodyArea.hand.matchesInjuryKeyword(in: "dolor en la muneca"))
    }

    func test_es_rodilla_matches() {
        XCTAssertTrue(BodyArea.knee.matchesInjuryKeyword(in: "me duele la rodilla"))
    }

    // MARK: - Case insensitivity

    func test_matching_isCaseInsensitive() {
        XCTAssertTrue(BodyArea.back.matchesInjuryKeyword(in: "RUG doet pijn"))
        XCTAssertTrue(BodyArea.knee.matchesInjuryKeyword(in: "Knie geblesseerd"))
    }

    // MARK: - Multi-occurrence: embedded here, standalone later

    func test_keyword_matchesWhenStandaloneLaterInText() {
        // "rug" is embedded in "terug" first, then appears standalone — must still match.
        XCTAssertTrue(BodyArea.back.matchesInjuryKeyword(in: "ik ga terug, maar mijn rug zeurt"))
    }

    // MARK: - Direct matcher API

    func test_matcher_anyOf_and_single() {
        XCTAssertTrue(InjuryKeywordMatcher.matches(anyOf: ["knie", "rug"], in: "last van mijn rug"))
        XCTAssertFalse(InjuryKeywordMatcher.matches(anyOf: ["knie", "rug"], in: "ik ga terug"))
        XCTAssertTrue(InjuryKeywordMatcher.matches(keyword: "kuit", in: "kuitpijn"))
        XCTAssertFalse(InjuryKeywordMatcher.matches(keyword: "rug", in: "terug"))
    }

    func test_matcher_emptyKeyword_neverMatches() {
        XCTAssertFalse(InjuryKeywordMatcher.matches(keyword: "", in: "anything"))
    }

    // MARK: - Every BodyArea keyword still resolves as a whole word

    func test_allBodyAreas_keywordsResolveAgainstThemselves() {
        // Sanity net: each keyword, on its own, must match its own area. Catches an accidental
        // over-tightening of the matcher (e.g. a keyword that no longer matches even standalone).
        for area in BodyArea.allCases {
            for keyword in area.injuryKeywords {
                XCTAssertTrue(area.matchesInjuryKeyword(in: keyword),
                              "\(area) keyword '\(keyword)' should match itself standalone.")
                XCTAssertTrue(area.matchesInjuryKeyword(in: "last van \(keyword) vandaag"),
                              "\(area) keyword '\(keyword)' should match at a word boundary.")
            }
        }
    }
}
