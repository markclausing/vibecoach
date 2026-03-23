import XCTest
import UIKit
@testable import AIFitnessCoach
import GoogleGenerativeAI

@MainActor
final class ChatViewModelTests: XCTestCase {

    var viewModel: ChatViewModel!
    var mockModel: MockGenerativeModel!
    var mockTokenStore: MockTokenStore!
    var mockNetworkSession: MockNetworkSession!
    var fitnessDataService: FitnessDataService!

    override func setUp() {
        super.setUp()
        // Injecteer de mock AI, zodat we onafhankelijk van Google of netwerk kunnen testen
        mockModel = MockGenerativeModel()
        mockTokenStore = MockTokenStore()
        mockNetworkSession = MockNetworkSession()

        fitnessDataService = FitnessDataService(tokenStore: mockTokenStore, session: mockNetworkSession)

        viewModel = ChatViewModel(aiModel: mockModel, fitnessDataService: fitnessDataService)
    }

    override func tearDown() {
        viewModel = nil
        mockModel = nil
        mockTokenStore = nil
        mockNetworkSession = nil
        fitnessDataService = nil
        super.tearDown()
    }

    /// Test of het versturen van een leeg bericht correct wordt genegeerd
    func testSendMessage_WithEmptyInput_DoesNothing() {
        viewModel.inputText = "    " // Alleen spaties
        viewModel.sendMessage()

        XCTAssertTrue(viewModel.messages.isEmpty, "Een leeg bericht of een bericht met alleen spaties moet niet worden verzonden.")
        XCTAssertFalse(viewModel.isTyping, "De laadindicator mag niet aanspringen.")
    }

    /// Test of het versturen van een correct bericht resulteert in een state-update en een laadindicator.
    func testSendMessage_WithValidInput_AddsMessageAndShowsTypingIndicator() async {
        // Arrange
        let expectedUserText = "Ik heb net 50km gefietst!"
        let expectedAIResponse = "Goed gedaan! Heb je nog gelet op je cadans?"

        viewModel.inputText = expectedUserText
        mockModel.responseToReturn = expectedAIResponse

        // Simuleer een kleine API delay om asynchroon het isTyping flaggetje te kunnen evalueren
        mockModel.delay = 0.1

        // Setup mock activity to avoid missing token error
        try? mockTokenStore.saveToken("valid_token", forService: "StravaToken")
        let activityJson = "[{\"id\":123,\"name\":\"Ride\",\"distance\":50000.0,\"moving_time\":7200,\"average_heartrate\":140.0,\"type\":\"Ride\",\"start_date\":\"2023-10-12T10:00:00Z\"}]"
        mockNetworkSession.dataToReturn = activityJson.data(using: .utf8)
        mockNetworkSession.responseToReturn = HTTPURLResponse(url: URL(string: "https://strava.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)

        // Zorg dat messages leeg is voordat we de test beginnen
        viewModel.messages.removeAll()

        // Actie 1: Verstuur het bericht
        viewModel.sendMessage()

        // Wacht een fractie van een seconde om de async actie te laten starten (isTyping wordt direct gezet, maar fetchAIResponse is async)
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Check 1: De isTyping state moet direct na het triggeren 'true' zijn
        XCTAssertTrue(viewModel.isTyping, "Laadindicator (isTyping) moet op 'true' staan terwijl het AI model verwerkt.")

        // Check 2: Het input bericht staat in de messages array (user bericht toegevoegd)
        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages.first?.text, expectedUserText)
        XCTAssertEqual(viewModel.messages.first?.role, .user)
        XCTAssertTrue(viewModel.inputText.isEmpty, "Het tekstinvoerveld moet weer leeg zijn na het verzenden.")

        // Wacht op de asynchrone completion van Task (simuleert het binnenkomen van het AI antwoord)
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s wachten

        // Check 3: Het antwoord moet zijn toegevoegd
        XCTAssertEqual(viewModel.messages.count, 2, "AI bericht moet zijn toegevoegd aan de lijst.")
        XCTAssertEqual(viewModel.messages.last?.role, .ai)
        XCTAssertEqual(viewModel.messages.last?.text, expectedAIResponse)

        // Check 4: De isTyping moet weer false zijn
        XCTAssertFalse(viewModel.isTyping, "Laadindicator moet weer uit (false) staan nadat de AI reactie succesvol geladen is.")
    }

    /// Test of het meesturen van een afbeelding succesvol in de berichtenlijst (met attached data) belandt,
    /// de input gereset wordt, en we een mock antwoord krijgen.
    func testSendMessage_WithImage_AttachesImageAndClearsInput() async {
        // Arrange
        let expectedUserText = "Kijk naar deze grafiek!"
        let expectedAIResponse = "Interessante hartslagdata! Goed in de D2 zone gebleven."

        // Simuleer een vierkantje rode afbeelding van 10x10 pixels
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let testImage = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }

        viewModel.inputText = expectedUserText
        viewModel.selectedImage = testImage
        mockModel.responseToReturn = expectedAIResponse
        mockModel.delay = 0.1

        // Setup mock activity to avoid missing token error
        try? mockTokenStore.saveToken("valid_token", forService: "StravaToken")
        let activityJson = "[{\"id\":123,\"name\":\"Ride\",\"distance\":50000.0,\"moving_time\":7200,\"average_heartrate\":140.0,\"type\":\"Ride\",\"start_date\":\"2023-10-12T10:00:00Z\"}]"
        mockNetworkSession.dataToReturn = activityJson.data(using: .utf8)
        mockNetworkSession.responseToReturn = HTTPURLResponse(url: URL(string: "https://strava.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)

        viewModel.messages.removeAll()

        // Actie
        viewModel.sendMessage()

        try? await Task.sleep(nanoseconds: 10_000_000)

        // Assert: Input fields reset
        XCTAssertTrue(viewModel.inputText.isEmpty, "Tekst invoer moet leeg zijn.")
        XCTAssertNil(viewModel.selectedImage, "De geselecteerde afbeelding moet gereset (nil) zijn na verzending.")
        XCTAssertTrue(viewModel.isTyping, "Laad indicator aan")

        // Assert: User message bevat de image data
        XCTAssertEqual(viewModel.messages.count, 1)
        let userMessage = viewModel.messages.first
        XCTAssertEqual(userMessage?.role, .user)
        XCTAssertEqual(userMessage?.text, expectedUserText)
        XCTAssertNotNil(userMessage?.attachedImageData, "De user message moet de attached image data (JPEG) bevatten.")

        // Wacht op de asynchrone Vision AI reactie
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Assert: Controleer of we de juiste SDK Part in de payload hebben doorgestuurd
        XCTAssertEqual(mockModel.receivedParts.count, 2, "Er moeten twee parts doorgestuurd zijn: text en image")
        if mockModel.receivedParts.count >= 2 {
            let part2 = mockModel.receivedParts[1]
            // We expect part2 to be ModelContent.Part.data
            // Since it's now explicitly a ModelContent.Part enum, we can just describe it
            let description = String(describing: part2)
            XCTAssertTrue(description.contains("data") || description.contains("Data"), "De tweede part moet een 'data' part zijn met mimetype en bytes.")
            XCTAssertTrue(description.contains("image/jpeg"), "De data part moet een 'image/jpeg' mimetype hebben.")
        }

        // Assert: AI Vision antwoord
        XCTAssertEqual(viewModel.messages.count, 2, "AI response moet zijn binnengekomen na het insturen van de afbeelding.")
        XCTAssertEqual(viewModel.messages.last?.text, expectedAIResponse)
        XCTAssertFalse(viewModel.isTyping, "Klaar met laden.")
    }

    func testSendMessage_WithProfileContext_InjectsContextInPayload() async {
        // Arrange
        let userText = "Wat vind je van mijn vorm?"
        let expectedAIResponse = "Je vorm is fantastisch op basis van je volume!"
        let testProfile = AthleticProfile(peakDistanceInMeters: 50000, peakDurationInSeconds: 7200, averageWeeklyVolumeInSeconds: 14400, daysSinceLastTraining: 2, isRecoveryNeeded: false)

        viewModel.inputText = userText
        mockModel.responseToReturn = expectedAIResponse
        mockModel.delay = 0.1

        viewModel.messages.removeAll()

        // Actie
        viewModel.sendMessage(contextProfile: testProfile)

        try? await Task.sleep(nanoseconds: 200_000_000)

        // Assert: UI bevat alleen de userText, NIET de context prefix
        XCTAssertEqual(viewModel.messages.first?.text, userText, "UI message mag geen prefix bevatten")

        // Assert: Mock model heeft wél de prefix ontvangen in de parts payload
        XCTAssertEqual(mockModel.receivedParts.count, 1)
        if let firstPart = mockModel.receivedParts.first {
            let desc = String(describing: firstPart)
            XCTAssertTrue(desc.contains("CONTEXT ATLEET:"), "Payload string naar AI mist de profiel prefix")
            XCTAssertTrue(desc.contains("50.0 km"), "Payload string mist geparseerde piekprestatie")
            XCTAssertTrue(desc.contains("240 minuten per week"), "Payload string mist wekelijks volume (14400s / 60)")
            XCTAssertTrue(desc.contains(userText), "Payload string mist de daadwerkelijke user vraag")
            XCTAssertFalse(desc.contains("URGENT: De atleet vertoont tekenen van overtraining"), "Warning mag niet inzitten als isRecoveryNeeded false is")
        }
    }

    func testSendMessage_WithRecoveryWarning_InjectsUrgentPrefix() async {
        // Arrange
        let userText = "Wat vind je van mijn vorm?"
        let expectedAIResponse = "Je moet rusten!"
        let testProfile = AthleticProfile(peakDistanceInMeters: 50000, peakDurationInSeconds: 7200, averageWeeklyVolumeInSeconds: 20000, daysSinceLastTraining: 0, isRecoveryNeeded: true)

        viewModel.inputText = userText
        mockModel.responseToReturn = expectedAIResponse
        mockModel.delay = 0.1
        viewModel.messages.removeAll()

        // Actie
        viewModel.sendMessage(contextProfile: testProfile)
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Assert: Mock model heeft de urgent prefix
        XCTAssertEqual(mockModel.receivedParts.count, 1)
        if let firstPart = mockModel.receivedParts.first {
            let desc = String(describing: firstPart)
            XCTAssertTrue(desc.contains("URGENT: De atleet vertoont tekenen van overtraining"), "Urgent waarschuwing mist in payload")
        }
    }

    func testAnalyzeCurrentStatus_Success() async {
        // Arrange
        let expectedAIResponse = "Je hebt een mooie week achter de rug met 2 trainingen!"
        mockModel.responseToReturn = expectedAIResponse
        mockModel.delay = 0.1

        try? mockTokenStore.saveToken("valid_token", forService: "StravaToken")

        // Mock data with 2 workouts in the last 7 days
        let formatter = ISO8601DateFormatter()
        let now = Date()
        let calendar = Calendar.current

        // 1 day ago
        let date1 = calendar.date(byAdding: .day, value: -1, to: now)!
        let start_date_1 = formatter.string(from: date1)

        // 3 days ago
        let date2 = calendar.date(byAdding: .day, value: -3, to: now)!
        let start_date_2 = formatter.string(from: date2)

        let activityJson = """
        [
            {"id":123,"name":"Hardlopen","distance":5000.0,"moving_time":2700,"average_heartrate":150.0,"type":"Run","start_date":"\(start_date_1)"},
            {"id":124,"name":"Wandelen","distance":3000.0,"moving_time":1800,"average_heartrate":100.0,"type":"Walk","start_date":"\(start_date_2)"}
        ]
        """

        let emptyJson = "[]"
        let response = HTTPURLResponse(url: URL(string: "https://strava.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        // Sequence: 1. first page, 2. empty page to break loop
        mockNetworkSession.sequenceResponses = [
            (activityJson.data(using: .utf8)!, response),
            (emptyJson.data(using: .utf8)!, response)
        ]

        viewModel.messages.removeAll()

        // Actie
        viewModel.analyzeCurrentStatus(days: 7)

        // Check loading state immediately
        XCTAssertTrue(viewModel.isFetchingWorkout)

        // Polling loop to wait for the asynchronous operations to complete
        var attempts = 0
        while viewModel.messages.count < 2 && attempts < 50 { // max 5 seconds wait (50 * 0.1s)
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        // Check berichten en eindstatus
        XCTAssertFalse(viewModel.isFetchingWorkout, "Fetching state should be reset to false")
        XCTAssertFalse(viewModel.isTyping, "Typing state should be reset to false")
        XCTAssertEqual(viewModel.messages.count, 2, "There should be exactly 2 messages: the workout context prompt and the AI response")

        let promptText = viewModel.messages.first?.text ?? ""
        XCTAssertEqual(viewModel.messages.first?.role, .user)

        // Check if the prompt contains expected formats
        XCTAssertTrue(promptText.contains("Context voor de AI Coach:"))
        XCTAssertTrue(promptText.contains("Mijn opgeslagen doelen:"))
        XCTAssertTrue(promptText.contains("Hardlopen"))
        XCTAssertTrue(promptText.contains("Wandelen"))
        XCTAssertTrue(promptText.contains("Totale Cumulatieve TRIMP:"))
        XCTAssertTrue(promptText.contains("Rust"))
        XCTAssertTrue(promptText.contains("Instructie voor de Coach:"))

        XCTAssertEqual(viewModel.messages.last?.role, .ai)
        XCTAssertEqual(viewModel.messages.last?.text, expectedAIResponse)
    }

    func testAnalyzeWorkoutWithId_Success() async {
        // Arrange
        let expectedAIResponse = "Snelle lunch run! Goed tempo."
        mockModel.responseToReturn = expectedAIResponse
        mockModel.delay = 0.1

        try? mockTokenStore.saveToken("valid_token", forService: "StravaToken")

        // Specifieke workout JSON (geen array, maar één object)
        let activityJson = "{\"id\":999,\"name\":\"Lunch Run\",\"distance\":5000.0,\"moving_time\":1800,\"average_heartrate\":160.0,\"type\":\"Run\",\"start_date\":\"2023-10-12T10:00:00Z\"}"
        mockNetworkSession.dataToReturn = activityJson.data(using: .utf8)
        let response = HTTPURLResponse(url: URL(string: "https://strava.com/api/v3/activities/999")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        mockNetworkSession.responseToReturn = response

        viewModel.messages.removeAll()

        // Actie
        viewModel.analyzeWorkout(withId: 999)

        // Check loading state immediately
        XCTAssertTrue(viewModel.isFetchingWorkout)

        // Polling loop to wait for the asynchronous operations to complete
        var attempts = 0
        while viewModel.messages.count < 2 && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        // Check berichten en eindstatus
        XCTAssertFalse(viewModel.isFetchingWorkout)
        XCTAssertFalse(viewModel.isTyping)
        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages.first?.role, .user)
        XCTAssertTrue(viewModel.messages.first!.text.contains("Lunch Run"))
        XCTAssertTrue(viewModel.messages.first!.text.contains("5.0 km"))
        XCTAssertTrue(viewModel.messages.first!.text.contains("30 minuten"))
        XCTAssertTrue(viewModel.messages.first!.text.contains("160"))

        XCTAssertEqual(viewModel.messages.last?.role, .ai)
        XCTAssertEqual(viewModel.messages.last?.text, expectedAIResponse)
    }

    func testSkipWorkout_SendsCorrectMessageAndTriggersRecalculation() async {
        // Arrange
        let expectedAIResponse = "Ik heb je schema aangepast en rust ingepland."
        mockModel.responseToReturn = expectedAIResponse
        mockModel.delay = 0.1
        viewModel.messages.removeAll()

        let workoutToSkip = SuggestedWorkout(
            dateOrDay: "Morgen",
            activityType: "Hardlopen",
            suggestedDurationMinutes: 45,
            targetTRIMP: 60,
            description: "Intervals"
        )

        // Actie
        viewModel.skipWorkout(workoutToSkip)

        // Wacht even tot asynchrone taken gestart zijn
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Assert direct na start
        XCTAssertTrue(viewModel.isTyping)
        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages.first?.role, .user)
        let sentMessageText = viewModel.messages.first?.text ?? ""
        XCTAssertTrue(sentMessageText.contains("Ik sla de training 'Hardlopen' op Morgen over. Herbereken de week en schuif de belasting door. BELANGRIJK: Retourneer in je JSON-output altijd het volledige 7-daagse schema (inclusief alle ongewijzigde andere dagen), en niet alleen de aangepaste dag."))

        // Wacht op AI response
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Assert na AI response
        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages.last?.role, .ai)
        XCTAssertEqual(viewModel.messages.last?.text, expectedAIResponse)
        XCTAssertFalse(viewModel.isTyping)
    }

    func testRequestAlternativeWorkout_SendsCorrectMessageAndTriggersRecalculation() async {
        // Arrange
        let expectedAIResponse = "Hier is een fietstraining in plaats van hardlopen."
        mockModel.responseToReturn = expectedAIResponse
        mockModel.delay = 0.1
        viewModel.messages.removeAll()

        let workoutToReplace = SuggestedWorkout(
            dateOrDay: "Zaterdag",
            activityType: "Duurloop",
            suggestedDurationMinutes: 90,
            targetTRIMP: 120,
            description: "Lange langzame duurloop"
        )

        // Actie
        viewModel.requestAlternativeWorkout(workoutToReplace)

        // Wacht even tot asynchrone taken gestart zijn
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Assert direct na start
        XCTAssertTrue(viewModel.isTyping)
        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages.first?.role, .user)
        let sentMessageText = viewModel.messages.first?.text ?? ""
        XCTAssertTrue(sentMessageText.contains("Ik vind de geplande training 'Duurloop' op Zaterdag niet leuk. Geef me een alternatief voor Zaterdag dat een vergelijkbare trainingsprikkel geeft. BELANGRIJK: Retourneer in je JSON-output altijd het volledige 7-daagse schema (inclusief alle ongewijzigde andere dagen), en niet alleen de aangepaste dag."))

        // Wacht op AI response
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Assert na AI response
        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages.last?.role, .ai)
        XCTAssertEqual(viewModel.messages.last?.text, expectedAIResponse)
        XCTAssertFalse(viewModel.isTyping)
    }

    func testSuggestedWorkout_DecodingWithMissingOrStringTRIMP_HandlesGracefully() throws {
        // Test Int TRIMP
        let jsonInt = """
        {
            "dateOrDay": "Maandag",
            "activityType": "Fietsen",
            "suggestedDurationMinutes": 60,
            "targetTRIMP": 55,
            "description": "Rustige rit"
        }
        """
        let dataInt = jsonInt.data(using: .utf8)!
        let workoutInt = try JSONDecoder().decode(SuggestedWorkout.self, from: dataInt)
        XCTAssertEqual(workoutInt.targetTRIMP, 55)

        // Test String TRIMP
        let jsonString = """
        {
            "dateOrDay": "Dinsdag",
            "activityType": "Hardlopen",
            "suggestedDurationMinutes": 30,
            "targetTRIMP": "45",
            "description": "Korte run"
        }
        """
        let dataString = jsonString.data(using: .utf8)!
        let workoutString = try JSONDecoder().decode(SuggestedWorkout.self, from: dataString)
        XCTAssertEqual(workoutString.targetTRIMP, 45)

        // Test Missing TRIMP
        let jsonMissing = """
        {
            "dateOrDay": "Woensdag",
            "activityType": "Rust",
            "suggestedDurationMinutes": 0,
            "description": "Hersteldag"
        }
        """
        let dataMissing = jsonMissing.data(using: .utf8)!
        let workoutMissing = try JSONDecoder().decode(SuggestedWorkout.self, from: dataMissing)
        XCTAssertNil(workoutMissing.targetTRIMP)
    }

    func testAnalyzeCurrentStatus_FallbackToStrava() async {
        // We simuleren dat HealthKit nil teruggeeft, dus we vallen terug op Strava.
        // Omdat we HealthKitManager niet direct kunnen mocken in de huidige opzet zonder een protocol
        // (we gebruiken direct de class), zal HealthKit de `HKSampleQuery` falen in een test environment
        // omdat de permissies niet gevraagd zijn en de test target geen entitlements heeft. Dit gooit een fout
        // en valt keurig terug in de catch block naar Strava.

        // Arrange
        let expectedAIResponse = "Strava Fallback gelukt!"
        mockModel.responseToReturn = expectedAIResponse
        mockModel.delay = 0.1

        try? mockTokenStore.saveToken("valid_token", forService: "StravaToken")

        let formatter = ISO8601DateFormatter()
        let now = Date()
        let calendar = Calendar.current

        let date1 = calendar.date(byAdding: .day, value: -2, to: now)!
        let start_date_1 = formatter.string(from: date1)

        let activityJson = "[{\"id\":123,\"name\":\"Morning Ride\",\"distance\":50000.0,\"moving_time\":7200,\"average_heartrate\":140.0,\"type\":\"Ride\",\"start_date\":\"\(start_date_1)\"}]"
        let emptyJson = "[]"
        let response = HTTPURLResponse(url: URL(string: "https://strava.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        mockNetworkSession.sequenceResponses = [
            (activityJson.data(using: .utf8)!, response),
            (emptyJson.data(using: .utf8)!, response)
        ]

        viewModel.messages.removeAll()

        // Actie
        viewModel.analyzeCurrentStatus(days: 7)

        var attempts = 0
        while viewModel.messages.count < 2 && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        // Assert
        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages.first?.role, .user)
        XCTAssertTrue(viewModel.messages.first!.text.contains("Context voor de AI Coach:")) // Bevestigt dat we de nieuwe prompt gebruiken
        XCTAssertTrue(viewModel.messages.first!.text.contains("Morning Ride"))

        XCTAssertEqual(viewModel.messages.last?.role, .ai)
        XCTAssertEqual(viewModel.messages.last?.text, expectedAIResponse)
    }
}
