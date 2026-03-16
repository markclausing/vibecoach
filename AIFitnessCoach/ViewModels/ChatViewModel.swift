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

        // Haal recente Strava activiteit op om als extra context mee te sturen
        Task {
            isTyping = true
            var activityContext = ""

            do {
                if let activity = try await fitnessDataService.fetchLatestActivity() {
                    let heartRateStr = activity.average_heartrate != nil ? "\(Int(activity.average_heartrate!)) bpm" : "onbekend"
                    activityContext = "\n\n[Systeem context: De gebruiker heeft zojuist een Strava activiteit voltooid. Naam: '\(activity.name)'. Afstand: \(Int(activity.distance)) meter. Tijd: \(activity.moving_time) seconden. Gemiddelde hartslag: \(heartRateStr).]"
                }
            } catch let error as FitnessDataError {
                // Toon een systeembericht aan de gebruiker als er een bekende API fout is
                messages.append(ChatMessage(role: .ai, text: "Let op: Ik kon je recente Strava data niet ophalen. Reden: \(error.localizedDescription)"))
                print("Strava data ophalen mislukt: \(error.localizedDescription)")
            } catch {
                print("Onbekende fout bij Strava: \(error)")
            }

            // 3. Haal AI reactie op (inclusief eventuele Strava context)
            let fullText = textToSend + activityContext
            fetchAIResponse(for: fullText, image: imageToSend)
        }

        inputText = ""
        clearImage()
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
