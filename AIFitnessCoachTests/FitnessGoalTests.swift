import XCTest
import SwiftData
@testable import AIFitnessCoach

@MainActor
final class FitnessGoalTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        // Configuratie voor in-memory database om geen persisterende data achter te laten
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: FitnessGoal.self, configurations: config)
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        // Opruimen container
        container = nil
        context = nil
    }

    func testCreateFitnessGoal() throws {
        // Arrange
        let title = "Marathon onder 3:30"
        let sportType = "Hardlopen"
        let targetDate = Date().addingTimeInterval(86400 * 30) // +30 dagen

        // Act
        let goal = FitnessGoal(title: title, targetDate: targetDate, sportType: sportType)
        context.insert(goal)

        // Assert
        let descriptor = FetchDescriptor<FitnessGoal>()
        let fetchedGoals = try context.fetch(descriptor)

        XCTAssertEqual(fetchedGoals.count, 1)
        XCTAssertEqual(fetchedGoals.first?.title, title)
        XCTAssertEqual(fetchedGoals.first?.sportType, sportType)
        XCTAssertFalse(fetchedGoals.first!.isCompleted, "Standaard isCompleted zou false moeten zijn")
    }

    func testUpdateFitnessGoal() throws {
        // Arrange
        let goal = FitnessGoal(title: "Oud Doel", targetDate: Date())
        context.insert(goal)

        // Act
        goal.title = "Nieuw Doel"
        goal.isCompleted = true
        try context.save()

        // Assert
        let descriptor = FetchDescriptor<FitnessGoal>()
        let fetchedGoals = try context.fetch(descriptor)

        XCTAssertEqual(fetchedGoals.first?.title, "Nieuw Doel")
        XCTAssertTrue(fetchedGoals.first!.isCompleted)
    }

    func testDeleteFitnessGoal() throws {
        // Arrange
        let goal1 = FitnessGoal(title: "Doel 1", targetDate: Date())
        let goal2 = FitnessGoal(title: "Doel 2", targetDate: Date())
        context.insert(goal1)
        context.insert(goal2)

        // Controleer of ze zijn toegevoegd
        var descriptor = FetchDescriptor<FitnessGoal>()
        var fetchedGoals = try context.fetch(descriptor)
        XCTAssertEqual(fetchedGoals.count, 2)

        // Act
        context.delete(goal1)
        try context.save()

        // Assert
        descriptor = FetchDescriptor<FitnessGoal>()
        fetchedGoals = try context.fetch(descriptor)

        XCTAssertEqual(fetchedGoals.count, 1)
        XCTAssertEqual(fetchedGoals.first?.title, "Doel 2")
    }
}
