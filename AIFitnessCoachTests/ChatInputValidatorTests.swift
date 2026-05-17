import XCTest
@testable import AIFitnessCoach

/// Epic #51-A4: borgt dat de input-clamp en de counter-zichtbaarheid zich
/// houden aan de afgesproken drempels. De pure-Swift validator is AppStorage-
/// vrij — caller injecteert de drempels desgewenst zelf, zodat we ook
/// alternatieve limieten kunnen testen.
final class ChatInputValidatorTests: XCTestCase {

    // MARK: - Clamp

    func testClampNoOpUnderLimit() {
        let result = ChatInputValidator.clamp("hallo")
        XCTAssertEqual(result.clamped, "hallo")
        XCTAssertFalse(result.didClamp)
    }

    func testClampExactlyAtLimitIsNoOp() {
        let text = String(repeating: "x", count: ChatInputValidator.maxLength)
        let result = ChatInputValidator.clamp(text)
        XCTAssertEqual(result.clamped.count, ChatInputValidator.maxLength)
        XCTAssertFalse(result.didClamp, "Precies op de limiet hoeft de paste niet gemarkeerd te worden.")
    }

    func testClampTruncatesAboveLimit() {
        let text = String(repeating: "x", count: ChatInputValidator.maxLength + 100)
        let result = ChatInputValidator.clamp(text)
        XCTAssertEqual(result.clamped.count, ChatInputValidator.maxLength)
        XCTAssertTrue(result.didClamp)
    }

    func testClampRespectsCustomLimit() {
        let result = ChatInputValidator.clamp("abcdef", limit: 3)
        XCTAssertEqual(result.clamped, "abc")
        XCTAssertTrue(result.didClamp)
    }

    func testClampWithZeroLimitProducesEmpty() {
        let result = ChatInputValidator.clamp("abc", limit: 0)
        XCTAssertEqual(result.clamped, "")
        XCTAssertTrue(result.didClamp)
    }

    func testClampWithNegativeLimitTreatedAsZero() {
        let result = ChatInputValidator.clamp("abc", limit: -5)
        XCTAssertEqual(result.clamped, "")
        XCTAssertTrue(result.didClamp, "Negatieve limiet mag nooit silently 'pass-through' worden.")
    }

    // MARK: - Counter

    func testCounterHiddenWellBelowThreshold() {
        XCTAssertFalse(ChatInputValidator.shouldShowCounter("hallo"))
    }

    func testCounterHiddenJustBelowThreshold() {
        let text = String(repeating: "x", count: ChatInputValidator.counterThreshold - 1)
        XCTAssertFalse(ChatInputValidator.shouldShowCounter(text))
    }

    func testCounterShownAtThreshold() {
        let text = String(repeating: "x", count: ChatInputValidator.counterThreshold)
        XCTAssertTrue(ChatInputValidator.shouldShowCounter(text))
    }

    func testCounterShownAboveThreshold() {
        let text = String(repeating: "x", count: ChatInputValidator.counterThreshold + 100)
        XCTAssertTrue(ChatInputValidator.shouldShowCounter(text))
    }

    func testCounterRespectsCustomThreshold() {
        XCTAssertTrue(ChatInputValidator.shouldShowCounter("abcde", threshold: 5))
        XCTAssertFalse(ChatInputValidator.shouldShowCounter("abcd", threshold: 5))
    }
}
