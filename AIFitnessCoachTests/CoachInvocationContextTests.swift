import XCTest
@testable import AIFitnessCoach

/// Story 65.3: defaults for the `CoachInvocationContext` value type.
final class CoachInvocationContextTests: XCTestCase {

    func testEmpty_HasNilProfileAndEmptyCollections() {
        let ctx = CoachInvocationContext.empty
        XCTAssertNil(ctx.profile)
        XCTAssertTrue(ctx.activeGoals.isEmpty)
        XCTAssertTrue(ctx.activePreferences.isEmpty)
    }

    func testDefaultInit_MatchesEmpty() {
        let ctx = CoachInvocationContext()
        XCTAssertNil(ctx.profile)
        XCTAssertTrue(ctx.activeGoals.isEmpty)
        XCTAssertTrue(ctx.activePreferences.isEmpty)
    }

    func testInit_CarriesProfile() {
        let profile = AthleticProfile(
            peakDistanceInMeters: 10000,
            peakDurationInSeconds: 3000,
            averageWeeklyVolumeInSeconds: 7200,
            daysSinceLastTraining: 1,
            isRecoveryNeeded: false
        )
        let ctx = CoachInvocationContext(profile: profile)
        XCTAssertNotNil(ctx.profile)
        XCTAssertTrue(ctx.activeGoals.isEmpty)
    }
}
