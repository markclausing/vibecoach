import XCTest
import SwiftData
@testable import AIFitnessCoach

/// Story 65.3 safety net.
///
/// Pins the exact byte output of the assembled coach context-prefix for a fixed
/// fixture context. Written against the pre-refactor `ChatViewModel.buildContextPrefix`
/// (driven through `sendMessage` → captured from the mock model) and kept
/// byte-identical while `buildContextPrefix`/`getStoredPlanString`/
/// `generateCurrentStatusPrompt` are extracted into `CoachPromptAssembler`.
///
/// The context-block branches (weather/patterns/history/blueprint/…) are pinned
/// comprehensively in `CoachPromptAssemblerTests`; this test locks the core
/// assembly wiring + two raw pass-through insertions + the profileUpdateNote
/// clear-after-use behaviour through the real `ChatViewModel` seam.
@MainActor
final class CoachPromptFixtureTests: XCTestCase {

    private var viewModel: ChatViewModel!
    private var mockModel: MockGenerativeModel!
    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        mockModel = MockGenerativeModel()
        mockModel.responseToReturn = "ok"
        mockModel.delay = 0

        // Strava data source so the real HealthKitManager is never touched.
        UserDefaults.standard.set(DataSource.strava.rawValue, forKey: "selectedDataSource")
        // Clear any threshold state leaking from other tests so the
        // [TRAINING THRESHOLDS] block stays empty (deterministic).
        for key in ["vibecoach_maxHeartRate.v1", "vibecoach_restingHeartRate.v1",
                    "vibecoach_lactateThresholdHR.v1", "vibecoach_ftp.v1"] {
            UserDefaults.standard.removeObject(forKey: key)
        }

        // In-memory SwiftData store so configure(with:) can create the context cache.
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        container = try! ModelContainer(for: CoachContextCache.self, configurations: config)

        viewModel = ChatViewModel(aiModel: mockModel)
        viewModel.configure(with: container.mainContext)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "selectedDataSource")
        viewModel = nil
        mockModel = nil
        container = nil
        super.tearDown()
    }

    func testContextPrefix_FixtureIsByteIdentical() async {
        // Populate deterministic context.
        viewModel.cacheVibeScoreUnavailable()
        viewModel.cacheIntentExecution("[INTENT-EXECUTION FIXTURE]\n\n")
        viewModel.profileUpdateNote = "[PROFILE UPDATE FIXTURE]"

        let profile = AthleticProfile(
            peakDistanceInMeters: 50000,
            peakDurationInSeconds: 7200,
            averageWeeklyVolumeInSeconds: 14400,
            daysSinceLastTraining: 2,
            isRecoveryNeeded: false
        )

        viewModel.messages.removeAll()
        viewModel.sendMessage("Hallo coach", contextProfile: profile)

        // Wait for the async fetch Task to hand the payload to the mock.
        var attempts = 0
        while mockModel.receivedParts.isEmpty && attempts < 200 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            attempts += 1
        }

        guard let firstPart = mockModel.receivedParts.first,
              case let .text(payload) = firstPart else {
            XCTFail("Expected a text part in the payload sent to the model")
            return
        }

        let dateString = AppDateFormatters.fixed("yyyy-MM-dd").string(from: Date())

        let expected =
            "[CURRENT DATE: Today is \(dateString). Use this for your calculations around 'expirationDate'.]\n\n"
            + "[RECOVERY STATUS TODAY: No objective biometric data is available (the user probably didn't wear the Apple Watch overnight). Rely fully on the Symptom Tracker scores and the planned goals. NEVER use phrases like 'I can see from your HRV that...' or 'Your biometrics indicate...'. Instead say: 'Because we have no Watch data today, we'll go by your own feeling and the entered scores.']\n\n"
            + "[INTENT-EXECUTION FIXTURE]\n\n"
            + "[PROFILE UPDATE FIXTURE]\n\n"
            + "[ATHLETE CONTEXT: Has a peak performance of 50.0 km in 120 minutes. Trains on average 240 minutes per week (avg. last 4 weeks), and last trained 2 days ago. Take this into account in your analysis about recovery and performance.]\n\n"
            + "[QUESTION]: "
            + "Hallo coach"

        XCTAssertEqual(payload, expected)

        // profileUpdateNote is consumed on build and cleared for the next turn.
        XCTAssertEqual(viewModel.profileUpdateNote, "")
    }
}
