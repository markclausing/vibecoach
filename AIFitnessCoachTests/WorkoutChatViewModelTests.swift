import XCTest
@testable import AIFitnessCoach

/// Epic #70 story 70.3: unit tests voor de workout-chat-orchestratie. Persistentie
/// loopt via callbacks (de view is de SwiftData-eigenaar) — hier testen we het
/// callback-contract, niet de opslag zelf.
@MainActor
final class WorkoutChatViewModelTests: XCTestCase {

    private func makeWorkout() -> WorkoutChatViewModel.WorkoutInfo {
        WorkoutChatViewModel.WorkoutInfo(
            activityID: "9876543210",
            name: "Zondagrit",
            date: Date(timeIntervalSince1970: 1_751_200_000),
            sportRaw: "cycling",
            sessionTypeLabel: "Endurance",
            trimp: 132,
            movingTimeMinutes: 90,
            averageHeartrate: 145,
            rpe: 6,
            mood: "🟢"
        )
    }

    private func makeViewModel(mock: MockGenerativeModel) -> WorkoutChatViewModel {
        mock.delay = 0
        return WorkoutChatViewModel(workout: makeWorkout(), aiModel: mock)
    }

    /// Wacht tot de asynchrone send-Task klaar is (isTyping teruggezet).
    private func waitUntilIdle(_ viewModel: WorkoutChatViewModel,
                               timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while viewModel.isTyping, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(viewModel.isTyping, "Send-flow bleef hangen in isTyping")
    }

    // MARK: - Happy path

    func testSendAppendsUserAndAIMessageAndFiresCallbacks() async throws {
        let mock = MockGenerativeModel()
        mock.responseToReturn = """
        {"reply": "Lekker gereden!", "workoutFacts": [{"text": "Route beviel goed", "category": "route"}]}
        """
        let viewModel = makeViewModel(mock: mock)

        var persisted: [(SenderRole, String)] = []
        var detectedFacts: [WorkoutChatResponseParser.DistilledFact] = []
        viewModel.onMessagePersisted = { role, text, _ in persisted.append((role, text)) }
        viewModel.onNewFactsDetected = { detectedFacts = $0 }

        viewModel.sendMessage("Mooie route vandaag om de plas!", existingFactTexts: [])
        try await waitUntilIdle(viewModel)

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages.first?.role, .user)
        XCTAssertEqual(viewModel.messages.last?.role, .ai)
        XCTAssertEqual(viewModel.messages.last?.text, "Lekker gereden!")

        XCTAssertEqual(persisted.count, 2, "User-bericht én AI-reply moeten gepersisteerd worden")
        XCTAssertEqual(persisted.first?.0, .user)
        XCTAssertEqual(persisted.last?.0, .ai)

        XCTAssertEqual(detectedFacts.count, 1)
        XCTAssertEqual(detectedFacts.first?.category, .route)
    }

    /// De prompt moet de workout-data, onthouden feiten en de vraag bevatten —
    /// de lokale [WORKOUT DATA]/[REMEMBERED FACTS]-markers (§13 both-sides).
    func testPromptContainsWorkoutDataFactsAndQuestion() async throws {
        let mock = MockGenerativeModel()
        mock.responseToReturn = #"{"reply": "Oké."}"#
        let viewModel = makeViewModel(mock: mock)

        viewModel.sendMessage("Hoe was mijn pacing?", existingFactTexts: ["Slecht geslapen voor deze rit"])
        try await waitUntilIdle(viewModel)

        guard case .text(let prompt)? = mock.receivedParts.first else {
            return XCTFail("Verwachtte één tekst-part")
        }
        XCTAssertTrue(prompt.contains("[WORKOUT DATA]"))
        XCTAssertTrue(prompt.contains("Zondagrit"))
        XCTAssertTrue(prompt.contains("TRIMP 132"))
        XCTAssertTrue(prompt.contains("RPE 6/10"))
        XCTAssertTrue(prompt.contains("[REMEMBERED FACTS]"))
        XCTAssertTrue(prompt.contains("Slecht geslapen voor deze rit"))
        XCTAssertTrue(prompt.contains("user: Hoe was mijn pacing?"))
    }

    func testLoadHistorySeedsOnceAndIsIdempotent() {
        let viewModel = makeViewModel(mock: MockGenerativeModel())
        let entries: [(role: SenderRole, text: String, timestamp: Date)] = [
            (.user, "Voelde zwaar.", Date(timeIntervalSince1970: 1_751_100_000)),
            (.ai, "Dat kan door de warmte komen.", Date(timeIntervalSince1970: 1_751_100_060))
        ]
        viewModel.loadHistory(entries)
        viewModel.loadHistory(entries) // re-appear van de view mag niet dupliceren

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages.first?.text, "Voelde zwaar.")
    }

    // MARK: - Fallback & fouten

    /// Niet-overload-fouten gaan als transiente fout-bubble naar de UI en worden
    /// níét gepersisteerd. (Het overload-waterfall-pad zelf is hier niet te isoleren:
    /// `fallbackModel()` bouwt een echte client, en het pad is gedeeld met
    /// `ChatViewModel` — daar al gedekt in `ChatViewModelTests`.)
    func testErrorAppendsTransientErrorBubble_notPersisted() async throws {
        let mock = MockGenerativeModel()
        mock.errorToThrow = AIProviderError.authenticationFailed
        let viewModel = makeViewModel(mock: mock)

        var persisted: [(SenderRole, String)] = []
        viewModel.onMessagePersisted = { role, text, _ in persisted.append((role, text)) }

        viewModel.sendMessage("Test", existingFactTexts: [])
        try await waitUntilIdle(viewModel)

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertTrue(viewModel.messages.last?.isError ?? false)
        XCTAssertEqual(persisted.count, 1, "Alleen het user-bericht wordt gepersisteerd, de fout-bubble niet")
        XCTAssertEqual(persisted.first?.0, .user)
    }

    func testEmptyInputIsIgnored() {
        let viewModel = makeViewModel(mock: MockGenerativeModel())
        viewModel.sendMessage("   \n", existingFactTexts: [])
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertFalse(viewModel.isTyping)
    }

    /// Zonder facts-array in de response géén callback (geen lege-array-spam).
    func testNoFactsMeansNoFactsCallback() async throws {
        let mock = MockGenerativeModel()
        mock.responseToReturn = #"{"reply": "Prima!", "workoutFacts": []}"#
        let viewModel = makeViewModel(mock: mock)

        var callbackFired = false
        viewModel.onNewFactsDetected = { _ in callbackFired = true }

        viewModel.sendMessage("Ging goed.", existingFactTexts: [])
        try await waitUntilIdle(viewModel)

        XCTAssertFalse(callbackFired)
        XCTAssertEqual(viewModel.messages.last?.text, "Prima!")
    }
}
