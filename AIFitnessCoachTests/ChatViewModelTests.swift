import XCTest
@testable import AIFitnessCoach
import GoogleGenerativeAI

@MainActor
final class ChatViewModelTests: XCTestCase {

    var viewModel: ChatViewModel!
    var mockModel: MockGenerativeModel!

    override func setUp() {
        super.setUp()
        // Injecteer de mock AI, zodat we onafhankelijk van Google of netwerk kunnen testen
        mockModel = MockGenerativeModel()
        viewModel = ChatViewModel(aiModel: mockModel)
    }

    override func tearDown() {
        viewModel = nil
        mockModel = nil
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

        // Zorg dat messages leeg is voordat we de test beginnen
        viewModel.messages.removeAll()

        // Actie 1: Verstuur het bericht
        viewModel.sendMessage()

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
}
