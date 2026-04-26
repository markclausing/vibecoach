import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Unit tests voor `StravaStreamIngestService`. Borgt:
///  • zip-helper combineert stream-data met timestamps correct (incl. mismatched-length-edge)
///  • full-flow ingest schrijft idempotent naar de store met de juiste UUID-koppeling
///  • ontbrekende streams (geen power, geen cadence) resulteren niet in crashes
@MainActor
final class StravaStreamIngestServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var store: WorkoutSampleStore!
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: WorkoutSample.self, configurations: config)
        store = WorkoutSampleStore(modelContainer: container)
    }

    override func tearDownWithError() throws {
        container = nil
        store = nil
    }

    // MARK: zip-helper

    func testZipCombinesStreamWithTimestamps() {
        let stream = StravaStream(data: [120, 130, 140])
        let times = [baseDate, baseDate.addingTimeInterval(5), baseDate.addingTimeInterval(10)]

        let result = StravaStreamIngestService.zip(stream: stream, with: times)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].value, 120)
        XCTAssertEqual(result[2].timestamp, baseDate.addingTimeInterval(10))
    }

    func testZipHandlesMismatchedLengthsGracefully() {
        // Stream langer dan timestamps — pak het minimum, niet crashen.
        let stream = StravaStream(data: [100, 110, 120, 130])
        let times = [baseDate, baseDate.addingTimeInterval(5)]

        let result = StravaStreamIngestService.zip(stream: stream, with: times)
        XCTAssertEqual(result.count, 2,
                       "Bij mismatched lengtes pakken we het minimum — voorkomt index-out-of-range")
    }

    func testZipReturnsEmptyForNilStream() {
        let result = StravaStreamIngestService.zip(stream: nil, with: [baseDate])
        XCTAssertTrue(result.isEmpty)
    }

    func testZipReturnsEmptyForEmptyStream() {
        let result = StravaStreamIngestService.zip(stream: StravaStream(data: []), with: [baseDate])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: Full ingest-flow

    func testIngestStoresSamplesUnderDeterministicUUID() async throws {
        // Stream van 30 seconden, watts + heartrate alleen.
        let times: [Double] = (0..<30).map { Double($0) } // seconden offsets
        let watts: [Double] = (0..<30).map { 200 + Double($0) }
        let hr:    [Double] = (0..<30).map { 140 + Double($0 % 10) }

        let streamSet = StravaStreamSet(
            time: StravaStream(data: times),
            watts: StravaStream(data: watts),
            cadence: nil,
            heartrate: StravaStream(data: hr),
            velocity_smooth: nil
        )

        let service = StravaStreamIngestService()
        try await service.ingestStreams(
            streamSet,
            activityID: "12345678901",
            startDate: baseDate,
            durationSeconds: 30,
            into: store
        )

        let expectedUUID = UUID.deterministic(fromStravaID: "12345678901")
        let count = try await store.sampleCount(forWorkoutUUID: expectedUUID)
        XCTAssertGreaterThan(count, 0, "Samples moeten worden opgeslagen onder de Strava-deterministic UUID")
    }

    func testIngestIsIdempotentOnRerun() async throws {
        let times: [Double] = (0..<10).map { Double($0) }
        let watts: [Double] = (0..<10).map { 200 + Double($0) }

        let streamSet = StravaStreamSet(
            time: StravaStream(data: times),
            watts: StravaStream(data: watts),
            cadence: nil, heartrate: nil, velocity_smooth: nil
        )

        let service = StravaStreamIngestService()
        try await service.ingestStreams(streamSet, activityID: "999", startDate: baseDate, durationSeconds: 10, into: store)
        let firstCount = try await store.sampleCount(forWorkoutUUID: UUID.deterministic(fromStravaID: "999"))

        // Opnieuw ingesten — moet vervangen, niet verdubbelen.
        try await service.ingestStreams(streamSet, activityID: "999", startDate: baseDate, durationSeconds: 10, into: store)
        let secondCount = try await store.sampleCount(forWorkoutUUID: UUID.deterministic(fromStravaID: "999"))

        XCTAssertEqual(firstCount, secondCount,
                       "replaceSamples moet idempotent zijn — geen duplicaten bij hersync")
    }

    func testIngestSkipsWhenNoTimeStream() async throws {
        // Zonder time-stream kunnen we niets aan tijdstippen koppelen — gracefully skip.
        let streamSet = StravaStreamSet(
            time: nil,
            watts: StravaStream(data: [200, 210]),
            cadence: nil, heartrate: nil, velocity_smooth: nil
        )
        let service = StravaStreamIngestService()
        try await service.ingestStreams(streamSet, activityID: "777", startDate: baseDate, durationSeconds: 60, into: store)

        let count = try await store.sampleCount(forWorkoutUUID: UUID.deterministic(fromStravaID: "777"))
        XCTAssertEqual(count, 0, "Geen time-stream → geen samples — geen crash")
    }

    func testIngestHandlesPartialStreams() async throws {
        // Alleen power, geen HR/cadence/speed — moet werken zonder crash.
        let times: [Double] = (0..<15).map { Double($0) }
        let watts: [Double] = (0..<15).map { _ in 250.0 }
        let streamSet = StravaStreamSet(
            time: StravaStream(data: times),
            watts: StravaStream(data: watts),
            cadence: nil, heartrate: nil, velocity_smooth: nil
        )
        let service = StravaStreamIngestService()
        try await service.ingestStreams(streamSet, activityID: "555", startDate: baseDate, durationSeconds: 15, into: store)

        let count = try await store.sampleCount(forWorkoutUUID: UUID.deterministic(fromStravaID: "555"))
        XCTAssertGreaterThan(count, 0,
                             "Power-only stream moet alsnog samples opleveren met heartRate=nil/cadence=nil/speed=nil")
    }
}
