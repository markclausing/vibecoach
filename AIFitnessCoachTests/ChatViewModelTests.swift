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
        let activityJson = "[{\"id\":123,\"name\":\"Ride\",\"distance\":50000.0,\"moving_time\":7200,\"average_heartrate\":140.0,\"type\":\"Ride\"}]"
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
        let activityJson = "[{\"id\":123,\"name\":\"Ride\",\"distance\":50000.0,\"moving_time\":7200,\"average_heartrate\":140.0,\"type\":\"Ride\"}]"
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

    func testAnalyzeLatestWorkout_Success() async {
        // Arrange
        let expectedAIResponse = "Goed getraind! Je hartslag was netjes."
        mockModel.responseToReturn = expectedAIResponse
        mockModel.delay = 0.1

        try? mockTokenStore.saveToken("valid_token", forService: "StravaToken")
        // moving_time 7200 sec = 120 minuten
        // distance 50000 m = 50.0 km
        let activityJson = "[{\"id\":123,\"name\":\"Morning Ride\",\"distance\":50000.0,\"moving_time\":7200,\"average_heartrate\":140.0,\"type\":\"Ride\"}]"
        mockNetworkSession.dataToReturn = activityJson.data(using: .utf8)
        let response = HTTPURLResponse(url: URL(string: "https://strava.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        mockNetworkSession.responseToReturn = response

        viewModel.messages.removeAll()

        // Actie
        viewModel.analyzeLatestWorkout()

        // Check loading state immediately
        XCTAssertTrue(viewModel.isFetchingWorkout)

        // Wacht tot de data fetch is afgerond en AI verzoek is gestart
        try? await Task.sleep(nanoseconds: 150_000_000)

        // Check of fetching klaar is en we wachten op typen
        XCTAssertFalse(viewModel.isFetchingWorkout)
        XCTAssertTrue(viewModel.isTyping)

        // Wacht op afronding AI verzoek
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Check berichten
        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages.first?.role, .user)
        XCTAssertTrue(viewModel.messages.first!.text.contains("Morning Ride"))
        XCTAssertTrue(viewModel.messages.first!.text.contains("50.0 km"))
        XCTAssertTrue(viewModel.messages.first!.text.contains("120 minuten"))
        XCTAssertTrue(viewModel.messages.first!.text.contains("140"))

        XCTAssertEqual(viewModel.messages.last?.role, .ai)
        XCTAssertEqual(viewModel.messages.last?.text, expectedAIResponse)
        XCTAssertFalse(viewModel.isTyping)
    }
}
