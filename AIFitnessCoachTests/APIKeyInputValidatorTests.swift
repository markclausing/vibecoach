import XCTest
@testable import AIFitnessCoach

/// Epic #62 story 62.2 — paste sanitisation + wrong-provider prefix detection.
final class APIKeyInputValidatorTests: XCTestCase {

    // MARK: - sanitize

    func testSanitizeTrimsSurroundingWhitespaceAndNewlines() {
        XCTAssertEqual(APIKeyInputValidator.sanitize("  sk-abc123\n"), "sk-abc123")
    }

    func testSanitizeRemovesEmbeddedWhitespace() {
        // A line-wrapped paste can carry an internal newline/space — keys never contain one.
        XCTAssertEqual(APIKeyInputValidator.sanitize("sk-ab\nc1 23"), "sk-abc123")
    }

    func testSanitizeLeavesACleanKeyUnchanged() {
        XCTAssertEqual(APIKeyInputValidator.sanitize("AIzaSyClean"), "AIzaSyClean")
    }

    // MARK: - inferredProvider

    func testAnthropicPrefixBeatsOpenAIPrefix() {
        // sk-ant- must be checked before the broader sk-.
        XCTAssertEqual(APIKeyInputValidator.inferredProvider(forKey: "sk-ant-abc"), .anthropic)
    }

    func testOpenAIPrefix() {
        XCTAssertEqual(APIKeyInputValidator.inferredProvider(forKey: "sk-proj-abc"), .openAI)
    }

    func testGeminiPrefix() {
        XCTAssertEqual(APIKeyInputValidator.inferredProvider(forKey: "AIzaSyABC"), .gemini)
    }

    func testUnknownPrefixReturnsNil() {
        // Mistral keys carry no standard prefix — never guessed.
        XCTAssertNil(APIKeyInputValidator.inferredProvider(forKey: "abc123def456"))
    }

    // MARK: - isProviderMismatch

    func testOpenAIKeyUnderGeminiIsMismatch() {
        XCTAssertTrue(APIKeyInputValidator.isProviderMismatch(key: "sk-abc", selected: .gemini))
    }

    func testGeminiKeyUnderGeminiIsNoMismatch() {
        XCTAssertFalse(APIKeyInputValidator.isProviderMismatch(key: "AIzaSyABC", selected: .gemini))
    }

    func testUnknownKeyNeverMismatches() {
        // No false positive for an unrecognised (e.g. Mistral) key under any provider.
        XCTAssertFalse(APIKeyInputValidator.isProviderMismatch(key: "randomkey", selected: .mistral))
        XCTAssertFalse(APIKeyInputValidator.isProviderMismatch(key: "randomkey", selected: .gemini))
    }

    func testMismatchToleratesSurroundingWhitespace() {
        XCTAssertTrue(APIKeyInputValidator.isProviderMismatch(key: "  sk-ant-abc\n", selected: .openAI))
    }
}
