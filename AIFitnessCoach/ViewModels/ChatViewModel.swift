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

    /// Statusbericht tijdens een retry-poging, bijv. "Opnieuw proberen (1/3)...". Leeg als er geen retry loopt.
    @Published var retryStatusMessage: String = ""

    /// True als we op dit moment Strava data aan het ophalen zijn via de expliciete knop.
    @Published var isFetchingWorkout: Bool = false

    /// Gebruiksvriendelijke foutmelding van de laatste AI-call. `nil` zodra er een
    /// nieuwe call start of succesvol afrondt. Screens die geen chat tonen
    /// (zoals het Dashboard bij pull-to-refresh) gebruiken deze om een banner te
    /// laten zien — anders zou een timeout stil sneuvelen omdat de chat-bubble
    /// niet zichtbaar is.
    @Published var lastAIErrorMessage: String? = nil

    /// Het protocol waartegen we de AI-verzoeken uitvoeren.
    /// Lazy: wordt pas aangemaakt bij het eerste AI-verzoek, niet bij app-start.
    /// Tests kunnen een mock injecteren via de init-parameter.
    private var _model: GenerativeModelProtocol?
    private var model: GenerativeModelProtocol {
        if let existing = _model { return existing }
        let built = buildGenerativeModel()
        _model = built
        return built
    }

    /// Service voor externe API calls (Sprint 4.2).
    private let fitnessDataService: FitnessDataService

    /// Service voor HealthKit (Sprint 7.2).
    private let healthKitManager: HealthKitManager
    private let fitnessCalculator: PhysiologicalCalculatorProtocol

    // Lees de voorkeur van de gebruiker m.b.t. primaire databron (Sprint 7.4)
    @AppStorage("selectedDataSource") private var selectedDataSource: DataSource = .healthKit

    // Epic 20: BYOK — gebruiker-geconfigureerde AI provider.
    // C-02: de API-sleutel zelf staat NIET meer in @AppStorage maar in de
    // Keychain (zie `UserAPIKeyStore`). Uitlezen gebeurt via `effectiveAPIKey()`.
    @AppStorage("vibecoach_aiProvider") private var storedProviderRaw: String = AIProvider.gemini.rawValue

    /// De API-sleutel waarmee het huidige model is opgebouwd.
    /// Wordt bijgehouden om te detecteren wanneer een rebuild nodig is.
    private var activeAPIKey: String = ""

    /// True als er een bruikbare API-sleutel geconfigureerd is.
    var hasAPIKey: Bool {
        !effectiveAPIKey().isEmpty
    }

    /// De gedeelde state manager voor het actuele trainingsschema.
    private var trainingPlanManager: TrainingPlanManager?

    /// Opgeslagen Data van het meest recente gegenereerde schema (Voor fallback referentie)
    @AppStorage("latestSuggestedPlanData") private var latestSuggestedPlanData: Data = Data()

    /// Opgeslagen inzichten/motivatie van de coach om uit te lichten op het dashboard
    @AppStorage("latestCoachInsight") private var latestCoachInsight: String = ""

    /// Epic 14.4: Cache van de Vibe Score van vandaag voor injectie in AI-prompts.
    /// Wordt gevuld vanuit DashboardView (bij onAppear) zodat de AI altijd de actuele
    /// herstelstatus kent — ook zonder directe SwiftData-toegang in ChatViewModel.
    @AppStorage("vibecoach_todayVibeScoreContext") private var todayVibeScoreContext: String = ""

    /// Epic 18.1: Cache van de subjectieve feedback (RPE + stemming) van de laatste workout.
    /// Wordt gevuld vanuit DashboardView zodra een ActivityRecord een beoordeling heeft.
    @AppStorage("vibecoach_lastWorkoutFeedbackContext") private var lastWorkoutFeedbackContext: String = ""

    /// Epic 17: Cache van de actieve blueprint-status per doel voor injectie in AI-prompts.
    /// Bevat openstaande en voldane kritieke trainingen zodat de coach hierop kan bijsturen.
    @AppStorage("vibecoach_blueprintContext") private var blueprintContext: String = ""

    /// Epic 17.1: Cache van de PeriodizationEngine-status per doel.
    /// Bevat de huidige trainingsfase + succescriteria + voortgang voor gerichte fase-coaching.
    @AppStorage("vibecoach_periodizationContext") private var periodizationContext: String = ""

    /// Tijdstip van de laatste geslaagde coach-analyse (Unix timestamp).
    /// Wordt gebruikt om automatisch te vernieuwen bij een nieuwe dag.
    @AppStorage("vibecoach_lastAnalysisTimestamp") var lastAnalysisTimestamp: Double = 0

    /// Epic 18: Cache van de dagelijkse symptoomscores — pijncijfers per lichaamsdeel.
    @AppStorage("vibecoach_symptomContext") private var symptomContext: String = ""

    /// Epic 21: Cache van de 7-daagse weersverwachting — wordt gevuld door WeatherManager.
    /// Wordt geïnjecteerd in de AI-prompt zodat de coach rekening houdt met buitenactiviteiten.
    @AppStorage("vibecoach_weatherContext") var weatherContext: String = ""

    /// Epic 32 Story 32.3c: cache van significante fysiologische patronen in recente
    /// workouts (decoupling, drift, cadence-fade, trage HR-recovery). Wordt gevuld
    /// vanuit `DashboardView.refreshWorkoutPatternsContext()` op basis van de
    /// `WorkoutSample`-data van de afgelopen 7 dagen, zodat de coach er proactief
    /// over kan praten in een chat-turn.
    @AppStorage("vibecoach_workoutPatternsContext") var workoutPatternsContext: String = ""

    /// Epic 45 Story 45.3: rijkere per-workout-context over de afgelopen 14 dagen
    /// (datum, sport, sessieType, duur, TRIMP, gem-HR, eventueel power, en
    /// detector-output per workout). Aanvulling op `workoutPatternsContext` (1-regel
    /// pulse over 7 dagen): de pulse signaleert dát er iets is, dit blok geeft de
    /// coach de specifieke onderbouwing per workout zodat plan-aanpassingen verwijzen
    /// naar concrete sessies ("op 28 april reed je een tempo-rit met decoupling…").
    /// Wordt gevuld vanuit `DashboardView.refreshChatContextCaches()`.
    @AppStorage("vibecoach_workoutHistoryContext") var workoutHistoryContext: String = ""

    /// Epic 23 Sprint 1: Cache van de gap-analyse per actief doel.
    /// Bevat het verschil tussen verwacht en werkelijk TRIMP/km op dit moment in de voorbereiding.
    @AppStorage("vibecoach_gapAnalysisContext") private var gapAnalysisContext: String = ""

    /// Epic Doel-Intenties: Cache van de intent-instructies per actief doel.
    /// Bevat de gegenereerde coachingInstruction per doel (formaat, intentie, VibeScore-aanpassing).
    @AppStorage("vibecoach_intentContext") private var intentContext: String = ""

    /// Epic 23 Sprint 2: Cache van de toekomstprognose per doel (Future Projection Engine).
    /// Beantwoordt de vraag: "Wanneer bereikt de atleet de Peak Phase op basis van zijn groeitempo?"
    /// Wordt gevuld via `cacheProjections(_:)` vanuit GoalsListView en geïnjecteerd in de AI-prompt.
    @AppStorage("vibecoach_projectionContext") private var projectionContext: String = ""

    /// Epic 24 Sprint 1: Cache van het fysiologische profiel + voedingsplan voor vandaag/morgen.
    /// Wordt gevuld via `refreshNutritionContext()` en geïnjecteerd in elke AI-prompt.
    @AppStorage("vibecoach_nutritionContext") private var nutritionContext: String = ""

    /// Story 33.2a: cache van handmatig verplaatste workouts (`isSwapped == true`)
    /// zodat de coach in elke prompt weet welke sessies de gebruiker bewust heeft
    /// verschoven en die niet bij volgende suggesties terug-forceert.
    @AppStorage("vibecoach_userOverrideContext") private var userOverrideContext: String = ""

    /// Story 33.4: cache van de Intent-vs-Execution-analyse voor de meest recente workout.
    /// Empty string = geen recent vergelijkbare workout (geen plan match, of insufficient data).
    @AppStorage("vibecoach_intentExecutionContext") private var intentExecutionContext: String = ""

    /// Epic 24 Sprint 3: Eenmalige coach-melding bij een gedetecteerde profielwijziging (bijv. leeftijd).
    /// Wordt geschreven door `PhysicalProfileSection` en geïnjecteerd in de eerstvolgende AI-prompt.
    /// Wordt geleegd nadat de prompt is opgebouwd zodat de melding slechts éénmaal verschijnt.
    @AppStorage("vibecoach_profileUpdateNote") var profileUpdateNote: String = ""

    /// Callback om nieuwe voorkeuren naar de View te sturen zodat ze in SwiftData opgeslagen worden.
    var onNewPreferencesDetected: (([ExtractedPreference]) -> Void)?

    /// Stelt de TrainingPlanManager in
    func setTrainingPlanManager(_ manager: TrainingPlanManager) {
        self.trainingPlanManager = manager
    }

    /// Epic 14.4: Schrijft de Vibe Score van vandaag naar de AppStorage cache.
    /// Wordt aangeroepen vanuit DashboardView bij onAppear zodat de AI-prompts
    /// altijd de actuele herstelstatus bevatten.
    /// Sentinel-waarde die aangeeft dat er vandaag geen Watch-data beschikbaar was.
    /// Wordt herkend in buildContextPrefix om de AI de juiste instructie te geven.
    private static let noVibeDataSentinel = "GEEN_BIOMETRISCHE_DATA"

    /// Markeert in de AI-cache dat de Vibe Score ontbreekt omdat de Watch niet gedragen werd.
    /// De coach krijgt dan expliciet de instructie om op symptoomscores en eigen gevoel te vertrouwen.
    func cacheVibeScoreUnavailable() {
        todayVibeScoreContext = Self.noVibeDataSentinel
    }

    func cacheVibeScore(_ readiness: DailyReadiness?) {
        guard let r = readiness else {
            // Niet overschrijven als er al een 'unavailable' sentinel staat —
            // die is waardevoller dan gewoon leeeg.
            if todayVibeScoreContext != Self.noVibeDataSentinel {
                todayVibeScoreContext = ""
            }
            return
        }

        let label: String
        if r.readinessScore >= 80 { label = "Optimaal Hersteld" }
        else if r.readinessScore >= 50 { label = "Matig Hersteld" }
        else { label = "Slecht Hersteld — Rust prioriteit" }

        let sleepH = Int(r.sleepHours)
        let sleepM = Int((r.sleepHours - Double(sleepH)) * 60)

        // Epic 21 Sprint 2: voeg slaapfase-kwaliteit toe als stage-data beschikbaar is
        var sleepQualityNote = ""
        let totalStageMins = r.deepSleepMinutes + r.remSleepMinutes + r.coreSleepMinutes
        if totalStageMins > 0 {
            let deepRatio = Double(r.deepSleepMinutes) / Double(totalStageMins)
            let qualLabel: String = {
                if deepRatio >= 0.20 { return "Uitstekend" }
                if deepRatio >= 0.15 { return "Goed" }
                if deepRatio >= 0.10 { return "Matig" }
                return "Onvoldoende"
            }()
            sleepQualityNote = " Slaapfases: diep \(r.deepSleepMinutes)m · REM \(r.remSleepMinutes)m · kern \(r.coreSleepMinutes)m (kwaliteit: \(qualLabel), \(String(format: "%.0f%%", deepRatio * 100)) diepe slaap)."

            // Geef de coach een expliciete instructie bij slechte diepe slaap
            if deepRatio < 0.15 {
                sleepQualityNote += " INSTRUCTIE: Benoem de slaapkwaliteit expliciet in je Insight ('Je hebt \(sleepH)u \(sleepM)m geslapen maar de diepe slaap was maar \(String(format: "%.0f%%", deepRatio * 100)) — herstel is daardoor minder effectief'). Houd de intensiteit dienovereenkomstig lager."
            }
        }

        todayVibeScoreContext = "Vibe Score vandaag: \(r.readinessScore)/100 (\(label)). Slaap: \(sleepH)u \(sleepM)m. HRV: \(String(format: "%.1f", r.hrv)) ms.\(sleepQualityNote)"
    }

    /// Epic 20 / M-04: Retourneert de door de gebruiker geconfigureerde Gemini API-sleutel.
    /// Er is geen Secrets-fallback meer — BYOK is verplicht, de onboarding zorgt dat
    /// er altijd een sleutel is ingevuld voordat AI-functionaliteit aangeroepen wordt.
    /// C-02: sleutel wordt gelezen uit de Keychain via `UserAPIKeyStore`.
    func effectiveAPIKey() -> String {
        return UserAPIKeyStore.read()
    }

    /// Bouwt een nieuw Gemini model op basis van de huidige API-sleutel.
    /// Wordt aangeroepen als de gebruiker een nieuwe sleutel heeft opgeslagen.
    /// Epic 20: Placeholder voor Sprint 20.2 — slaat de aktieve key op zodat toekomstige
    /// code kan detecteren of de sleutel gewijzigd is en het model opnieuw moet bouwen.
    private func rebuildRealModel() {
        let key = effectiveAPIKey()
        guard !key.isEmpty else { return }
        activeAPIKey = key
        // Wis de gecachte instantie zodat buildGenerativeModel() opnieuw gebouwd wordt
        // met de nieuwe sleutel bij het eerstvolgende AI-verzoek.
        _model = nil
    }

    /// Epic 18.1: Schrijft de subjectieve feedback van de laatste workout naar de AppStorage cache.
    /// Wordt aangeroepen vanuit DashboardView zodra er een ActivityRecord is met rpe en mood.
    /// De AI gebruikt dit om discrepanties te detecteren (bijv. laag TRIMP maar hoge RPE = overtraining signaal).
    /// Epic 33 Story 33.1b: optioneel `sessionType` — als aanwezig wordt het type + fysiologische
    /// intent meegegeven zodat de coach z'n toon kalibreert (geen "te langzaam" bij Recovery).
    /// Format-logica zit in `LastWorkoutContextFormatter` (testbaar zonder ChatViewModel-state).
    /// Story 33.2a: schrijft het USER_OVERRIDE-blok naar de cache. Aangeroepen vanuit
    /// `DashboardView.onAppear` zodat het blok bij elke schema-context-build aanwezig is.
    func cacheUserOverrides(_ workouts: [SuggestedWorkout]) {
        userOverrideContext = UserOverrideContextFormatter.format(workouts: workouts)
    }

    /// Story 33.4: schrijft de Intent-vs-Execution-analyse naar de cache. Aangeroepen
    /// vanuit DashboardView wanneer er een recente match is tussen een SuggestedWorkout
    /// en een ActivityRecord op dezelfde kalenderdag. Pass `""` om de cache te legen.
    func cacheIntentExecution(_ formatted: String) {
        intentExecutionContext = formatted
    }

    // MARK: - Story 33.2b: Reset Schema

    /// Bepaalt of `trainingPlanManager?.updatePlan` of `mergeReplannedPlan` wordt
    /// gebruikt zodra er een nieuw plan uit Gemini terugkomt. Default `.replace`
    /// behoudt het bestaande gedrag van requestRecoveryPlan / skipWorkout etc.
    private enum PlanUpdateMode {
        case replace
        case mergePreservingSwaps
    }
    private var pendingPlanUpdateMode: PlanUpdateMode = .replace

    /// Story 33.2b: vraagt Gemini om de rest van de week opnieuw te plannen rondom
    /// de handmatig verplaatste sessies. Het response-plan wordt door
    /// `TrainingPlanManager.mergeReplannedPlan(_:)` ge-merget zodat overrides
    /// gegarandeerd blijven, zelfs bij AI-hallucinaties op heilige dagen.
    /// - Parameter swappedWorkouts: De workouts met `isSwapped == true` uit het
    ///   huidige plan. Caller (`WeekTimelineView`) levert die aan.
    func requestPlanReset(swappedWorkouts: [SuggestedWorkout],
                          contextProfile: AthleticProfile? = nil,
                          activeGoals: [FitnessGoal] = [],
                          activePreferences: [UserPreference] = []) {
        // Voorkom parallelle resets — isTyping vangt de meeste cases af, maar de
        // mode-flag moet ook beschermd zijn.
        guard !isTyping else { return }

        let (systemText, userText) = PlanResetPromptBuilder.build(swappedWorkouts: swappedWorkouts)
        pendingPlanUpdateMode = .mergePreservingSwaps
        sendHiddenSystemMessage(
            systemText: systemText,
            userText: userText,
            fallbackMessage: "Ik heb je week opnieuw ingedeeld rondom je verplaatste sessies. Bekijk je overzicht.",
            contextProfile: contextProfile,
            activeGoals: activeGoals,
            activePreferences: activePreferences
        )
    }

    func cacheLastWorkoutFeedback(rpe: Int?,
                                  mood: String?,
                                  workoutName: String?,
                                  trimp: Double?,
                                  startDate: Date? = nil,
                                  sessionType: SessionType? = nil) {
        lastWorkoutFeedbackContext = LastWorkoutContextFormatter.format(
            rpe: rpe,
            mood: mood,
            workoutName: workoutName,
            trimp: trimp,
            startDate: startDate,
            sessionType: sessionType
        )
    }

    /// Epic 17: Schrijft de blueprint-status van alle actieve doelen naar de AppStorage cache.
    /// Wordt aangeroepen vanuit DashboardView zodat de AI weet welke kritieke trainingen
    /// al behaald zijn en welke nog open staan — voor gerichtere coaching.
    func cacheActiveBlueprints(_ results: [BlueprintCheckResult]) {
        guard !results.isEmpty else {
            blueprintContext = ""
            return
        }

        var lines: [String] = []
        for result in results {
            let weeksLeft = result.goal.weeksRemaining
            let weeksLeftStr = String(format: "%.1f", weeksLeft)
            let statusLabel = result.isOnTrack ? "Op schema" : "Achter op schema"
            lines.append("• Doel '\(result.goal.title)' (\(weeksLeftStr) weken resterend) — Blueprint: \(result.blueprint.goalType.displayName), \(statusLabel) (\(result.satisfiedCount)/\(result.totalCount) kritieke eisen behaald).")

            for milestone in result.milestones {
                let check = milestone.isSatisfied ? "✅" : "❌"
                let deadlineStr = DateFormatter.localizedString(from: milestone.deadline, dateStyle: .short, timeStyle: .none)
                if milestone.isSatisfied {
                    lines.append("  \(check) \(milestone.description) (behaald)")
                } else {
                    lines.append("  \(check) \(milestone.description) — deadline: \(deadlineStr) (\(milestone.weeksBefore) weken voor race)")
                }
            }
        }
        blueprintContext = lines.joined(separator: "\n")
    }

    /// Epic 17.1: Schrijft de PeriodizationEngine-status naar de AppStorage cache.
    /// Wordt aangeroepen vanuit DashboardView zodat de AI per doel weet in welke trainingsfase
    /// de gebruiker zit en of hij aan de fase-specifieke succescriteria voldoet.
    func cachePeriodizationStatus(_ results: [PeriodizationResult]) {
        guard !results.isEmpty else {
            periodizationContext = ""
            return
        }
        periodizationContext = results
            .map { $0.coachingContext }
            .joined(separator: "\n\n")
    }

    /// Epic Doel-Intenties: Schrijft de intent-instructies per doel naar de AppStorage cache.
    /// Wordt aangeroepen vanuit ContentView (na cachePeriodizationStatus) zodat de AI een aparte
    /// [DOEL INTENTIES EN BENADERING] sectie ontvangt met format-, intentie- en VibeScore-instructies.
    func cacheIntentContext(_ results: [PeriodizationResult]) {
        let instructions = results
            .filter { !$0.intentModifier.coachingInstruction.isEmpty }
            .map { result -> String in
                var text = "• \(result.goal.title):\n\(result.intentModifier.coachingInstruction)"

                // Expliciete toertocht-context: de coach mag NIET redeneren als bij een wedstrijd
                let format = result.goal.resolvedFormat
                if format == .multiDayStage || format == .singleDayTour {
                    text += "\n⚠️ LET OP: Dit is een TOERTOCHT, geen race. Beoordeel de voortgang op basis van rustig touren, comfort en meerdaags duurvermogen, NIET op race-snelheid."
                }

                // Expliciete stretch goal doeltijd in leesbaar formaat
                if let stretchTime = result.goal.stretchGoalTime {
                    let totalSec = Int(stretchTime)
                    let hours    = totalSec / 3600
                    let minutes  = (totalSec % 3600) / 60
                    let timeStr  = hours > 0 ? "\(hours) uur en \(minutes) minuten" : "\(minutes) minuten"
                    text += "\n✅ Stretch Goal Doeltijd: \(timeStr). Bouw af en toe tempo-oefeningen in het schema in om deze snelheid op te bouwen, mits de actuele VibeScore / herstel dit toelaat."
                }

                return text
            }
        intentContext = instructions.isEmpty ? "" : instructions.joined(separator: "\n\n")
    }

    /// Epic 23 Sprint 1: Schrijft de gap-analyse (verschil gepland vs. gerealiseerd) naar de AppStorage cache.
    /// De coach gebruikt dit om concrete bijsturingsadviezen te geven:
    /// "Je ligt X km achter op schema — deze week 15% meer volume om dat in te halen."
    func cacheGapAnalysis(_ gaps: [BlueprintGap]) {
        guard !gaps.isEmpty else {
            gapAnalysisContext = ""
            return
        }
        gapAnalysisContext = gaps
            .map { $0.coachContext }
            .joined(separator: "\n\n")
    }

    /// Epic 23 Sprint 2: Schrijft de toekomstprognose per doel naar de AppStorage cache.
    /// De coach gebruikt dit om proactief te waarschuwen als een doel "At Risk" of "Unreachable" is:
    /// "Op basis van je huidige tempo ben je pas in juli klaar voor de marathon."
    func cacheProjections(_ projections: [GoalProjection]) {
        projectionContext = FutureProjectionService.buildCoachContext(from: projections)
    }

    /// Epic 24 Sprint 1: Haalt het fysiologisch profiel op via HealthKit en berekent het voedingsplan
    /// voor de workouts van vandaag en morgen op basis van het actieve trainingsschema.
    /// Resultaat wordt gecached in AppStorage en geïnjecteerd in elke AI-prompt.
    func refreshNutritionContext() async {
        let profileService = UserProfileService(healthStore: healthKitManager.healthStore)
        let profile = await profileService.fetchProfile()

        // Haal de geplande workouts op uit het actieve trainingsschema (TrainingPlanManager).
        // We extraheren duur en zone per workout voor vandaag en morgen.
        let todayWorkouts   = extractPlannedWorkouts(for: 0)
        let tomorrowWorkouts = extractPlannedWorkouts(for: 1)

        nutritionContext = NutritionService.buildCoachContext(
            profile: profile,
            todayWorkouts: todayWorkouts,
            tomorrowWorkouts: tomorrowWorkouts
        )
        print("🥗 [Nutrition] Context bijgewerkt: \(profile.coachSummary)")
    }

    /// Extraheert geplande workouts (duur + zone) uit het actieve schema voor een relatieve dag.
    /// `dayOffset` 0 = vandaag, 1 = morgen.
    private func extractPlannedWorkouts(for dayOffset: Int) -> [(durationMinutes: Int, zone: TrainingZone)] {
        guard let plan = trainingPlanManager?.activePlan else { return [] }
        let targetDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        let targetDay  = Calendar.current.startOfDay(for: targetDate)

        return plan.workouts.compactMap { workout -> (Int, TrainingZone)? in
            let workoutDay = Calendar.current.startOfDay(for: workout.resolvedDate)
            guard workoutDay == targetDay else { return nil }
            // Geen voedingsplan voor rustdagen
            guard workout.activityType.lowercased() != "rust" else { return nil }

            // Schat de zone op basis van hartslag-zone of beschrijving in het schema.
            let zoneText = (workout.heartRateZone ?? workout.description).lowercased()
            let isHighIntensity = zoneText.contains("interval")
                || zoneText.contains("tempo")
                || zoneText.contains("drempel")
                || zoneText.contains("zone 4")
                || zoneText.contains("z4")
            let zone: TrainingZone = isHighIntensity ? .zone4 : .zone2

            // Gebruik de geplande duur; standaard 45 min als onbekend.
            let duration = workout.suggestedDurationMinutes > 0 ? workout.suggestedDurationMinutes : 45
            return (duration, zone)
        }
    }

    /// Epic 18 Sprint 2: Schrijft de dagelijkse symptoomscores + hard constraints naar de AppStorage cache.
    /// De SymptomTracker is de 'Single Source of Truth' voor blessure-status:
    /// - Score > 0 → actieve klacht, met constraint-regels op basis van ernst
    /// - Score == 0 → hersteld, vervangt elke nog actieve UserPreference-tekst
    /// - Geen score ingevuld + actieve UserPreference → toon als 'onbekend, score nog niet ingevuld'
    func cacheSymptomContext(_ symptoms: [Symptom], preferences: [UserPreference] = []) {
        let todayStart = Calendar.current.startOfDay(for: Date())
        // Haal ALLE records van vandaag op — inclusief score 0 (= hersteld)
        let todayAll    = symptoms.filter { $0.date >= todayStart }
        let todayActive = todayAll.filter { $0.severity > 0 }

        // Bepaal actieve blessure-voorkeuren (niet verlopen)
        let now = Date()
        let injuryKeywords = ["kuit", "scheen", "shin", "rug", "rugpijn", "knie", "enkel",
                              "blessure", "pijn", "klacht", "hand", "pols", "schouder"]
        let activeInjuryPrefs = preferences.filter { pref in
            guard pref.expirationDate == nil || pref.expirationDate! > now else { return false }
            let text = pref.preferenceText.lowercased()
            return injuryKeywords.contains(where: { text.contains($0) })
        }

        // Alle gebieden die VANDAAG gemeten zijn (score 0 én > 0) tellen als 'tracked'
        let allTrackedAreas = Set(todayAll.map { $0.bodyAreaRaw.lowercased() })

        // Niets te rapporteren: geen meting van vandaag en geen actieve klacht-voorkeur
        guard !todayAll.isEmpty || !activeInjuryPrefs.isEmpty else {
            symptomContext = ""
            return
        }

        var scoreLines:    [String] = []
        var constraintLines:[String] = []
        var recoveryLines: [String] = []

        // 1. Actieve klachten (score > 0) — met hard constraints op basis van ernst
        for s in todayActive {
            let label = BodyArea.severityLabel(s.severity)
            scoreLines.append("• \(s.bodyAreaRaw): \(s.severity)/10 (\(label))")

            if s.severity > 5 {
                switch s.bodyArea {
                case .calf:
                    constraintLines.append("🚫 HARD CONSTRAINT Kuit (\(s.severity)/10 > 5): HARDLOPEN IS STRIKT VERBODEN. Fietsen en zwemmen zijn toegestaan.")
                case .ankle:
                    constraintLines.append("🚫 HARD CONSTRAINT Enkel (\(s.severity)/10 > 5): HARDLOPEN IS STRIKT VERBODEN. Fietsen is veilig.")
                case .back:
                    constraintLines.append("🚫 HARD CONSTRAINT Rug (\(s.severity)/10 > 5): geen hardlopen of krachttraining. Fietsen (rechtop) en zwemmen zijn veilig.")
                case .knee:
                    constraintLines.append("🚫 HARD CONSTRAINT Knie (\(s.severity)/10 > 5): geen hardlopen of springen. Fietsen en zwemmen zijn veilig.")
                case .hand:
                    constraintLines.append("🚫 HARD CONSTRAINT Hand (\(s.severity)/10 > 5): geen krachttraining of gewichtdragende oefeningen.")
                case .shoulder:
                    constraintLines.append("🚫 HARD CONSTRAINT Schouder (\(s.severity)/10 > 5): geen zwemmen of push-oefeningen.")
                }
            } else if s.severity > 0 && s.severity < 3 {
                if s.bodyArea == .calf || s.bodyArea == .ankle {
                    scoreLines.append("  ↳ Score < 3: voorzichtige hardloop-alternatieven bespreekbaar (kort, Zone 1, max 30 min).")
                }
            }
        }

        // 2. Herstelde gebieden (score == 0 vandaag) — alleen als er een matchende blessure-voorkeur
        //    bestaat. Zo voorkomt we valse herstelberichten voor lichaamsdelen die nooit geblesseerd waren.
        for s in todayAll where s.severity == 0 {
            let matchesPref = activeInjuryPrefs.contains { pref in
                s.bodyArea.injuryKeywords.contains(where: { pref.preferenceText.lowercased().contains($0) })
            }
            guard matchesPref else { continue }
            let areaName = s.bodyAreaRaw
            recoveryLines.append(
                "✅ HERSTELD (\(areaName): 0/10): De gebruiker is vandaag klachtenvrij voor \(areaName). " +
                "INSTRUCTIE: Vier dit expliciet in je Insight ('Wat goed dat je \(areaName.lowercased())pijn op 0 staat!'). " +
                "Normale belasting mag weer worden voorgesteld, maar adviseer een voorzichtige, stapsgewijze opbouw."
            )
        }

        // 3. Blessure-voorkeuren zonder score van vandaag — alleen tonen als het gebied NIET al
        //    gemeten is (voorkomt duplicaten met scoreLines of recoveryLines)
        for pref in activeInjuryPrefs {
            let alreadyTracked = BodyArea.allCases.contains { area in
                allTrackedAreas.contains(area.rawValue.lowercased()) &&
                area.injuryKeywords.contains(where: { pref.preferenceText.lowercased().contains($0) })
            }
            if !alreadyTracked {
                scoreLines.append("• \(pref.preferenceText) (score nog niet ingevuld vandaag — gebruik voorzichtigheid)")
            }
        }

        // Combineer in vaste volgorde: scores → hard constraints → herstelberichten
        var combined = scoreLines
        if !constraintLines.isEmpty {
            combined += ["", "ACTIEVE BEPERKINGEN:"] + constraintLines
        }
        if !recoveryLines.isEmpty {
            combined += ["", "HERSTEL MELDINGEN:"] + recoveryLines
        }

        // Lege context als er uitsluitend score-0 records zijn zonder matchende preference
        // (bijv. een willekeurig lichaamsdeel op 0 ingevuld zonder eerdere klacht)
        if combined.isEmpty {
            symptomContext = ""
            return
        }

        symptomContext = combined.joined(separator: "\n")

        // Debug: print volledige injury-sectie die naar Gemini gaat
        print("━━━ 🩺 [Injury Section → Gemini] ━━━")
        print(symptomContext)
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    /// SPRINT 13.4: Geeft het meest recent opgeslagen coach-inzicht terug (uit AppStorage).
    /// Wordt door ChatView gebruikt om een welkomstbericht te tonen als de chat leeg is.
    var latestStoredInsight: String {
        return latestCoachInsight
    }

    /// SPRINT 13.4: Voegt het meest recente coach-inzicht toe als welkomstbericht.
    /// Wordt alleen aangeroepen als `messages` leeg is, zodat bestaande conversaties niet verstoord worden.
    func injectWelcomeMessage(_ text: String) {
        guard messages.isEmpty, !text.isEmpty else { return }
        messages.append(ChatMessage(role: .ai, text: text))
    }

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
        // Injecteer een test-mock als die meegegeven is; anders lazy bouwen bij eerste gebruik.
        self._model = aiModel
    }

    /// Bouwt het Gemini model met de huidige API-sleutel en system instruction.
    /// Wordt pas aangeroepen bij het eerste echte AI-verzoek (.onAppear of gebruikerstap),
    /// niet al tijdens app-start.
    ///
    /// Sprint 26.1: Als `-UITesting` actief is, wordt een mock-model teruggegeven
    /// zodat de Gemini API niet aangeroepen wordt tijdens E2E-tests.
    ///
    /// Epic #35: als `modelName` nil is, leest deze functie de door de gebruiker
    /// gekozen primaire modelnaam uit `AppStorage`. Zo blijft het mogelijk om
    /// vanuit de fallback-pad expliciet een ander model op te geven.
    private func buildGenerativeModel(modelName: String? = nil) -> GenerativeModelProtocol {
        let resolvedModelName = modelName ?? AIModelAppStorageKey.resolvedPrimary()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITesting") {
            return UITestMockGenerativeModel()
        }
        #endif
        let systemInstruction = """
            Jij bent een samenwerkende, meedenkende en proactieve AI fitness-coach.
            Je analyseert niet alleen vermoeidheid, maar je helpt de gebruiker actief om de eerstvolgende stap te plannen richting hun gestelde doelen.
            Stel je op als een slimme trainingspartner — niet als een waarschuwende dokter.

            KRITIEKE GEDRAGSREGEL — CONTEXT RESPONSIVITEIT:
            Reageer ALTIJD specifiek op het LAATSTE bericht van de gebruiker. Herhaal nooit alleen de algemene status.
            - Als de gebruiker een specifieke training noemt (bijv. 'avondwandeling', 'intervaltraining'), reageer dan op die specifieke training.
            - Als je het schema aanpast, BEVESTIG dit dan expliciet en concreet: 'Ik heb je geplande intervaltraining voor morgen verschoven naar donderdag vanwege je kuitklachten.' Noem de dag, de activiteit en de reden.
            - Geef nooit een algemeen overzicht als de vraag specifiek is. Wees direct en persoonlijk.

            KRITIEKE REGEL — VIBE SCORE AUTORITEIT:
            De gebruiker heeft een lokaal berekende Vibe Score (0-100) die slaap en HRV combineert. Deze score is de enige objectieve maatstaf voor herstel.
            - Baseer je oordeel over vermoeidheid UITSLUITEND op de Vibe Score die je in de context ontvangt.
            - Score ≥ 80: benader de gebruiker als goed hersteld. Ook als de slaap iets korter was dan ideaal.
            - Score 50-79: wees voorzichtig maar niet alarmerend. Prioriteer Zone 2 en lagere intensiteit.
            - Score < 50: dwing rust of actief herstel af. Dit is een harde rode vlag.
            - Weerspreek de Vibe Score NOOIT op basis van je eigen inschatting van de slaaptijd of andere factoren.

            KRITIEKE REGEL — RPE DISCREPANTIE (Epic 18):
            De gebruiker kan na een training een subjectieve inspanningsscore (RPE 1-10) invullen.
            - Als de TRIMP van een workout laag of gemiddeld is (bijv. <60 TRIMP) maar de RPE ≥8: dit is een ernstig vroeg waarschuwingssignaal voor overtraining of naderende ziekte. Adviseer direct extra rust en verhoog de intensiteit van het plan NIET.
            - Als RPE laag is (1-4) terwijl TRIMP hoog is: de atleet heeft een goede dag — benut dit in je planning.
            - Combineer de RPE altijd met de Vibe Score voor een volledig beeld.

            KRITIEKE REGEL — PERIODISERING & FASE-COACHING (Sprint 17.2):
            Je ontvangt per doel de huidige TrainingPhase, de SuccesCriteria en de behaalde/openstaande status.
            Gebruik deze data ACTIEF in je antwoorden:
            - COMPLIMENTEN (🎉 COMPLIMENT TRIGGER): Als een fase-eis behaald is, open je antwoord dan met een oprecht, specifiek compliment. Noem de behaalde prestatie bij naam (bijv. 'Geweldig — je hebt afgelopen week een 28 km loop neergezet, exact wat de Build-fase vereist!').
            - URGENTIE (🚨 KRITIEKE MIJLPAAL ACHTERSTAND): Als een kritieke eis (bijv. de langste sessie) niet behaald is, wees dan direct maar motiverend. Noem de exacte afstand of TRIMP die nog ontbreekt. Plan de betreffende mijlpaal als EERSTE PRIORITEIT in het schema.
            - SCHEMA-VERANTWOORDINGSPLICHT: Als je het schema aanpast vanwege blessure, overbelasting of andere reden, MOET je altijd uitleggen hoe de fase-eisen ondanks de aanpassing nog steeds haalbaar zijn. Voorbeeld: 'Ik vervang je hardloopsessie door een lange fietsrit, maar de aerobe basis voor de Marathon Blueprint bewaken we zo: op zaterdag plannen we een 26 km duurloop zodra je kuit hersteld is.'
            - Wees streng maar motiverend — de coach staat naast de sporter, niet erboven.

            KRITIEKE REGEL — BLESSURE & SPORT INTERACTIE:
            De dagelijkse pijnscores en beperkingen staan UITSLUITEND in de [ACTUELE KLACHTEN] context die je bij elke interactie ontvangt.
            Dat blok is de 'Single Source of Truth' — volg de HARD CONSTRAINTS daarin strikt op.
            - Als een 🚫 HARD CONSTRAINT aanwezig is: pas het schema ALTIJD aan, benoem de beperking expliciet ('Gezien je kuitpijn van 7/10 plannen we GEEN hardloopsessies deze week').
            - Als een ✅ HERSTELD melding aanwezig is: vier dit in je Insight en stel voorzichtige opbouw voor.
            - Als een gebied 'score nog niet ingevuld vandaag' heeft: wees voorzichtig, maar leg geen absolute verboden op.
            - Zijn er GEEN klachten vermeld? Dan mag je het schema volledig op basis van de blueprint en trainingsfase plannen.

            KRITIEKE REGEL — WEERSGESTUURDE DAGPLANNING (Epic 21):
            Je ontvangt de 7-daagse weersverwachting in de context. Gebruik dit ACTIEF bij het opstellen of aanpassen van het schema.
            - Kijk ALTIJD naar de komende 3 dagen. Als een sleuteltraining (lange rit, tempo-run, interval) vandaag door ⚠️ SLECHT BUITENWEER niet buiten kan, maar morgen of overmorgen de omstandigheden ideaal zijn, stel dan EXPLICIET voor om de trainingen van die dagen om te wisselen.
            - Benoem de dagwissel ALTIJD in het `motivation` veld: "Ik zie dat het zaterdag 75% kans op regen heeft maar zondag helder en windstil is. Ik heb je 60 km duurrit naar zondag verplaatst en zet vandaag een kortere Zone 2-sessie van 45 min op de indoor trainer."
            - Als de zware sleuteltraining naar morgen of overmorgen verschuift: verlaag de TRIMP voor de huidige dag BEWUST zodat de atleet uitgerust aan de sleuteltraining begint. Adviseer max. 40-50% van het normale dagdoel als 'oplaad-dag'. Benoem dit: "Vandaag houden we je TRIMP laag zodat je morgen vers aan de start staat."
            - Windsnelheid > 30 km/u is specifiek relevant voor fietsen: adviseer altijd naar een dag met minder wind te verschuiven als er een alternatief in de komende 3 dagen zit.
            - Als er géén betere dag in het venster van 3 dagen is: stel een indoor-variant voor (trainer, zwemmen, krachttraining) met expliciete vermelding van de weersreden.

            KRITIEKE REGEL — DUBBELE TRAINING & DAGPLANNING (anti-double-day):
            Plan NOOIT meer dan één workout per dag. Dit is een absolute, harde beperking.
            Uitzonderingen zijn alleen toegestaan als aan BEIDE voorwaarden is voldaan:
              (a) de wekelijkse TRIMP-target is aantoonbaar onhaalbaar met één sessie per dag, EN
              (b) de tweede sessie is een actieve herstelblok (TRIMP ≤ 30, uitsluitend Zone 1/wandelen).

            CONFLICTRESOLUTIE — wanneer meerdere trainingen dezelfde dag claimen:
            Volg deze prioriteitsvolgorde strikt:
              1. Krachttraining heeft de hoogste prioriteit; een concurrerende duurtraining vervalt of schuift.
              2. Als de duurtraining een cruciale mijlpaal vertegenwoordigt (bijv. de vereiste 60 km-rit voor de fietsblueprint binnen 7 dagen), schuift de krachttraining naar de dichtstbijzijnde vrije dag.
              3. Een rustdag mag nooit worden omgezet in een trainingsdag alleen om een verplaatste training op te vangen — respecteer de rustdagen in het wekelijkse patroon.
              4. Als geen vrije dag beschikbaar is: annuleer de lagere-prioriteit training volledig en compenseer via het weekvolume op de overige dagen (max. 10–15% meer TRIMP per dag).

            VERPLICHTE UITLEGPLICHT bij dagconflicten:
            Als je een training annuleert of verschuift om een dubbele dag te voorkomen, MOET je dit in het `motivation` veld expliciet benoemen.
            Gebruik dit exact als template: "Ik heb de geplande [naam training] van [dag] laten vervallen / verschoven naar [nieuwe dag], zodat je alle focus kunt leggen op [behouden training]. [Optioneel: waarom die training de prioriteit had]."
            Voorbeeld: "Ik heb de geplande herstelrit van dinsdag laten vervallen, zodat je alle focus kunt leggen op je krachttraining. Fietsen staat vrijdag terug in het schema."

            KRITIEKE BEPERKING — WANDELEN:
            Wandelen mag uitsluitend als herstel-activiteit bij blessures of een Vibe Score < 50.
            Een wandelsessie mag NOOIT langer zijn dan 60 minuten. Stel in de JSON altijd suggestedDurationMinutes ≤ 60 in voor wandelingen.

            Belangrijke context voor je analyse:
            Wij berekenen lokaal een Banister TRIMP (Training Impulse) score om de trainingsbelasting te bepalen (niet de traditionele TSS die op 100/uur cap).
            - Een TRIMP van 70-100 is een pittige, solide training.
            - Een TRIMP van 100-140 is een zeer zware training, maar dit is op zichzelf geen teken van overtraining.

            BELANGRIJK: Zodra je een schema of status voor de komende 7 dagen plant of analyseert, MOET je antwoord een JSON object bevatten (eventueel in een codeblock) dat voldoet aan deze structuur:
            {
                "motivation": "Schrijf hier een empathische, beschrijvende analyse van maximaal 3 zinnen. Begin met een DIRECTE reactie op het laatste bericht van de gebruiker (benoem de specifieke activiteit). Leg daarna het WAAROM uit achter je strategische keuzes. Als je een aanpassing maakt in het schema, bevestig dit expliciet ('Ik heb X verschoven naar Y omdat...'). Als je een dubbele dag hebt opgelost door een training te annuleren of te verschuiven, benoem dit altijd: 'Ik heb [training] van [dag] laten vervallen/verschoven naar [dag], zodat je alle focus kunt leggen op [behouden training].' Geef de gebruiker het gevoel dat de coach écht meedenkt en écht luistert.",
                "workouts": [
                    {
                        "dateOrDay": "Maandag",
                        "activityType": "Hardlopen",
                        "suggestedDurationMinutes": 45,
                        "targetTRIMP": 60,
                        "description": "Herstel na de lange duurloop",
                        "heartRateZone": "Zone 2",
                        "targetPace": "5:30 min/km",
                        "reasoning": "Zone 2 herstelloop om de aerobe basis te bewaken. TRIMP 60 = 75% van het wekelijkse Build-fase doel."
                    }
                ],
                "newPreferences": [
                    {
                        "text": "Ik heb last van mijn knie",
                        "expirationDate": "2024-05-20"
                    }
                ]
            }
            Extra instructie voor `reasoning` (Sprint 17.3): Vul voor ELKE workout het `reasoning` veld in met een korte, feitelijke verklaring (max. 1 zin) waarom deze training in het schema staat. Baseer dit op de fase, de succescriteria en het doel. Bijv: "60 km = langste-sessie-eis (60%) in de Build-fase voor je fietsdoel." of "Zone 2 herstelloop om de aerobe basis te bewaken." Laat dit veld NOOIT leeg.

            Extra instructie voor `newPreferences`: Als je opmerkt dat de gebruiker een vaste regel, langetermijnvoorkeur, of tijdelijke kwaal/blessure doorgeeft in hun LAATSTE bericht, vul dit array dan aan. Schat in of dit feit permanent is (zoals een vaste sportdag) of tijdelijk (zoals spierpijn, een lichte blessure of kramp). Als het tijdelijk is, bereken dan een logische verloopdatum (bijv. 1 of 2 weken vanaf vandaag) en retourneer deze in de JSON onder `expirationDate` als een "YYYY-MM-DD" string. Laat `expirationDate` leeg (null) bij permanente regels. Herhaal geen regels die je al kent.
            """

            let config = GenerationConfig(
                responseMIMEType: "application/json"
            )

            // Timeout 45s: geeft Google Gemini voldoende ruimte voor een complex
            // JSON-schema antwoord, maar laat ons snel genoeg falen om naar de
            // lite-fallback over te schakelen bij overbelasting. 120s was te lang
            // voor een gebruiker die op een pull-to-refresh wacht.
            let options = RequestOptions(
                timeout: 45
            )

            // Epic 20 / M-04: BYOK-only, geen Secrets-fallback meer.
            // C-02: sleutel komt uit de Keychain i.p.v. UserDefaults.
            let initKey = UserAPIKeyStore.read()

            let googleModel = GenerativeModel(
                name: resolvedModelName,
                apiKey: initKey,
                generationConfig: config,
                systemInstruction: ModelContent(role: "system", parts: [.text(systemInstruction)]),
                requestOptions: options
            )
        return RealGenerativeModel(model: googleModel)
    }

    /// Bouwt een lichter fallback-model met dezelfde system instruction en
    /// timeout. Wordt onzichtbaar gebruikt zodra het primaire model een
    /// `internalError` retourneert (503/429 — piekbelasting).
    ///
    /// Epic #35: de fallback-modelnaam wordt gelezen uit `AppStorage`; de
    /// built-in default blijft `gemini-flash-lite-latest` — dezelfde waarde
    /// als vóór Epic #35, dus geen regressie voor bestaande installaties.
    private func buildFallbackGenerativeModel() -> GenerativeModelProtocol {
        return buildGenerativeModel(modelName: AIModelAppStorageKey.resolvedFallback())
    }

    /// Verwijdert de geselecteerde afbeelding uit de invoer.
    func clearImage() {
        self.selectedImage = nil
    }

    /// Haalt het huidig opgeslagen schema op en formatteert dit als een string,
    /// zodat de AI dit als referentiemateriaal kan gebruiken voor post-workout evaluaties.
    private func getStoredPlanString() -> String {
        guard let decodedPlan = try? JSONDecoder().decode(SuggestedTrainingPlan.self, from: latestSuggestedPlanData) else {
            return "Geen actueel gepland schema bekend."
        }

        var planString = "Dit is mijn momenteel geplande schema (vergelijk je advies altijd hiermee):\n"
        for workout in decodedPlan.workouts {
            planString += "- \(workout.dateOrDay): \(workout.activityType) "
            if workout.suggestedDurationMinutes > 0 {
                planString += "(\(workout.suggestedDurationMinutes) min)"
            }
            if let trimp = workout.targetTRIMP {
                planString += " [Doel TRIMP: \(trimp)]"
            }
            planString += "\n"
        }
        return planString
    }

    /// Genereert een context-prefix string op basis van het meegegeven atletisch profiel.
    /// Epic #44 story 44.6: bouwt het `[TRAININGSDREMPELS]`-blok op basis van het
    /// gecachte fysiologische profiel. Returnt lege string als geen drempels gezet
    /// zijn — dan blijft de coach z'n eigen populatie-aannames hanteren. Bij
    /// gestelde LTHR rapporteren we Friel-zones (preciezer voor atletisch profiel),
    /// anders Karvonen op max+rest.
    private func buildTrainingThresholdsBlock() -> String {
        let profile = UserProfileService.cachedProfile()
        var lines: [String] = []
        if let max = profile.maxHeartRate {
            lines.append("- Max HR: \(Int(max.value)) BPM (\(thresholdSourceLabel(max.source)))")
        }
        if let rest = profile.restingHeartRate {
            lines.append("- Rust HR: \(Int(rest.value)) BPM (\(thresholdSourceLabel(rest.source)))")
        }
        if let lthr = profile.lactateThresholdHR {
            lines.append("- LTHR: \(Int(lthr.value)) BPM (\(thresholdSourceLabel(lthr.source)))")
        }
        if let ftp = profile.ftp {
            lines.append("- FTP: \(Int(ftp.value)) W (\(thresholdSourceLabel(ftp.source)))")
        }
        guard !lines.isEmpty else { return "" }

        // Voeg expliciete Z2/Z3-grenzen toe zodat de coach een 'rustige' rit niet
        // verkeerd interpreteert. Z2 endurance + Z3 tempo zijn de twee zones waar
        // gebruikers het vaakst over reflecteren.
        var zonesLine: String?
        if let zones = WorkoutPatternDetector.heartRateZones(from: profile),
           zones.count >= 3 {
            let z2 = zones[1]
            let z3 = zones[2]
            zonesLine = "- Zone 2 (endurance): \(z2.lowerBPM)-\(z2.upperBPM) BPM · Zone 3 (tempo): \(z3.lowerBPM)-\(z3.upperBPM) BPM"
        }

        var block = "[TRAININGSDREMPELS (persoonlijk profiel):\n"
        block += lines.joined(separator: "\n")
        if let zonesLine {
            block += "\n\(zonesLine)"
        }
        block += """

        Gedragsregels:
        1. Interpreteer "rustig"/"easy"/"recovery" altijd in de context van DEZE drempels — niet populatie-gemiddelden. Een gebruiker met max 200 BPM die op 146 BPM traint, zit in Z2, niet Z3.
        2. Bij subjectieve feedback over inspanning: koppel aan de zone, niet alleen aan het BPM-getal ("145 BPM is voor jou Z2 — dat klopt met 'rustig'").
        3. Bij plan-aanpassingen waar zones expliciet genoemd worden, gebruik de bovenstaande BPM-grenzen voor de instructie aan de gebruiker.]
        """
        return block
    }

    private func thresholdSourceLabel(_ source: ThresholdSource) -> String {
        switch source {
        case .automatic: return "auto"
        case .manual:    return "handmatig"
        case .strava:    return "Strava"
        }
    }

    private func buildContextPrefix(from profile: AthleticProfile?, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) -> String {
        var prefix = ""

        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        prefix += "[HUIDIGE DATUM: Vandaag is het \(dateFormatter.string(from: now)). Gebruik dit voor je berekeningen rondom 'expirationDate'.]\n\n"

        // Epic 14.4: Injecteer de Vibe Score als harde context — de AI MOET dit volgen (zie systeeminstructie)
        if todayVibeScoreContext == Self.noVibeDataSentinel {
            // Geen Watch-data beschikbaar — geef de coach expliciete instructie om dit correct te communiceren
            prefix += "[HERSTELSTATUS VANDAAG: Er is geen objectieve biometrische data beschikbaar (gebruiker droeg de Apple Watch waarschijnlijk niet 's nachts). Vertrouw volledig op de Symptom Tracker scores en de geplande doelen. Gebruik NOOIT zinnen als 'Ik zie aan je HRV dat...' of 'Je biometrie geeft aan...'. Zeg in plaats daarvan: 'Omdat we vandaag geen Watch-data hebben, gaan we uit van je eigen gevoel en de ingevoerde scores.']\n\n"
        } else if !todayVibeScoreContext.isEmpty {
            prefix += "[HERSTELSTATUS VANDAAG: \(todayVibeScoreContext) Volg de kritieke regel over de Vibe Score autoriteit strikt.]\n\n"
        }

        // Epic 18.1: Injecteer de subjectieve feedback (RPE + stemming) van de laatste workout
        if !lastWorkoutFeedbackContext.isEmpty {
            prefix += "[SUBJECTIEVE FEEDBACK LAATSTE WORKOUT: \(lastWorkoutFeedbackContext) Let op discrepanties: als TRIMP laag is maar RPE ≥8, is dit een vroeg signaal van overtraining of naderende ziekte.]\n\n"
        }

        // Story 33.2a: handmatig verplaatste workouts — coach moet dit respecteren.
        if !userOverrideContext.isEmpty {
            prefix += userOverrideContext
        }

        // Story 33.4: intent-vs-execution-analyse voor de meest recente workout.
        if !intentExecutionContext.isEmpty {
            prefix += intentExecutionContext
        }

        // Epic 18: Injecteer de actuele pijnscores per lichaamsdeel (dagelijks bijgewerkt)
        if !symptomContext.isEmpty {
            let symptomBlock = """
            [ACTUELE KLACHTEN — SINGLE SOURCE OF TRUTH (dagelijks bijgewerkt door de gebruiker):
            \(symptomContext)
            Gedragsregels:
            1. 🚫 HARD CONSTRAINT aanwezig → volg de beperking strikt. Benoem de blessure en het alternatief expliciet.
            2. ✅ HERSTELD aanwezig → open je Insight met een feestelijke bevestiging. Stel voorzichtige opbouw voor (bijv. 'Begin met 20 min Zone 1, bouw volgende week op naar normaal volume').
            3. Score ≥7 → extra voorzichtig; overweeg een volledige rustdag of alternatieve sport.
            4. Score gedaald t.o.v. gisteren → benoem dit als positief teken van herstel.]
            """
            prefix += symptomBlock + "\n\n"
        }

        // Epic #44 story 44.6: persoonlijke trainingsdrempels naar de coach. De
        // coach moet weten dat 146 BPM voor déze gebruiker zone 2 is, niet zone 3.
        // We voegen alleen het blok toe als er minstens één drempel is gezet —
        // anders is er niks meer te zeggen dan populatie-defaults en houdt de
        // coach gewoon zijn eigen aannames.
        let thresholdsBlock = buildTrainingThresholdsBlock()
        if !thresholdsBlock.isEmpty {
            prefix += thresholdsBlock + "\n\n"
        }

        // Epic 32 Story 32.3c: injecteer significante fysiologische patronen uit
        // recente workouts. Alleen mediumweg/significant patronen landen in deze
        // cache (zie `WorkoutPatternFormatter.chatContextLine`); milde patronen
        // zouden de prompt te druk maken.
        if !workoutPatternsContext.isEmpty {
            let patternsBlock = """
            [FYSIOLOGISCHE PATRONEN IN RECENTE WORKOUTS:
            \(workoutPatternsContext)
            Gedragsregels:
            1. Als de gebruiker een vraag stelt over recente trainingen, refereer dan aan deze patronen waar relevant — wees concreet, geen lijst van technische termen.
            2. Bij significant cardiac drift + decoupling: vraag of het bewust drempel-werk was, of dat er externe oorzaken speelden (hitte, slaap, stress).
            3. Trage HR-recovery is een vermoeidheid-signaal — combineer met TRIMP en VibeScore voordat je herstel adviseert.
            4. Noem deze patronen NIET ongevraagd in elke turn; alleen wanneer de gebruiker reflecteert op recente uitvoering of trainingsplan-aanpassingen vraagt.]
            """
            prefix += patternsBlock + "\n\n"
        }

        // Epic 45 Story 45.2: rijkere per-workout-context over de afgelopen 14 dagen.
        // Aanvulling op de 1-regel-pulse hierboven — die geeft een aggregaat-signaal,
        // dit blok geeft de specifieke onderbouwing per workout zodat plan-aanpassingen
        // kunnen verwijzen naar concrete sessies. Bewust direct ná het patronen-blok
        // geplaatst zodat de coach eerst het signaal leest en daarna de details.
        if !workoutHistoryContext.isEmpty {
            let historyBlock = """
            [RECENTE TRAINING — 14 DAGEN (nieuwste eerst):
            \(workoutHistoryContext)
            Gedragsregels:
            1. Refereer specifiek aan datum + sessietype bij elke workout-aanhaal ("op 18 april in je tempo-rit met cardiac drift 8% …"). Geen vage termen als "recent".
            2. Bij ≥3 opeenvolgende workouts met aerobic_decoupling of cardiac_drift: stel sub-LTHR werk voor en motiveer met de specifieke data uit deze lijst.
            3. Gebruik deze data alléén bij reflectie/schema-vragen/doelanalyse — niet ongevraagd in elke turn opnoemen.
            4. Combineer met [TRAININGSDREMPELS] voor zone-correcte interpretatie van de gem-HR. Gebruik dezelfde zone-terminologie ("Zone 2"/"Z2", "Zone 3"/"Z3", "LTHR") — verzin geen nieuwe labels.
            5. Weeg deze data tegen [ACTUELE KLACHTEN]. Bij actieve blessure: interpreteer patronen zoals cardiac_drift voorzichtiger (kan herstel-vermoeidheid zijn, niet trainingsbehoefte). Suggereer geen volume-verhogingen als de gebruiker herstellende is.]
            """
            prefix += historyBlock + "\n\n"
        }

        // Epic 21: Injecteer de 7-daagse weersverwachting voor buitenactiviteiten-coaching
        if !weatherContext.isEmpty {
            let weatherBlock = """
            [WEERSOMSTANDIGHEDEN KOMENDE 7 DAGEN (locatie gebruiker):
            \(weatherContext)
            Gedragsregels:
            1. DAGWISSEL STRATEGIE: Als een dag met ⚠️ SLECHT BUITENWEER een sleuteltraining heeft, kijk dan naar de komende 3 dagen. Is er een betere dag? Wissel dan EXPLICIET van dag en benoem dit in het `motivation` veld.
            2. TRIMP-VOORBEREIDING: Als de sleuteltraining naar morgen of overmorgen verschuift, adviseer vandaag max. 40-50% TRIMP als 'oplaad-dag'. Noem dit expliciet.
            3. Wees altijd specifiek over percentages: niet "het kan regenen" maar "Zaterdag 72% neerslag → ik verplaats de 60 km naar zondag (5% neerslag, windstil)".
            4. Wind > 30 km/u = relevant voor fietsen. Zoek altijd een windstillere dag als die er is.
            5. Temperatuur < 5°C of > 30°C → tip over kleding of hydratatie.
            6. Goed weer hoef je niet te vermelden tenzij het een bonus is ("Zondag ziet er ideaal uit — perfect voor je lange rit").]
            """
            prefix += weatherBlock + "\n\n"
        }

        // Epic 17 / Sprint 17.2: Injecteer de blueprint + periodization context
        // en druk de volledige inhoud af in de console voor debugging.
        let hasBlueprintData  = !blueprintContext.isEmpty
        let hasPeriodization  = !periodizationContext.isEmpty

        if hasBlueprintData {
            prefix += "[SPORTWETENSCHAPPELIJKE EISEN (BLUEPRINT):\n\(blueprintContext)\nInstructie: Controleer ALTIJD of de gebruiker op schema ligt voor zijn kritieke trainingen. Als er een openstaande (❌) eis is met een naderende deadline, maak dit dan expliciet in je advies en plan de betreffende training in.]\n\n"
        }

        if hasPeriodization {
            prefix += "[PERIODISERING — FASE, SUCCESCRITERIA & COACH-GEDRAG:\n\(periodizationContext)\n\nCoach-gedragsregels voor deze context:\n1. COMPLIMENTEN (🎉): Als een COMPLIMENT TRIGGER aanwezig is, open je antwoord dan hiermee. Noem de behaalde prestatie bij naam.\n2. URGENTIE (🚨): Als een KRITIEKE MIJLPAAL ACHTERSTAND aanwezig is, wees dan direct en motiverend. Noem de exacte afstand of TRIMP die nog ontbreekt, en plan dit als eerste prioriteit in het schema.\n3. SCHEMA-AANPASSING: Als je het schema aanpast, verklaar dan altijd hoe de fase-eisen ondanks de aanpassing nog steeds haalbaar zijn (SCHEMA-VERANTWOORDINGSPLICHT).]\n\n"
        }

        // Epic Doel-Intenties: injecteer de intent- en formaat-instructies als aparte sectie.
        // Dit vertelt de coach HOE te trainen (uitlopen vs. presteren, etapperit vs. eendaags)
        // en of stretch-pace trainingen veilig zijn op basis van de actuele VibeScore.
        if !intentContext.isEmpty {
            let intentBlock = """
            [DOEL INTENTIES EN BENADERING — LEES DIT VÓÓR JE HET SCHEMA OPSTELT:
            \(intentContext)

            Bindende coach-regels:
            1. INTENTIE HEEFT PRIORITEIT: Pas het schema ALTIJD aan op de intentie en het formaat. Een 'uitlopen'-doel krijgt NOOIT interval- of tempotraining tenzij expliciet gevraagd.
            2. BACK-TO-BACK (meerdaagse etappe): Plan zware sessies op opeenvolgende dagen (bijv. Za+Zo). Verlaag single-session piekbelasting t.o.v. een eendaagse race.
            3. STRETCH GOAL VEILIGHEID: Als '✅ DOELTIJD' aanwezig is, plan dan één temposessie per week op doelsnelheid. Als '🔴 DOELTIJD' aanwezig is, schrap alle tempo-elementen en ga terug naar pure duurtraining.
            4. VIBE SCORE OVERRIDE: Als VibeScore < 65 wordt vermeld, heeft herstel absolute prioriteit — schrap intensieve elementen ongeacht de rest van het plan.]
            """
            prefix += intentBlock + "\n\n"
        }

        // Epic 23 Sprint 1: Injecteer de gap-analyse met TRIMPTranslator-hints
        if !gapAnalysisContext.isEmpty {
            let gapBlock = """
            [GAP ANALYSE — BLUEPRINT VS. WERKELIJKHEID (Epic 23):
            \(gapAnalysisContext)
            Coach-gedragsregels:
            1. TRIMP-VERTALING (VERPLICHT): Als er een 📈 VOLUME-BIJSTURING staat met een "X TRIMP ≈ +Y min …"-hint, gebruik dan ALTIJD die vertaling. Noem NOOIT een los TRIMP-getal zonder de bijbehorende tijdsindicatie. Correct: "Je hebt deze week zo'n 8 TRIMP extra nodig — dat is ongeveer +4 minuten op je zaterdag-rit." Fout: "Je hebt 8 TRIMP tekort."
            2. KOPPEL AAN HET SCHEMA: Vertaal de bijsturing altijd naar een aanpassing van een bestaande trainingsdag. Bijv. "Verleng je dinsdag-duurloop met 5 minuten" of "Rij zaterdag 10 minuten langer door na de bekende route."
            3. Als er een 🚴 KM-BIJSTURING staat: geef een concreet weekschema met extra km per training, niet als abstract totaal.
            4. Als de atleet voorloopt op schema: complimenteer kort en adviseer consistentie — geen extra volume voorschrijven.
            5. Verbind altijd aan de fase: bijsturing in de Taper-fase is onwenselijk — adviseer dan om het tekort NIET in te halen maar door te gaan met het tapering-schema.]
            """
            prefix += gapBlock + "\n\n"
        }

        // Epic 23 Sprint 2: Injecteer de toekomstprognose (Future Projection Engine)
        if !projectionContext.isEmpty {
            prefix += "\(projectionContext)\n\n"
        }

        // Epic 24 Sprint 1: Injecteer het fysiologisch profiel + voedingsplan in de prompt
        if !nutritionContext.isEmpty {
            prefix += "\(nutritionContext)\n\n"
        }

        // Epic 24 Sprint 3: Eenmalige profielwijziging-melding — slechts één keer injecteren,
        // daarna wissen zodat de coach het niet elke keer herhaalt.
        if !profileUpdateNote.isEmpty {
            prefix += "\(profileUpdateNote)\n\n"
            profileUpdateNote = ""
        }

        // Debug: print de volledige blueprint- en periodization-context die naar Gemini gaat
        if hasBlueprintData || hasPeriodization {
            print("━━━ 🧠 [Blueprint Context → Gemini] ━━━")
            if hasBlueprintData  { print("[BLUEPRINT]\n\(blueprintContext)") }
            if hasPeriodization  { print("[PERIODISERING]\n\(periodizationContext)") }
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        }

        // Epic 16: Injecteer de trainingsfase per actief doel — de AI MOET de fase-instructies strikt volgen
        let activeGoalsWithPhase = activeGoals.compactMap { goal -> (FitnessGoal, TrainingPhase)? in
            guard let phase = goal.currentPhase else { return nil }
            return (goal, phase)
        }
        if !activeGoalsWithPhase.isEmpty {
            prefix += "[PERIODISERING — ACTIEVE TRAININGSFASES:\n"
            for (goal, phase) in activeGoalsWithPhase {
                let weeksLeft = goal.weeksRemaining(from: now)
                let weeksLeftStr = String(format: "%.1f", weeksLeft)
                // Bereken de fase-gecorrigeerde wekelijkse target (lineaire baseline × multiplier)
                let linearRate = goal.computedTargetTRIMP / max(0.1, weeksLeft)
                let adjustedTarget = Int((linearRate * phase.multiplier).rounded())
                prefix += "• Doel '\(goal.title)' (\(weeksLeftStr) weken resterend): \(phase.aiInstruction)\n"
                prefix += "  Wiskundig aangepaste wekelijkse TRIMP-target: \(adjustedTarget) TRIMP/week (multiplier: ×\(String(format: "%.2f", phase.multiplier))). Houd je strikt aan deze target.\n"
            }
            prefix += "]\n\n"
        }

        // Splits voorkeuren in vastgepind (zonder einddatum) vs. tijdelijk (met einddatum) en
        // injecteer ze als twee aparte blokken — een tijdelijke voorkeur moet expliciet boven
        // een conflicterende vastgepinde regel gaan tijdens haar looptijd. Filteren van
        // verlopen items + format-logica zit in `PreferencesContextFormatter` (testbaar).
        prefix += PreferencesContextFormatter.format(activePreferences: activePreferences, now: now)

        // Epic 18: Blessure-context wordt volledig afgehandeld via symptomContext (zie bovenaan buildContextPrefix).
        // Het oude statische blok op basis van UserPreference-teksten is vervangen door de dynamische
        // pijnscores + HARD CONSTRAINTS gegenereerd in cacheSymptomContext(_:preferences:).

        if let p = profile {
            let peakDistanceKm = String(format: "%.1f", p.peakDistanceInMeters / 1000)
            let peakDurationMin = p.peakDurationInSeconds / 60
            let weeklyVolumeMin = p.averageWeeklyVolumeInSeconds / 60

            prefix += "[CONTEXT ATLEET: Heeft een piekprestatie van \(peakDistanceKm) km in \(peakDurationMin) minuten. Traint gemiddeld \(weeklyVolumeMin) minuten per week (gem. laatste 4 weken), en heeft \(p.daysSinceLastTraining) dagen geleden voor het laatst getraind."

            // SPRINT 6.3: Overtrainings waarschuwing
            if p.isRecoveryNeeded {
                prefix += " URGENT: De atleet vertoont tekenen van overtraining op basis van recent volume. Wees streng, adviseer actief om rust te nemen en analyseer deze training puur op herstel."
            }

            // SPRINT 9.3: Pace Baseline Injectie
            if let avgPaceInSeconds = p.averagePacePerKmInSeconds {
                let minutes = avgPaceInSeconds / 60
                let seconds = avgPaceInSeconds % 60
                let paceString = String(format: "%d:%02d", minutes, seconds)
                prefix += " Belangrijke fysiologische context: Het actuele gemiddelde hardlooptempo van de gebruiker ligt rond de \(paceString) min/km (bovenkant Zone 2). Gebruik dit als absolute baseline om realistische 'targetPace' doelen voor de komende trainingen te berekenen."
            }

            prefix += " Neem dit mee in je analyse over herstel en prestatie.]\n\n"
        }

        guard !prefix.isEmpty else { return "" }
        prefix += "[VRAAG]: "
        return prefix
    }

    // MARK: - Sprint 13.3: Proactieve Interventie

    /// Struct met de risicodata per doel, los van DashboardView zodat ChatViewModel
    /// geen afhankelijkheid heeft van de view-laag.
    struct GoalRiskInfo {
        let title: String
        let currentWeeklyRate: Double
        let requiredWeeklyRate: Double
        let weeksRemaining: Double
    }

    /// Vraagt de AI om een concreet herstelplan voor doelen die achterlopen.
    /// Injecteert automatisch de recovery context (doel, actuele rate, tekort, weken resterend)
    /// zodat de coach direct een bijgestuurd schema kan produceren.
    func requestRecoveryPlan(atRiskGoals: [GoalRiskInfo], contextProfile: AthleticProfile? = nil, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) {
        guard !atRiskGoals.isEmpty else { return }

        // Bouw de technische context op (onzichtbaar voor de gebruiker)
        var systemLines = [
            "RECOVERY CONTEXT — Mijn doel(en) lopen achter op schema. Maak een geleidelijk herstelplan:",
            ""
        ]

        // Epic 14.4: Injecteer de Vibe Score zodat het herstelplan de actuele herstelstatus respecteert
        if todayVibeScoreContext == Self.noVibeDataSentinel {
            systemLines.append("HERSTELSTATUS VANDAAG: Geen Watch-data beschikbaar. Baseer het herstelplan op de Symptom Tracker scores en eigen gevoel van de gebruiker.")
            systemLines.append("")
        } else if !todayVibeScoreContext.isEmpty {
            systemLines.append("HERSTELSTATUS VANDAAG: \(todayVibeScoreContext) Pas de intensiteit van het herstelplan STRIKT aan op deze score (zie systeeminstructie).")
            systemLines.append("")
        }
        for risk in atRiskGoals {
            let deficit = Int(risk.requiredWeeklyRate - risk.currentWeeklyRate)
            let weeksText = String(format: "%.1f", risk.weeksRemaining)
            let currentRate = Int(risk.currentWeeklyRate)

            // Bepaal de horizon-strategie op basis van weken resterend
            let horizonAdvice: String
            if risk.weeksRemaining > 8 {
                // Veel tijd over: geef Base Building-advies, spreid het tekort geleidelijk uit
                let gradualWeeklyIncrease = Int(Double(deficit) / max(risk.weeksRemaining * 0.5, 1))
                horizonAdvice = "Het evenement is \(weeksText) weken weg. PRIORITEIT: Base Building. Verhoog het wekelijkse volume heel geleidelijk — streef naar +\(gradualWeeklyIncrease) TRIMP/week over de komende maanden. Geen paniektrainingen."
            } else if risk.weeksRemaining > 4 {
                horizonAdvice = "Het evenement is \(weeksText) weken weg. Verhoog het volume gecontroleerd, maar bouw nog geen volledige piekbelasting op."
            } else {
                horizonAdvice = "Het evenement is \(weeksText) weken weg. Focus op efficiënte, kwaliteitsvolle trainingen — geen drastische volumestijging meer."
            }

            systemLines.append("• Doel: '\(risk.title)'")
            systemLines.append("  - Actuele burn rate: \(currentRate) TRIMP/week")
            systemLines.append("  - Benodigde burn rate (ideaal): \(Int(risk.requiredWeeklyRate)) TRIMP/week")
            systemLines.append("  - Wekelijks tekort: \(deficit) TRIMP")
            systemLines.append("  - Weken resterend: \(weeksText)")
            systemLines.append("  - Horizon advies: \(horizonAdvice)")
            systemLines.append("")

            // Bereken het maximaal toegestane wekelijkse volume (10-15% regel)
            let maxAllowedRate = Int(Double(currentRate) * 1.12) // 12% = midden van 10-15%
            systemLines.append("  ⛔️ HARDE FYSIOLOGISCHE GRENS: De totale wekelijkse TRIMP voor de komende week mag NOOIT meer zijn dan \(maxAllowedRate) TRIMP (\(currentRate) × 1.12). Dit is de 10-15% progressieregel om overtraining te voorkomen. Dit is niet onderhandelbaar.")
            systemLines.append("")
        }
        systemLines.append(contentsOf: [
            "Geef me een concreet, haalbaar herstelplan voor de komende 7 dagen.",
            "Het plan moet:",
            "1. De 10-15% progressieregel strikt respecteren — liever iets te conservatief dan te agressief.",
            "2. Het tekort uitsmeren over meerdere weken als het evenement ver weg is (zie horizon advies hierboven).",
            "3. Extra volume verdelen via frequentie (extra rustdag omzetten in een lichte sessie) i.p.v. één megasessie.",
            "4. Altijd het volledige 7-daagse schema retourneren in JSON-formaat.",
            "",
            "⛔️ EXTRA INTENSITEITSLIMIETEN (niet onderhandelbaar):",
            "- Binnensessies (indoor fietsen, roeien, zwemmen) mogen NOOIT langer zijn dan 60 minuten, tenzij het doel expliciet een duurtraining van >90 min vereist.",
            "- Geen enkele individuele sessie mag meer dan 40% hoger in TRIMP zijn dan het gemiddelde van de afgelopen 7 dagen. Voorkomen van extreme pieken is prioriteit."
        ])

        let systemPrompt = systemLines.joined(separator: "\n")

        // De tekst die de gebruiker ziet in de chat (beknopt en begrijpelijk)
        let goalTitles = atRiskGoals.map { "'\($0.title)'" }.joined(separator: " en ")
        let userFacingText = "Los de achterstand op voor \(goalTitles) en geef me een bijgestuurd schema."

        sendHiddenSystemMessage(
            systemText: systemPrompt,
            userText: userFacingText,
            fallbackMessage: "Ik heb je herstelplan klaar! Bekijk je overzicht — het schema is bijgewerkt om je weer op schema te brengen.",
            contextProfile: contextProfile,
            activeGoals: activeGoals,
            activePreferences: activePreferences
        )
    }

    /// Handelt het afwijzen (overslaan) van een specifieke voorgestelde workout af (Rest Day).
    func skipWorkout(_ workout: SuggestedWorkout, contextProfile: AthleticProfile? = nil, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) {
        let systemPrompt = "Ik sla de training '\(workout.activityType)' op \(workout.dateOrDay) over. Herbereken de week en schuif de belasting door. BELANGRIJK: Retourneer in je JSON-output altijd het volledige 7-daagse schema (inclusief alle ongewijzigde andere dagen), en niet alleen de aangepaste dag."
        let userFacingText = "Ik sla de geplande \(workout.activityType) op \(workout.dateOrDay) over."
        sendHiddenSystemMessage(systemText: systemPrompt, userText: userFacingText, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
    }

    /// Handelt de aanvraag voor een alternatieve workout af.
    func requestAlternativeWorkout(_ workout: SuggestedWorkout, contextProfile: AthleticProfile? = nil, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) {
        let systemPrompt = "Ik vind de geplande training '\(workout.activityType)' op \(workout.dateOrDay) niet leuk. Geef me een alternatief voor \(workout.dateOrDay) dat een vergelijkbare trainingsprikkel geeft. BELANGRIJK: Retourneer in je JSON-output altijd het volledige 7-daagse schema (inclusief alle ongewijzigde andere dagen), en niet alleen de aangepaste dag."
        let userFacingText = "Geef me een alternatief voor de \(workout.activityType) op \(workout.dateOrDay)."
        sendHiddenSystemMessage(systemText: systemPrompt, userText: userFacingText, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
    }

    /// Verstuurt een bericht waarbij de UI een simpele tekst toont, maar de payload de technische prompt bevat.
    /// Als JSON-parsing mislukt, wordt `fallbackMessage` getoond in plaats van de ruwe AI-tekst —
    /// zodat bij recovery plan / skip-workout calls nooit ruwe JSON in de chat verschijnt.
    private func sendHiddenSystemMessage(
        systemText: String,
        userText: String,
        fallbackMessage: String = "Ik heb je schema bijgewerkt! Bekijk je overzicht voor het nieuwe plan.",
        contextProfile: AthleticProfile? = nil,
        activeGoals: [FitnessGoal] = [],
        activePreferences: [UserPreference] = []
    ) {
        messages.append(ChatMessage(role: .user, text: userText))
        isTyping = true

        let contextPrefix = buildContextPrefix(from: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
        let payloadText = "\(contextPrefix)\(systemText)"

        fetchAIResponse(for: payloadText, image: nil, fallbackMessage: fallbackMessage)
    }

    /// Verstuurt het huidige tekstveld (of de meegegeven tekst) en/of de geselecteerde afbeelding.
    func sendMessage(_ explicitText: String? = nil, contextProfile: AthleticProfile? = nil, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) {
        let textToUse = explicitText ?? inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        let imageToSend = selectedImage?.downsample(to: 2048.0)

        guard !textToUse.isEmpty || imageToSend != nil else { return }
        // Voorkom dat de gebruiker een nieuw bericht stuurt terwijl de coach nog aan het typen is.
        guard !isTyping else { return }

        // 1. Maak bericht aan van gebruiker voor de UI (ZONDER de onzichtbare context prefix)
        let imageData = imageToSend?.jpegData(compressionQuality: 0.8)
        let uiMessage = ChatMessage(role: .user, text: textToUse, attachedImageData: imageData)
        messages.append(uiMessage)

        isTyping = true
        inputText = ""
        clearImage()

        // 2. Bouw de uiteindelijke payload prompt op
        let contextPrefix = buildContextPrefix(from: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)

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

    /// Verwijdert de laatste foutmelding en stuurt het laatste gebruikersbericht opnieuw.
    /// Wordt aangeroepen via de 'Probeer opnieuw' knop in de MessageBubble.
    func retryLastMessage(contextProfile: AthleticProfile? = nil, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) {
        // Verwijder het laatste foutbericht uit de chat
        if let lastErrorIndex = messages.indices.last(where: { messages[$0].isError }) {
            messages.remove(at: lastErrorIndex)
        }

        // Zoek het laatste gebruikersbericht om opnieuw te versturen
        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else { return }

        // Verwijder ook het gebruikersbericht zelf zodat sendMessage() het netjes opnieuw toevoegt
        if let lastUserIndex = messages.indices.last(where: { messages[$0].role == .user }) {
            messages.remove(at: lastUserIndex)
        }

        // Stuur opnieuw — sendMessage voegt het bericht weer toe en roept de AI aan
        sendMessage(lastUserMessage.text, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
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

        let storedPlanContext = getStoredPlanString()

        var lines: [String] = [storedPlanContext, "\nDit zijn mijn meest recente voltooide trainingen (inclusief rustdagen):"]

        // Inject Goals explicitly
        let uncompletedGoals = activeGoals.filter { !$0.isCompleted }
        if uncompletedGoals.isEmpty {
            lines.append("- Mijn opgeslagen doelen: Geen specifieke doelen.")
        } else {
            let goalsString = uncompletedGoals.map { goal in
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                let dateStr = formatter.string(from: goal.targetDate)
                let sport = goal.sportCategory?.displayName ?? "Sport"
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

        let dateString = now.formatted(date: .complete, time: .omitted)
        lines.append("LET OP: Vandaag is het \(dateString). Het nieuwe 7-daagse schema MOET vanaf vandaag beginnen. Verwijder dagen in het verleden en vul de week aan.")
        lines.append("KRITIEK: Sorteer de workouts in het JSON-array ALTIJD chronologisch — dag 1 (vandaag) eerst, dag 7 (over 6 dagen) als laatste. Nooit andersom, nooit willekeurig.")
        lines.append("Vergelijk deze recente activiteiten met het actuele schema hierboven. Is het resterende schema voor deze week nog steeds optimaal en realistisch? Zo niet, herbereken het schema (retourneer altijd alle 7 dagen) en geef een korte motivatie of feedback op mijn recente trainingen.")

        return lines.joined(separator: "\n")
    }

    /// Haalt de status op via de geselecteerde bron voor de afgelopen X dagen.
    /// Valt terug op de andere bron bij gebrek aan data of permissies.
    func analyzeCurrentStatus(days: Int = 7, contextProfile: AthleticProfile? = nil, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) {
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
                        await sendPromptToAI(uiPrompt: uiPrompt, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
                        return
                    }
                    print("⚠️ Geen of lege HealthKit workouts gevonden, terugvallen op Strava.")
                } catch {
                    print("⚠️ Fout bij ophalen HealthKit data (\(error.localizedDescription)), terugvallen op Strava.")
                }

                // Fallback naar Strava
                await fetchStravaRecentActivities(days: days, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)

            } else {
                // Strava geselecteerd
                await fetchStravaRecentActivities(days: days, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
            }
        }
    }

    /// Hulpfunctie voor de AI prompt injectie (Zonder de payload in de UI te tonen).
    private func sendPromptToAI(uiPrompt: String, contextProfile: AthleticProfile?, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) async {
        await MainActor.run {
            // Let op: We voegen uiPrompt (de ruwe JSON context) NIET toe aan messages.
            // Voeg eventueel een vriendelijke systeem-indicatie toe voor de UI als het een handmatige refresh was,
            // of laat de UI leeg en toon alleen het laden (isTyping).
            // Voor nu houden we het simpel en onzichtbaar.
            isTyping = true
            isFetchingWorkout = false

            let contextPrefix = buildContextPrefix(from: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
            let payloadText = "\(contextPrefix)\(uiPrompt)"
            fetchAIResponse(for: payloadText, image: nil)
        }
    }

    /// Hulpfunctie voor het ophalen via HealthKit, met optionele fallback.
    private func fetchHealthKitRecentWorkouts(days: Int, contextProfile: AthleticProfile?, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = [], isFallback: Bool = false) async {
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
                await sendPromptToAI(uiPrompt: uiPrompt, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
                return
            }

            if !isFallback {
                print("⚠️ Geen of lege HealthKit workouts gevonden, terugvallen op Strava.")
                await fetchStravaRecentActivities(days: days, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences, isFallback: true)
            } else {
                await MainActor.run {
                    messages.append(ChatMessage(role: .ai, text: "Ik kon geen recente trainingen vinden in HealthKit of je Strava account."))
                    isFetchingWorkout = false
                }
            }
        } catch {
            if !isFallback {
                print("⚠️ Fout bij ophalen HealthKit data (\(error.localizedDescription)), terugvallen op Strava.")
                await fetchStravaRecentActivities(days: days, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences, isFallback: true)
            } else {
                await MainActor.run {
                    messages.append(ChatMessage(role: .ai, text: "Ik kon geen recente trainingen vinden. HealthKit fout: \(error.localizedDescription)"))
                    isFetchingWorkout = false
                }
            }
        }
    }

    /// Hulpfunctie voor het ophalen via Strava, inclusief fallback naar HealthKit.
    private func fetchStravaRecentActivities(days: Int, contextProfile: AthleticProfile?, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = [], isFallback: Bool = false) async {
        do {
            let activities = try await fitnessDataService.fetchRecentActivities(days: days)

            if activities.isEmpty {
                if !isFallback && selectedDataSource == .strava {
                    // Reverse Fallback: Als Strava faalt of leeg is en Strava was de bron, probeer HealthKit
                    print("⚠️ Geen recente Strava activiteit gevonden. Reverse fallback naar HealthKit.")
                    await fetchHealthKitRecentWorkouts(days: days, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences, isFallback: true)
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

            await sendPromptToAI(uiPrompt: uiPrompt, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)

        } catch let error as FitnessDataError {
            if !isFallback && selectedDataSource == .strava {
                print("⚠️ Strava API fout (\(error)). Reverse fallback naar HealthKit.")
                await fetchHealthKitRecentWorkouts(days: days, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences, isFallback: true)
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
                await fetchHealthKitRecentWorkouts(days: days, contextProfile: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences, isFallback: true)
                return
            }

            await MainActor.run {
                messages.append(ChatMessage(role: .ai, text: "Er is een onbekende fout opgetreden."))
                isFetchingWorkout = false
            }
        }
    }

    // MARK: - JSON Parsing Hulpfuncties

    /// Haalt een schone JSON-string op uit een AI-response die mogelijk markdown-opmaak bevat.
    ///
    /// Strategie (in volgorde):
    /// 1. Strip markdown code block tags (```json, ```JSON, ```) aan het begin en einde.
    /// 2. Als de string daarna nog steeds niet begint met `{`, zoek dan de eerste `{`
    ///    en de laatste `}` en extraheer alleen dat gedeelte.
    /// 3. Trim witruimte.
    private func extractCleanJSON(from rawText: String) -> String {
        var text = rawText

        // Stap 1: Strip markdown code block opening tag (```json of ```)
        // Gebruik case-insensitive zoek zodat ook ```JSON werkt
        if let startRange = text.range(of: "```json", options: .caseInsensitive) {
            text = String(text[startRange.upperBound...])
        } else if let startRange = text.range(of: "```") {
            text = String(text[startRange.upperBound...])
        }

        // Strip sluitende ``` (zoek van achteren naar voren)
        if let endRange = text.range(of: "```", options: .backwards) {
            text = String(text[..<endRange.lowerBound])
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Stap 2: Als er nog steeds proza vóór de JSON staat, extraheer het { ... } blok direct
        if !text.hasPrefix("{") {
            if let startIndex = text.firstIndex(of: "{"),
               let endIndex = text.lastIndex(of: "}") {
                text = String(text[startIndex...endIndex])
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stuurt asynchroon het verzoek naar het AI-model met de juiste content payload.
    ///
    /// - Parameters:
    ///   - text: De ingevoerde tekst door de gebruiker.
    ///   - image: Een optionele UIImage.
    ///   - fallbackMessage: Optioneel. Als JSON-parsing mislukt (bijv. bij hidden system calls),
    ///     wordt dit bericht getoond in plaats van de ruwe AI-tekst. Gebruik dit voor
    ///     recovery plan requests, skip workout, etc. om te voorkomen dat JSON in de chat zichtbaar wordt.
    func fetchAIResponse(for text: String, image: UIImage?, fallbackMessage: String? = nil) {
        // Om te zorgen dat de unit tests (die het protocol mocken) niet falen op de check
        // van de ontbrekende API sleutel (omdat de statische Secrets placeholder vaak actief is in CI),
        // negeren we de check als een custom model is geïnjecteerd voor testing, of loggen de waarschuwing.
        // Epic 20: BYOK — blokkeer als er geen geldige API-sleutel is geconfigureerd.
        // Uitzondering: als een custom model (bijv. een mock voor unit tests) is geïnjecteerd,
        // slaan we de key-check over zodat tests niet falen op een ontbrekende sleutel.
        if model is RealGenerativeModel {
            guard hasAPIKey else {
                let noKeyMessage = "Je AI Coach slaapt. Voer een API-sleutel in via de Instellingen om hem wakker te maken."
                messages.append(ChatMessage(role: .ai, text: noKeyMessage))
                lastAIErrorMessage = noKeyMessage
                return
            }
        }

        // Wis een eventuele vorige foutbanner zodra er een nieuwe call start.
        lastAIErrorMessage = nil

        Task {
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

            print("DEBUG PROMPT: \(text)")

            // Waterfall: primair model eerst. Bij 503/429 (overbelasting) schakelen
            // we stil over op het fallback-model — standaard lichter, vaker beschikbaar
            // tijdens pieken. Beide modelnamen zijn vanaf Epic #35 configureerbaar in
            // Settings → AI Coach Configuratie. Andere fouten (invalid key, prompt
            // blocked, netwerk) vallen direct naar de UI door.
            var responseText: String? = nil
            var finalError: Error? = nil

            do {
                responseText = try await model.generateContent(promptParts)
            } catch let primaryError as GenerateContentError {
                if case .internalError = primaryError {
                    retryStatusMessage = "Model tijdelijk overbelast — overschakelen naar lichtere variant..."
                    let fallbackModel = buildFallbackGenerativeModel()
                    do {
                        responseText = try await fallbackModel.generateContent(promptParts)
                    } catch {
                        finalError = error
                    }
                } else {
                    finalError = primaryError
                }
            } catch {
                finalError = error
            }

            // Reset retry-statusbericht
            retryStatusMessage = ""

            // Verwerk fout als alle pogingen zijn mislukt
            if let error = finalError {
                let userFacingMessage: String
                if let geminiError = error as? GenerateContentError {
                    switch geminiError {
                    case .promptBlocked:
                        // Prompt geblokkeerd door veiligheidsfilters
                        userFacingMessage = "Je bericht kon niet verwerkt worden. Dit komt soms voor door veiligheidsfilters van de AI. Probeer het opnieuw of stel je vraag anders."
                    case .invalidAPIKey:
                        userFacingMessage = "De API-sleutel is ongeldig. Controleer de sleutel via Instellingen → AI Coach Configuratie."
                    case .internalError:
                        // Zowel primair als fallback model faalden met 503/429. 
                        userFacingMessage = "De AI-service is tijdelijk overbelast. Wacht even en probeer het opnieuw."
                    default:
                        userFacingMessage = "Er is een tijdelijk probleem met de AI-service. Probeer het opnieuw."
                    }
                } else {
                    userFacingMessage = "Er is een tijdelijk probleem. Probeer het opnieuw."
                }
                messages.append(ChatMessage(role: .ai, text: userFacingMessage, isError: true))
                // Spiegel de foutmelding in de banner-state zodat screens zonder
                // zichtbare chat (zoals Dashboard tijdens pull-to-refresh) óók feedback tonen.
                lastAIErrorMessage = userFacingMessage
                isTyping = false
                return
            }

            // Verwerk het succesvolle antwoord
            print("DEBUG RAW RESPONSE: \(responseText ?? "nil")")

            // Gebruik de robuuste JSON-extractor: strip markdown en haal het JSON-object eruit
            let cleanedJSON = extractCleanJSON(from: responseText ?? "{}")

            var parsedPlan: SuggestedTrainingPlan? = nil
            var motivationText: String

            if let data = cleanedJSON.data(using: .utf8) {
                do {
                    let plan = try JSONDecoder().decode(SuggestedTrainingPlan.self, from: data)
                    parsedPlan = plan

                    // SPRINT 13.4: motivation altijd zichtbaar in de chat.
                    // Als de AI een leeg veld teruggeeft, toon de fallbackMessage zodat
                    // er altijd een menselijke bevestiging in de chat staat.
                    let trimmedMotivation = plan.motivation.trimmingCharacters(in: .whitespacesAndNewlines)
                    motivationText = trimmedMotivation.isEmpty
                        ? (fallbackMessage ?? "Ik heb je schema bijgewerkt! Bekijk je overzicht.")
                        : trimmedMotivation

                    // Trigger callback als er nieuwe voorkeuren zijn gevonden
                    if let prefs = plan.newPreferences, !prefs.isEmpty {
                        onNewPreferencesDetected?(prefs)
                    }

                    // Update het centrale schema (ook opgeslagen in AppStorage).
                    // Story 33.2b: bij een reset gaat het via mergeReplannedPlan zodat
                    // verplaatste sessies (`isSwapped`) leidend blijven over AI-output.
                    switch pendingPlanUpdateMode {
                    case .replace:
                        trainingPlanManager?.updatePlan(plan)
                    case .mergePreservingSwaps:
                        trainingPlanManager?.mergeReplannedPlan(plan)
                    }
                    // Reset altijd na één gebruik — voorkomt dat een latere chat-message
                    // per ongeluk nog in merge-mode komt.
                    pendingPlanUpdateMode = .replace

                    // Sla de motivatie op voor het dashboard insight block
                    if !motivationText.isEmpty {
                        latestCoachInsight = motivationText
                        lastAnalysisTimestamp = Date().timeIntervalSince1970
                    }
                } catch {
                    // JSON-parsing mislukt: gebruik de fallbackMessage als die is meegegeven
                    // (bijv. bij recovery plan of skip-workout calls), zodat nooit ruwe JSON in de chat zichtbaar is.
                    // Voor gewone chat-berichten tonen we de opgeschoonde tekst (proza zonder JSON-blokken).
                    print("⚠️ JSON-parsing mislukt: \(error.localizedDescription)")
                    if let fallback = fallbackMessage {
                        motivationText = fallback
                    } else {
                        // Gewone chat: toon de opgeschoonde response (zonder markdown-tags) als tekst
                        motivationText = cleanedJSON.hasPrefix("{") ? "Ik kon het schema niet correct verwerken. Probeer het opnieuw." : cleanedJSON
                    }
                }
            } else {
                motivationText = fallbackMessage ?? "Ik kon de reactie niet verwerken. Probeer het opnieuw."
            }

            messages.append(ChatMessage(role: .ai, text: motivationText, suggestedPlan: parsedPlan))
            isTyping = false
        }
    }
}
