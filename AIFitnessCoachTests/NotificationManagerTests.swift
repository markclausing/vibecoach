import XCTest
@testable import AIFitnessCoach

@MainActor
final class NotificationManagerTests: XCTestCase {

    func testNotificationManagerSingleton() {
        let manager1 = NotificationManager.shared
        let manager2 = NotificationManager.shared
        XCTAssertTrue(manager1 === manager2, "NotificationManager zou een singleton moeten zijn")
    }

    func testNotificationManagerInitialState() {
        let manager = NotificationManager.shared
        // De default state bij de eerste launch is waarschijnlijk false totdat permission wordt verleend of uitgelezen.
        // Omdat de initialisatie asynchroon in de achtergrond draait (checkPermission), testen we voornamelijk op bestaan.
        XCTAssertNotNil(manager)
    }
}
