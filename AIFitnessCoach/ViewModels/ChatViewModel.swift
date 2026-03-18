import Foundation
import SwiftUI
import Combine
import GoogleGenerativeAI

/// De viewmodel die de status van de chat bijhoudt en acties afhandelt.
@MainActor
class ChatViewModel: ObservableObject {
    /// Lijst van opgeslagen chatberichten.
    @Published var messages: [ChatMessage] = []
    /// De huidige tekstinput van de gebruiker.
    @Published var inputText: String = ""
    /// Een eventuele geselecteerde afbeelding uit de galerij.
    @Published var selectedImage: UIImage? = nil
    /// True als de applicatie wacht op een reactie van de AI.
    @Published var isTyping: Bool = false

    /// True als we op dit moment Strava data aan het ophalen zijn via de expliciete knop.
    @Published var isFetchingWorkout: Bool = false

    /// Het protocol waartegen we de AI-verzoeken uitvoeren.
    /// Dit maakt Dependency Injection (DI) mogelijk voor unit tests.
    private let model: GenerativeModelProtocol

    /// Service voor externe API calls (Sprint 4.2).
    private let fitnessDataService: FitnessDataService

    /// Initialiseert de `ChatViewModel`.
    ///
    /// - Parameter aiModel: De AI-dienst die gebruikt moet worden.
    ///             Wanneer niets wordt meegegeven, wordt standaard de
    ///             `RealGenerativeModel` (die met Google API praat) gebruikt.
    init(aiModel: GenerativeModelProtocol? = nil, fitnessDataService: FitnessDataService = FitnessDataService()) {
        self.fitnessDataService = fitnessDataService
        if let providedModel = aiModel {
            self.model = providedModel
        } else {
            let systemInstruction = "Jij bent een motiverende, deskundige persoonlijke fitness- en wielrencoach. Je helpt de gebruiker met het analyseren van trainingen en data van Strava/Intervals.icu. Houd je antwoorden beknopt, direct, deskundig en enthousiast."
            let googleModel = GenerativeModel(
                name: "gemini-3.1-pro-preview",
                apiKey: Secrets.geminiAPIKey,
                systemInstruction: ModelContent(role: "system", parts: [.text(systemInstruction)])
            )
            self.model = RealGenerativeModel(model: googleModel)
        }
    }

    /// Verwijdert de geselecteerde afbeelding uit de invoer.
    func clearImage() {
        self.selectedImage = nil
    }

    /// Verstuurt het huidige tekstveld en/of de geselecteerde afbeelding.
    func sendMessage() {
        let textToSend = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Als de gebruiker een afbeelding heeft geselecteerd, verkleinen we hem meteen naar een payload-vriendelijk formaat.
        let imageToSend = selectedImage?.downsample(to: 2048.0)

        guard !textToSend.isEmpty || imageToSend != nil else { return }

        // 1. Maak bericht aan van gebruiker (converteer UIImage naar datatypes na de resize)
        let imageData = imageToSend?.jpegData(compressionQuality: 0.8)
        let userMessage = ChatMessage(role: .user, text: textToSend, attachedImageData: imageData)

        // 2. Voeg toe aan UI en reset velden
        messages.append(userMessage)

        isTyping = true

        // 3. Haal AI reactie op
        fetchAIResponse(for: textToSend, image: imageToSend)

        inputText = ""
        clearImage()
    }

    /// Haalt de laatste Strava activiteit op, formatteert deze als een Nederlandse prompt
    /// en stuurt deze naar de AI-coach voor analyse.
    func analyzeLatestWorkout() {
        guard !isFetchingWorkout else { return }
        isFetchingWorkout = true

        Task {
            do {
                let activityData = try await fitnessDataService.fetchLatestActivity()

                guard let activity = activityData else {
                    Task { @MainActor in
                        messages.append(ChatMessage(role: .ai, text: "Ik kon geen recente trainingen vinden op je Strava account."))
                        isFetchingWorkout = false
                    }
                    return
                }

                // Converteer eenheden
                let distanceKm = String(format: "%.1f", activity.distance / 1000.0)
                let timeMinutes = activity.moving_time / 60
                let heartRateStr = activity.average_heartrate != nil ? "\(Int(activity.average_heartrate!))" : "onbekend"

                // Formatteer de context prompt
                let prompt = "Hier is de data van mijn laatste training via Strava. Naam: \(activity.name), Afstand: \(distanceKm) km, Tijd: \(timeMinutes) minuten, Gem. Hartslag: \(heartRateStr). Kan je deze training kort analyseren als mijn coach en vertellen of ik goed bezig ben?"

                Task { @MainActor in
                    // Voeg de prompt toe als een gebruikersbericht zodat de chatgeschiedenis klopt
                    messages.append(ChatMessage(role: .user, text: prompt))

                    isTyping = true
                    isFetchingWorkout = false

                    fetchAIResponse(for: prompt, image: nil)
                }

            } catch let error as FitnessDataError {
                var errorMsg = "Fout bij ophalen van Strava data: "
                switch error {
                case .missingToken:
                    errorMsg += "Je bent niet ingelogd op Strava. Ga naar instellingen om te koppelen."
                case .unauthorized:
                    errorMsg += "Je Strava sessie is verlopen. Koppel opnieuw in de instellingen."
                case .networkError(let desc):
                    errorMsg += "Netwerkfout (\(desc))."
                case .decodingError(let desc):
                    errorMsg += "Data onleesbaar (\(desc))."
                case .invalidResponse:
                    errorMsg += "Ongeldig antwoord van de server."
                }
                Task { @MainActor in
                    messages.append(ChatMessage(role: .ai, text: errorMsg))
                    isFetchingWorkout = false
                }
            } catch {
                Task { @MainActor in
                    messages.append(ChatMessage(role: .ai, text: "Er is een onbekende fout opgetreden bij het communiceren met Strava."))
                    isFetchingWorkout = false
                }
            }
        }
    }

    /// Haalt een specifieke Strava activiteit op (bijv. vanuit een notificatie),
    /// formatteert deze als een Nederlandse prompt en stuurt deze naar de AI-coach.
    func analyzeWorkout(withId id: Int64) {
        guard !isFetchingWorkout else { return }
        isFetchingWorkout = true

        Task {
            do {
                let activity = try await fitnessDataService.fetchActivity(byId: id)

                // Converteer eenheden
                let distanceKm = String(format: "%.1f", activity.distance / 1000.0)
                let timeMinutes = activity.moving_time / 60
                let heartRateStr = activity.average_heartrate != nil ? "\(Int(activity.average_heartrate!))" : "onbekend"

                // Formatteer de context prompt
                let prompt = "Ik heb zojuist deze training voltooid op Strava. Naam: \(activity.name), Afstand: \(distanceKm) km, Tijd: \(timeMinutes) minuten, Gem. Hartslag: \(heartRateStr). Kan je deze training kort analyseren als mijn coach en vertellen of ik goed bezig ben?"

                Task { @MainActor in
                    messages.append(ChatMessage(role: .user, text: prompt))
                    isTyping = true
                    isFetchingWorkout = false
                    fetchAIResponse(for: prompt, image: nil)
                }

            } catch let error as FitnessDataError {
                var errorMsg = "Fout bij ophalen van Strava data voor activiteit \(id): "
                switch error {
                case .missingToken:
                    errorMsg += "Je bent niet ingelogd op Strava."
                case .unauthorized:
                    errorMsg += "Je Strava sessie is verlopen."
                case .networkError(let desc):
                    errorMsg += "Netwerkfout (\(desc))."
                case .decodingError(let desc):
                    errorMsg += "Data onleesbaar (\(desc))."
                case .invalidResponse:
                    errorMsg += "Ongeldig antwoord van de server."
                }
                Task { @MainActor in
                    messages.append(ChatMessage(role: .ai, text: errorMsg))
                    isFetchingWorkout = false
                }
            } catch {
                Task { @MainActor in
                    messages.append(ChatMessage(role: .ai, text: "Er is een onbekende fout opgetreden."))
                    isFetchingWorkout = false
                }
            }
        }
    }

    /// Stuurt asynchroon het verzoek naar het AI-model met de juiste content payload.
    ///
    /// - Parameters:
    ///   - text: De ingevoerde tekst door de gebruiker.
    ///   - image: Een optionele UIImage.
    func fetchAIResponse(for text: String, image: UIImage?) {
        // Om te zorgen dat de unit tests (die het protocol mocken) niet falen op de check
        // van de ontbrekende API sleutel (omdat de statische Secrets placeholder vaak actief is in CI),
        // negeren we de check als een custom model is geïnjecteerd voor testing, of loggen de waarschuwing.
        #if !DEBUG
        guard Secrets.geminiAPIKey != "VUL_HIER_JE_API_KEY_IN" else {
            // Als de API-key ontbreekt in productie, waarschuw dan in de chat.
            messages.append(ChatMessage(role: .ai, text: "Let op: De API-sleutel ontbreekt in Secrets.swift. Vul deze in om met mij te kunnen praten!"))
            return
        }
        #endif

        // Zelfs als het DEBUG is, en we de fallback gebruiken zonder mock, tonen we toch de error
        if Secrets.geminiAPIKey == "VUL_HIER_JE_API_KEY_IN" && (model is RealGenerativeModel) {
             messages.append(ChatMessage(role: .ai, text: "Let op: De API-sleutel ontbreekt in Secrets.swift. Vul deze in om met mij te kunnen praten!"))
             return
        }

        Task {
            do {
                // Maak een dynamische array van ModelContent.Part objects
                var promptParts: [ModelContent.Part] = []

                if !text.isEmpty {
                    promptParts.append(.text(text))
                }

                // Zet de UIImage om naar JPEG data en wrap het in een SDK Part
                if let image = image, let imageData = image.jpegData(compressionQuality: 0.8) {
                    let imagePart = ModelContent.Part.data(mimetype: "image/jpeg", imageData)
                    promptParts.append(imagePart)
                }

                // Geef de array direct over aan de model protocol wrapper
                let responseText = try await model.generateContent(promptParts)

                let finalResponseText = responseText ?? "Ik kon geen antwoord genereren."

                messages.append(ChatMessage(role: .ai, text: finalResponseText))
            } catch {
                messages.append(ChatMessage(role: .ai, text: "Sorry, er ging iets mis: \(error.localizedDescription)"))
            }

            isTyping = false
        }
    }
}
