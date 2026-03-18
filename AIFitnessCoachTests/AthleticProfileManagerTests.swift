import XCTest
import SwiftData
@testable import AIFitnessCoach

@MainActor
final class AthleticProfileManagerTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    var manager: AthleticProfileManager!

    override func setUp() {
        super.setUp()
        // Creëer een in-memory configuratie voor SwiftData zodat tests lokaal en snel blijven
        let schema = Schema([ActivityRecord.self, FitnessGoal.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)

        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
            context = container.mainContext
        } catch {
            XCTFail("Kon in-memory ModelContainer niet aanmaken: \(error)")
        }

        manager = AthleticProfileManager()
    }

    override func tearDown() {
        container = nil
        context = nil
        manager = nil
        super.tearDown()
    }

    func testCalculateProfile_WithNoData_ReturnsNil() throws {
        // Act
        let profile = try manager.calculateProfile(context: context)

        // Assert
        XCTAssertNil(profile, "Profiel zou nil moeten zijn als er geen data is")
    }

    func testCalculateProfile_WithData_CalculatesCorrectly() throws {
        // Arrange
        let now = Date()
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        let threeWeeksAgo = Calendar.current.date(byAdding: .day, value: -21, to: now)!
        let fiveWeeksAgo = Calendar.current.date(byAdding: .day, value: -35, to: now)!

        // Activiteiten toevoegen
        // 1. Recente activiteit: 5 km in 1800 sec
        let act1 = ActivityRecord(id: 1, name: "Run 1", distance: 5000, movingTime: 1800, averageHeartrate: 150, type: "Run", startDate: twoDaysAgo)
        // 2. Activiteit 3 weken geleden: 10 km in 3600 sec (Piek afstand en tijd!)
        let act2 = ActivityRecord(id: 2, name: "Run 2", distance: 10000, movingTime: 3600, averageHeartrate: 155, type: "Run", startDate: threeWeeksAgo)
        // 3. Oude activiteit buiten de 4-weken window: 3 km in 1200 sec
        let act3 = ActivityRecord(id: 3, name: "Run 3", distance: 3000, movingTime: 1200, averageHeartrate: 145, type: "Run", startDate: fiveWeeksAgo)

        context.insert(act1)
        context.insert(act2)
        context.insert(act3)
        try context.save()

        // Act
        let profile = try manager.calculateProfile(context: context)

        // Assert
        XCTAssertNotNil(profile)

        // Piekprestatie moet gebaseerd zijn op alle activiteiten
        XCTAssertEqual(profile?.peakDistanceInMeters, 10000)
        XCTAssertEqual(profile?.peakDurationInSeconds, 3600)

        // Wekelijks volume van afgelopen 4 weken:
        // Totaal in sec: act1 (1800) + act2 (3600) = 5400 seconden
        // Gemiddeld per week: 5400 / 4 = 1350 seconden
        XCTAssertEqual(profile?.averageWeeklyVolumeInSeconds, 1350)

        // Dagen sinds laatste training: act1 was 2 dagen geleden
        // Omdat de precieze tijd op de milliseconde kan verschillen en Calendar kan afronden, checken we of het 2 of 1 is
        XCTAssertTrue((1...2).contains(profile!.daysSinceLastTraining), "Days since last training should be around 2")
    }
}
