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

    /// Service voor HealthKit (Sprint 7.2).
    private let healthKitManager: HealthKitManager
    private let fitnessCalculator: FitnessCalculatorProtocol

    /// Initialiseert de `ChatViewModel`.
    ///
    /// - Parameter aiModel: De AI-dienst die gebruikt moet worden.
    ///             Wanneer niets wordt meegegeven, wordt standaard de
    ///             `RealGenerativeModel` (die met Google API praat) gebruikt.
    init(aiModel: GenerativeModelProtocol? = nil,
         fitnessDataService: FitnessDataService = FitnessDataService(),
         healthKitManager: HealthKitManager = HealthKitManager(),
         fitnessCalculator: FitnessCalculatorProtocol = FitnessCalculator()) {
        self.fitnessDataService = fitnessDataService
        self.healthKitManager = healthKitManager
        self.fitnessCalculator = fitnessCalculator

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

    /// Genereert een context-prefix string op basis van het meegegeven atletisch profiel.
    private func buildContextPrefix(from profile: AthleticProfile?) -> String {
        guard let p = profile else { return "" }
        let peakDistanceKm = String(format: "%.1f", p.peakDistanceInMeters / 1000)
        let peakDurationMin = p.peakDurationInSeconds / 60
        let weeklyVolumeMin = p.averageWeeklyVolumeInSeconds / 60

        var prefix = "[CONTEXT ATLEET: Heeft een piekprestatie van \(peakDistanceKm) km in \(peakDurationMin) minuten. Traint gemiddeld \(weeklyVolumeMin) minuten per week (gem. laatste 4 weken), en heeft \(p.daysSinceLastTraining) dagen geleden voor het laatst getraind."

        // SPRINT 6.3: Overtrainings waarschuwing
        if p.isRecoveryNeeded {
            prefix += " URGENT: De atleet vertoont tekenen van overtraining op basis van recent volume. Wees streng, adviseer actief om rust te nemen en analyseer deze training puur op herstel."
        }

        prefix += " Neem dit mee in je analyse over herstel en prestatie.]\n\n[VRAAG]: "
        return prefix
    }

    /// Verstuurt het huidige tekstveld (of de meegegeven tekst) en/of de geselecteerde afbeelding.
    func sendMessage(_ explicitText: String? = nil, contextProfile: AthleticProfile? = nil) {
        let textToUse = explicitText ?? inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        let imageToSend = selectedImage?.downsample(to: 2048.0)

        guard !textToUse.isEmpty || imageToSend != nil else { return }

        // 1. Maak bericht aan van gebruiker voor de UI (ZONDER de onzichtbare context prefix)
        let imageData = imageToSend?.jpegData(compressionQuality: 0.8)
        let uiMessage = ChatMessage(role: .user, text: textToUse, attachedImageData: imageData)
        messages.append(uiMessage)

        isTyping = true
        inputText = ""
        clearImage()

        // 2. Bouw de uiteindelijke payload prompt op
        let contextPrefix = buildContextPrefix(from: contextProfile)
        let payloadText = textToUse.isEmpty ? contextPrefix : "\(contextPrefix)\(textToUse)"

        // 3. Haal AI reactie op met de verrijkte payload
        fetchAIResponse(for: payloadText, image: imageToSend)
    }

    /// Genereert een tekstprompt voor de Gemini AI op basis van de fysiologische data uit HealthKit.
    private func generateHealthKitPrompt(for workout: WorkoutDetails, tss: Int) -> String {
        let durationInMinutes = workout.duration / 60.0
        let hr = Int(workout.averageHeartRate)
        return "Analyseer mijn laatste training. Duur: \(String(format: "%.1f", durationInMinutes)) min, Gemiddelde hartslag: \(hr) bpm, Berekende Training Stress Score (TSS): \(tss)."
    }

    /// Haalt de laatste activiteit op via HealthKit (of valt terug op Strava),
    /// berekent de fysiologische data, en stuurt de prompt naar de AI.
    func analyzeLatestWorkout(contextProfile: AthleticProfile? = nil) {
        guard !isFetchingWorkout else { return }
        isFetchingWorkout = true

        Task {
            do {
                // 1. Probeer eerst HealthKit (Sprint 7.3)
                if let workout = try await healthKitManager.fetchLatestWorkoutDetails() {
                    let durationInMinutes = workout.duration / 60.0

                    // Bereken TSS
                    let calculatedTSS = fitnessCalculator.calculateTSS(
                        durationInSeconds: workout.duration,
                        averageHeartRate: workout.averageHeartRate,
                        maxHeartRate: workout.maxHeartRate,
                        restingHeartRate: workout.restingHeartRate
                    )

                    let tssInt = Int(calculatedTSS)

                    // Print de gewenste console output
                    print("🍏 HealthKit Workout Gevonden: \(String(format: "%.1f", durationInMinutes)) min, Gem HR: \(workout.averageHeartRate), Berekende TSS: \(calculatedTSS)")

                    let uiPrompt = generateHealthKitPrompt(for: workout, tss: tssInt)

                    await MainActor.run {
                        messages.append(ChatMessage(role: .user, text: uiPrompt))
                        isTyping = true
                        isFetchingWorkout = false

                        let contextPrefix = buildContextPrefix(from: contextProfile)
                        let payloadText = "\(contextPrefix)\(uiPrompt)"
                        fetchAIResponse(for: payloadText, image: nil)
                    }
                    return
                }

                print("⚠️ Geen of lege HealthKit workout gevonden, terugvallen op Strava.")

            } catch {
                print("⚠️ Fout bij ophalen HealthKit data (\(error.localizedDescription)), terugvallen op Strava.")
            }

            // 2. Fallback: Gebruik Strava API (Oude logica)
            do {
                let activityData = try await fitnessDataService.fetchLatestActivity()

                guard let activity = activityData else {
                    await MainActor.run {
                        messages.append(ChatMessage(role: .ai, text: "Ik kon geen recente trainingen vinden in HealthKit of je Strava account."))
                        isFetchingWorkout = false
                    }
                    return
                }

                // Converteer eenheden
                let distanceKm = String(format: "%.1f", activity.distance / 1000.0)
                let timeMinutes = activity.moving_time / 60
                let heartRateStr = activity.average_heartrate != nil ? "\(Int(activity.average_heartrate!))" : "onbekend"

                // Formatteer de zichtbare UI prompt
                let uiPrompt = "Hier is de data van mijn laatste training via Strava. Naam: \(activity.name), Afstand: \(distanceKm) km, Tijd: \(timeMinutes) minuten, Gem. Hartslag: \(heartRateStr). Kan je deze training kort analyseren als mijn coach en vertellen of ik goed bezig ben?"

                await MainActor.run {
                    // Voeg de originele prompt toe aan UI
                    messages.append(ChatMessage(role: .user, text: uiPrompt))

                    isTyping = true
                    isFetchingWorkout = false

                    // Bouw de payload inclusief onzichtbare context
                    let contextPrefix = buildContextPrefix(from: contextProfile)
                    let payloadText = "\(contextPrefix)\(uiPrompt)"

                    fetchAIResponse(for: payloadText, image: nil)
                }

            } catch let error as FitnessDataError {
                var errorMsg = "Fout bij ophalen van data: "
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
                await MainActor.run {
                    messages.append(ChatMessage(role: .ai, text: errorMsg))
                    isFetchingWorkout = false
                }
            } catch {
                await MainActor.run {
                    messages.append(ChatMessage(role: .ai, text: "Er is een onbekende fout opgetreden."))
                    isFetchingWorkout = false
                }
            }
        }
    }

    /// Haalt een specifieke Strava activiteit op (bijv. vanuit een notificatie),
    /// formatteert deze als een Nederlandse prompt en stuurt deze naar de AI-coach.
    func analyzeWorkout(withId id: Int64, contextProfile: AthleticProfile? = nil) {
        guard !isFetchingWorkout else { return }
        isFetchingWorkout = true

        Task {
            do {
                let activity = try await fitnessDataService.fetchActivity(byId: id)

                // Converteer eenheden
                let distanceKm = String(format: "%.1f", activity.distance / 1000.0)
                let timeMinutes = activity.moving_time / 60
                let heartRateStr = activity.average_heartrate != nil ? "\(Int(activity.average_heartrate!))" : "onbekend"

                // Formatteer de zichtbare UI prompt
                let uiPrompt = "Ik heb zojuist deze training voltooid op Strava. Naam: \(activity.name), Afstand: \(distanceKm) km, Tijd: \(timeMinutes) minuten, Gem. Hartslag: \(heartRateStr). Kan je deze training kort analyseren als mijn coach en vertellen of ik goed bezig ben?"

                Task { @MainActor in
                    messages.append(ChatMessage(role: .user, text: uiPrompt))
                    isTyping = true
                    isFetchingWorkout = false

                    let contextPrefix = buildContextPrefix(from: contextProfile)
                    let payloadText = "\(contextPrefix)\(uiPrompt)"

                    fetchAIResponse(for: payloadText, image: nil)
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
