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
    private let fitnessCalculator: PhysiologicalCalculatorProtocol

    // Lees de voorkeur van de gebruiker m.b.t. primaire databron (Sprint 7.4)
    @AppStorage("selectedDataSource") private var selectedDataSource: DataSource = .healthKit

    /// Initialiseert de `ChatViewModel`.
    ///
    /// - Parameter aiModel: De AI-dienst die gebruikt moet worden.
    ///             Wanneer niets wordt meegegeven, wordt standaard de
    ///             `RealGenerativeModel` (die met Google API praat) gebruikt.
    init(aiModel: GenerativeModelProtocol? = nil,
         fitnessDataService: FitnessDataService = FitnessDataService(),
         healthKitManager: HealthKitManager = HealthKitManager(),
         fitnessCalculator: PhysiologicalCalculatorProtocol = PhysiologicalCalculator()) {
        self.fitnessDataService = fitnessDataService
        self.healthKitManager = healthKitManager
        self.fitnessCalculator = fitnessCalculator

        if let providedModel = aiModel {
            self.model = providedModel
        } else {
            let systemInstruction = """
            Jij bent een samenwerkende, meedenkende en proactieve AI fitness-coach.
            Je analyseert niet alleen vermoeidheid, maar je helpt de gebruiker actief om de eerstvolgende stap te plannen richting hun gestelde doelen.
            Houd je antwoorden beknopt, direct en deskundig. Stel je niet op als een waarschuwende dokter, maar als een partner in hun trainingsschema.

            Belangrijke context voor je analyse:
            Wij berekenen lokaal een Banister TRIMP (Training Impulse) score om de trainingsbelasting te bepalen (niet de traditionele TSS die op 100/uur cap).
            - Een TRIMP van 70-100 is een pittige, solide training.
            - Een TRIMP van 100-140 is een zeer zware training, maar dit is op zichzelf geen teken van overtraining.
            """

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
        var prefix = ""

        if let p = profile {
            let peakDistanceKm = String(format: "%.1f", p.peakDistanceInMeters / 1000)
            let peakDurationMin = p.peakDurationInSeconds / 60
            let weeklyVolumeMin = p.averageWeeklyVolumeInSeconds / 60

            prefix += "[CONTEXT ATLEET: Heeft een piekprestatie van \(peakDistanceKm) km in \(peakDurationMin) minuten. Traint gemiddeld \(weeklyVolumeMin) minuten per week (gem. laatste 4 weken), en heeft \(p.daysSinceLastTraining) dagen geleden voor het laatst getraind."

            // SPRINT 6.3: Overtrainings waarschuwing
            if p.isRecoveryNeeded {
                prefix += " URGENT: De atleet vertoont tekenen van overtraining op basis van recent volume. Wees streng, adviseer actief om rust te nemen en analyseer deze training puur op herstel."
            }

            prefix += " Neem dit mee in je analyse over herstel en prestatie.]\n\n"
        }

        guard !prefix.isEmpty else { return "" }
        prefix += "[VRAAG]: "
        return prefix
    }

    /// Verstuurt het huidige tekstveld (of de meegegeven tekst) en/of de geselecteerde afbeelding.
    func sendMessage(_ explicitText: String? = nil, contextProfile: AthleticProfile? = nil, activeGoals: [FitnessGoal] = []) {
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

        // Combine explicitly injected goals into user text if applicable for plain chat
        var finalUserText = textToUse
        let uncompletedGoals = activeGoals.filter { !$0.isCompleted }
        if !uncompletedGoals.isEmpty && textToUse != "" {
            let goalsString = uncompletedGoals.map { goal in
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return "\(goal.title) voor \(formatter.string(from: goal.targetDate))"
            }.joined(separator: ", ")

            finalUserText = "[DOELEN: \(goalsString)]\n" + finalUserText
        }

        let payloadText = finalUserText.isEmpty ? contextPrefix : "\(contextPrefix)\(finalUserText)"

        // 3. Haal AI reactie op met de verrijkte payload
        fetchAIResponse(for: payloadText, image: imageToSend)
    }

    /// Genereert een tekstprompt voor de Gemini AI op basis van de fysiologische data uit HealthKit.
    struct DailyWorkout {
        let date: Date
        let name: String
        let durationMinutes: Int
        let trimp: Int
    }

    private func generateCurrentStatusPrompt(workouts: [DailyWorkout], days: Int, activeGoals: [FitnessGoal]) -> String {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        var lines: [String] = ["Context voor de AI Coach:"]

        // Inject Goals explicitly
        let uncompletedGoals = activeGoals.filter { !$0.isCompleted }
        if uncompletedGoals.isEmpty {
            lines.append("- Mijn opgeslagen doelen: Geen specifieke doelen.")
        } else {
            let goalsString = uncompletedGoals.map { goal in
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                let dateStr = formatter.string(from: goal.targetDate)
                let sport = goal.sportType ?? "Sport"
                return "\(goal.title) (\(sport)) voor \(dateStr)"
            }.joined(separator: ", ")
            lines.append("- Mijn opgeslagen doelen: \(goalsString)")
        }

        lines.append("- Mijn belasting (afgelopen \(days) dagen):")
        var totalTrimp = 0

        var workoutsByDay: [Int: [DailyWorkout]] = [:]

        for workout in workouts {
            let startOfWorkoutDay = calendar.startOfDay(for: workout.date)
            let components = calendar.dateComponents([.day], from: startOfWorkoutDay, to: startOfToday)
            let dayOffset = components.day ?? 0

            if dayOffset < days && dayOffset >= 0 {
                if workoutsByDay[dayOffset] == nil {
                    workoutsByDay[dayOffset] = []
                }
                workoutsByDay[dayOffset]?.append(workout)
                totalTrimp += workout.trimp
            }
        }

        var emptyDaysStreak: [Int] = []

        for dayOffset in 0..<days {
            let displayDay = days - dayOffset

            if let dailyWorkouts = workoutsByDay[dayOffset], !dailyWorkouts.isEmpty {
                if !emptyDaysStreak.isEmpty {
                    if emptyDaysStreak.count == 1 {
                        lines.append("- Dag \(emptyDaysStreak[0]): Rust")
                    } else {
                        lines.append("- Dag \(emptyDaysStreak.first!) t/m \(emptyDaysStreak.last!): Rust")
                    }
                    emptyDaysStreak.removeAll()
                }

                var dayName = "Dag \(displayDay)"
                if dayOffset == 0 {
                    dayName += " (Vandaag)"
                } else if dayOffset == 1 {
                    dayName += " (Gisteren)"
                }

                for workout in dailyWorkouts {
                    lines.append("- \(dayName): \(workout.durationMinutes) min \(workout.name) (TRIMP: \(workout.trimp))")
                }
            } else {
                emptyDaysStreak.append(displayDay)
            }
        }

        if !emptyDaysStreak.isEmpty {
            if emptyDaysStreak.count == 1 {
                lines.append("- Dag \(emptyDaysStreak[0]): Rust")
            } else {
                lines.append("- Dag \(emptyDaysStreak.first!) t/m \(emptyDaysStreak.last!): Rust")
            }
        }

        lines.append("Totale Cumulatieve TRIMP: \(totalTrimp)")

        lines.append("\nInstructie voor de Coach:")
        lines.append("Analyseer mijn vermoeidheid, maar start vooral een discussie over wat nu verstandig is om te doen. Geef een concreet voorstel voor mijn eerstvolgende training. Denk proactief mee over:")
        lines.append("- Specifieke afstand of duur.")
        lines.append("- Het gewenste tempo (pace).")
        lines.append("- De hartslagzones waar ik in moet blijven.")
        lines.append("\nEindig je antwoord altijd met een vraag aan mij (bijv. 'Heb je daar vandaag de tijd voor?').")

        return lines.joined(separator: "\n")
    }

    /// Haalt de status op via de geselecteerde bron voor de afgelopen X dagen.
    /// Valt terug op de andere bron bij gebrek aan data of permissies.
    func analyzeCurrentStatus(days: Int = 7, contextProfile: AthleticProfile? = nil, activeGoals: [FitnessGoal] = []) {
        guard !isFetchingWorkout else { return }
        isFetchingWorkout = true

        Task {
            // SPRINT 7.4 - Check geselecteerde databron
            if selectedDataSource == .healthKit {
                do {
                    let workouts = try await healthKitManager.fetchRecentWorkouts(days: days)
                    if !workouts.isEmpty {
                        var dailyWorkouts: [DailyWorkout] = []
                        for workout in workouts {
                            let durationInMinutes = Int(workout.duration / 60.0)
                            let calculatedTSS = fitnessCalculator.calculateTSS(durationInSeconds: workout.duration, averageHeartRate: workout.averageHeartRate, maxHeartRate: workout.maxHeartRate, restingHeartRate: workout.restingHeartRate)
                            let trimpInt = Int(calculatedTSS)

                            dailyWorkouts.append(DailyWorkout(date: workout.startDate, name: workout.name, durationMinutes: durationInMinutes, trimp: trimpInt))
                        }

                        let uiPrompt = generateCurrentStatusPrompt(workouts: dailyWorkouts, days: days, activeGoals: activeGoals)
                        await sendPromptToAI(uiPrompt: uiPrompt, contextProfile: contextProfile, activeGoals: activeGoals)
                        return
                    }
                    print("⚠️ Geen of lege HealthKit workouts gevonden, terugvallen op Strava.")
                } catch {
                    print("⚠️ Fout bij ophalen HealthKit data (\(error.localizedDescription)), terugvallen op Strava.")
                }

                // Fallback naar Strava
                await fetchStravaRecentActivities(days: days, contextProfile: contextProfile, activeGoals: activeGoals)

            } else {
                // Strava geselecteerd
                await fetchStravaRecentActivities(days: days, contextProfile: contextProfile, activeGoals: activeGoals)
            }
        }
    }

    /// Hulpfunctie voor de AI prompt injectie.
    private func sendPromptToAI(uiPrompt: String, contextProfile: AthleticProfile?, activeGoals: [FitnessGoal] = []) async {
        await MainActor.run {
            messages.append(ChatMessage(role: .user, text: uiPrompt))
            isTyping = true
            isFetchingWorkout = false

            let contextPrefix = buildContextPrefix(from: contextProfile)
            let payloadText = "\(contextPrefix)\(uiPrompt)"
            fetchAIResponse(for: payloadText, image: nil)
        }
    }

    /// Hulpfunctie voor het ophalen via HealthKit, met optionele fallback.
    private func fetchHealthKitRecentWorkouts(days: Int, contextProfile: AthleticProfile?, activeGoals: [FitnessGoal] = [], isFallback: Bool = false) async {
        do {
            let workouts = try await healthKitManager.fetchRecentWorkouts(days: days)
            if !workouts.isEmpty {
                var dailyWorkouts: [DailyWorkout] = []
                for workout in workouts {
                    let durationInMinutes = Int(workout.duration / 60.0)
                    let calculatedTSS = fitnessCalculator.calculateTSS(durationInSeconds: workout.duration, averageHeartRate: workout.averageHeartRate, maxHeartRate: workout.maxHeartRate, restingHeartRate: workout.restingHeartRate)
                    let trimpInt = Int(calculatedTSS)

                    dailyWorkouts.append(DailyWorkout(date: workout.startDate, name: workout.name, durationMinutes: durationInMinutes, trimp: trimpInt))
                }

                let uiPrompt = generateCurrentStatusPrompt(workouts: dailyWorkouts, days: days, activeGoals: activeGoals)
                await sendPromptToAI(uiPrompt: uiPrompt, contextProfile: contextProfile, activeGoals: activeGoals)
                return
            }

            if !isFallback {
                print("⚠️ Geen of lege HealthKit workouts gevonden, terugvallen op Strava.")
                await fetchStravaRecentActivities(days: days, contextProfile: contextProfile, activeGoals: activeGoals, isFallback: true)
            } else {
                await MainActor.run {
                    messages.append(ChatMessage(role: .ai, text: "Ik kon geen recente trainingen vinden in HealthKit of je Strava account."))
                    isFetchingWorkout = false
                }
            }
        } catch {
            if !isFallback {
                print("⚠️ Fout bij ophalen HealthKit data (\(error.localizedDescription)), terugvallen op Strava.")
                await fetchStravaRecentActivities(days: days, contextProfile: contextProfile, activeGoals: activeGoals, isFallback: true)
            } else {
                await MainActor.run {
                    messages.append(ChatMessage(role: .ai, text: "Ik kon geen recente trainingen vinden. HealthKit fout: \(error.localizedDescription)"))
                    isFetchingWorkout = false
                }
            }
        }
    }

    /// Hulpfunctie voor het ophalen via Strava, inclusief fallback naar HealthKit.
    private func fetchStravaRecentActivities(days: Int, contextProfile: AthleticProfile?, activeGoals: [FitnessGoal] = [], isFallback: Bool = false) async {
        do {
            let activities = try await fitnessDataService.fetchRecentActivities(days: days)

            if activities.isEmpty {
                if !isFallback && selectedDataSource == .strava {
                    // Reverse Fallback: Als Strava faalt of leeg is en Strava was de bron, probeer HealthKit
                    print("⚠️ Geen recente Strava activiteit gevonden. Reverse fallback naar HealthKit.")
                    await fetchHealthKitRecentWorkouts(days: days, contextProfile: contextProfile, activeGoals: activeGoals, isFallback: true)
                    return
                }

                await MainActor.run {
                    messages.append(ChatMessage(role: .ai, text: "Ik kon geen recente trainingen vinden in HealthKit of je Strava account."))
                    isFetchingWorkout = false
                }
                return
            }

            let formatter = ISO8601DateFormatter()
            var dailyWorkouts: [DailyWorkout] = []

            for activity in activities {
                let date = formatter.date(from: activity.start_date) ?? Date()
                let durationMinutes = activity.moving_time / 60

                // Schatting resting heart rate en max heart rate als deze niet via Strava beschikbaar is,
                // of we kunnen een simpele fallback gebruiken.
                // In een echte app zouden we dit uit het profiel halen of een default nemen.
                let avgHR = activity.average_heartrate ?? 140.0
                let calculatedTSS = fitnessCalculator.calculateTSS(durationInSeconds: Double(activity.moving_time), averageHeartRate: avgHR, maxHeartRate: 190.0, restingHeartRate: 60.0)

                dailyWorkouts.append(DailyWorkout(date: date, name: activity.name, durationMinutes: durationMinutes, trimp: Int(calculatedTSS)))
            }

            let uiPrompt = generateCurrentStatusPrompt(workouts: dailyWorkouts, days: days, activeGoals: activeGoals)

            await sendPromptToAI(uiPrompt: uiPrompt, contextProfile: contextProfile, activeGoals: activeGoals)

        } catch let error as FitnessDataError {
            if !isFallback && selectedDataSource == .strava {
                print("⚠️ Strava API fout (\(error)). Reverse fallback naar HealthKit.")
                await fetchHealthKitRecentWorkouts(days: days, contextProfile: contextProfile, activeGoals: activeGoals, isFallback: true)
                return
            }

            var errorMsg = "Fout bij ophalen van data: "
            switch error {
            case .missingToken: errorMsg += "Je bent niet ingelogd op Strava. Ga naar instellingen om te koppelen."
            case .unauthorized: errorMsg += "Je Strava sessie is verlopen. Koppel opnieuw in de instellingen."
            case .networkError(let desc): errorMsg += "Netwerkfout (\(desc))."
            case .decodingError(let desc): errorMsg += "Data onleesbaar (\(desc))."
            case .invalidResponse: errorMsg += "Ongeldig antwoord van de server."
            }
            await MainActor.run {
                messages.append(ChatMessage(role: .ai, text: errorMsg))
                isFetchingWorkout = false
            }
        } catch {
            if !isFallback && selectedDataSource == .strava {
                await fetchHealthKitRecentWorkouts(days: days, contextProfile: contextProfile, activeGoals: activeGoals, isFallback: true)
                return
            }

            await MainActor.run {
                messages.append(ChatMessage(role: .ai, text: "Er is een onbekende fout opgetreden."))
                isFetchingWorkout = false
            }
        }
    }

    /// Haalt een specifieke Strava activiteit op (bijv. vanuit een notificatie),
    /// formatteert deze als een Nederlandse prompt en stuurt deze naar de AI-coach.
    func analyzeWorkout(withId id: Int64, contextProfile: AthleticProfile? = nil, activeGoals: [FitnessGoal] = []) {
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
