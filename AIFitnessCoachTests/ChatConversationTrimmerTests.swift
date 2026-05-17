import XCTest
@testable import AIFitnessCoach

/// Epic #51-A3: borgt dat lange gesprekken bij een drempel splitsen in een
/// archief + zichtbare staart en dat korte gesprekken ongemoeid blijven.
/// De trimmer is generic — we testen met `[Int]` om los te staan van
/// `ChatMessage` (en zo van de SwiftData-/SwiftUI-keten die die meebrengt).
final class ChatConversationTrimmerTests: XCTestCase {

    // MARK: - Geen archivering nodig

    func testEmptyMessagesReturnsNothing() {
        let result = ChatConversationTrimmer.split(messages: [Int](), visibleLimit: 10)
        XCTAssertTrue(result.archived.isEmpty)
        XCTAssertTrue(result.visible.isEmpty)
    }

    func testBelowLimitReturnsAllVisible() {
        let messages = Array(1...10)
        let result = ChatConversationTrimmer.split(messages: messages, visibleLimit: 50)
        XCTAssertTrue(result.archived.isEmpty)
        XCTAssertEqual(result.visible, messages)
    }

    func testExactlyAtLimitReturnsAllVisible() {
        let messages = Array(1...50)
        let result = ChatConversationTrimmer.split(messages: messages, visibleLimit: 50)
        XCTAssertTrue(result.archived.isEmpty, "Op de limiet zelf nog niets archiveren.")
        XCTAssertEqual(result.visible, messages)
    }

    // MARK: - Archivering boven drempel

    func testOneAboveLimitArchivesOldest() {
        let messages = Array(1...51)
        let result = ChatConversationTrimmer.split(messages: messages, visibleLimit: 50)
        XCTAssertEqual(result.archived, [1])
        XCTAssertEqual(result.visible, Array(2...51))
    }

    func testManyAboveLimitArchivesFront() {
        let messages = Array(1...100)
        let result = ChatConversationTrimmer.split(messages: messages, visibleLimit: 50)
        XCTAssertEqual(result.archived, Array(1...50))
        XCTAssertEqual(result.visible, Array(51...100))
    }

    // MARK: - Edge cases

    func testZeroLimitArchivesEverything() {
        let messages = Array(1...10)
        let result = ChatConversationTrimmer.split(messages: messages, visibleLimit: 0)
        XCTAssertEqual(result.archived, messages, "Zero-limit: alles wordt opzij gezet.")
        XCTAssertTrue(result.visible.isEmpty)
    }

    func testDefaultLimitIsFifty() {
        XCTAssertEqual(ChatConversationTrimmer.defaultVisibleLimit, 50)
    }
}
