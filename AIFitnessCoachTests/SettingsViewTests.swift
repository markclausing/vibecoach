// We hoeven hier geen UI tests te schrijven voor SwiftUI views,
// maar we kunnen wel de integratie van onze mock store met een ViewModel valideren
// (aangezien de state in SettingsView zit, testen we logischerwijs de TokenStore interface).
import XCTest
@testable import AIFitnessCoach

final class TokenStoreTests: XCTestCase {

    func testMockTokenStoreCRUD() throws {
        // Arrange
        let store = MockTokenStore()

        // Act & Assert (Save & Read)
        try store.saveToken("secret123", forService: "StravaToken")
        let saved = try store.getToken(forService: "StravaToken")
        XCTAssertEqual(saved, "secret123")

        // Act & Assert (Delete)
        try store.deleteToken(forService: "StravaToken")
        let deleted = try store.getToken(forService: "StravaToken")
        XCTAssertNil(deleted)
    }
}
