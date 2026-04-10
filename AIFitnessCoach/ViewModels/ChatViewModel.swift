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

    // Epic 20: BYOK — gebruiker-geconfigureerde AI sleutel en provider
    @AppStorage("vibecoach_userAPIKey") private var storedAPIKey: String = ""
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

    /// Callback om nieuwe voorkeuren naar de View te sturen zodat ze in SwiftData opgeslagen worden.
    var onNewPreferencesDetected: (([ExtractedPreference]) -> Void)?

    /// Stelt de TrainingPlanManager in
    func setTrainingPlanManager(_ manager: TrainingPlanManager) {
        self.trainingPlanManager = manager
    }

    /// Epic 14.4: Schrijft de Vibe Score van vandaag naar de AppStorage cache.
    /// Wordt aangeroepen vanuit DashboardView bij onAppear zodat de AI-prompts
    /// altijd de actuele herstelstatus bevatten.
    func cacheVibeScore(_ readiness: DailyReadiness?) {
        guard let r = readiness else {
            todayVibeScoreContext = ""
            return
        }

        let label: String
        if r.readinessScore >= 80 { label = "Optimaal Hersteld" }
        else if r.readinessScore >= 50 { label = "Matig Hersteld" }
        else { label = "Slecht Hersteld — Rust prioriteit" }

        let sleepH = Int(r.sleepHours)
        let sleepM = Int((r.sleepHours - Double(sleepH)) * 60)

        todayVibeScoreContext = "Vibe Score vandaag: \(r.readinessScore)/100 (\(label)). Slaap: \(sleepH)u \(sleepM)m. HRV: \(String(format: "%.1f", r.hrv)) ms."
    }

    /// Epic 20: Retourneert de actieve API-sleutel.
    /// Prioriteit: gebruiker-geconfigureerde sleutel → Secrets.geminiAPIKey fallback.
    /// De fallback zorgt dat bestaande installaties zonder BYOK-sleutel blijven werken.
    func effectiveAPIKey() -> String {
        let stored = UserDefaults.standard.string(forKey: "vibecoach_userAPIKey") ?? ""
        return stored.isEmpty ? Secrets.geminiAPIKey : stored
    }

    /// Bouwt een nieuw Gemini model op basis van de huidige API-sleutel.
    /// Wordt aangeroepen als de gebruiker een nieuwe sleutel heeft opgeslagen.
    /// Epic 20: Placeholder voor Sprint 20.2 — slaat de aktieve key op zodat toekomstige
    /// code kan detecteren of de sleutel gewijzigd is en het model opnieuw moet bouwen.
    private func rebuildRealModel() {
        let key = effectiveAPIKey()
        guard !key.isEmpty else { return }
        activeAPIKey = key
    }

    /// Epic 18.1: Schrijft de subjectieve feedback van de laatste workout naar de AppStorage cache.
    /// Wordt aangeroepen vanuit DashboardView zodra er een ActivityRecord is met rpe en mood.
    /// De AI gebruikt dit om discrepanties te detecteren (bijv. laag TRIMP maar hoge RPE = overtraining signaal).
    func cacheLastWorkoutFeedback(rpe: Int?, mood: String?, workoutName: String?, trimp: Double?, startDate: Date? = nil) {
        guard let rpe = rpe, let mood = mood else {
            // Geen feedback beschikbaar — wis de cache
            lastWorkoutFeedbackContext = ""
            return
        }

        // Formatteer als "[Type] van [Datum]" — bijv. "Hardloopsessie van 8 apr."
        let baseName = workoutName ?? "Training"
        let nameStr: String
        if let date = startDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            formatter.locale = Locale(identifier: "nl_NL")
            nameStr = "\(baseName) van \(formatter.string(from: date))"
        } else {
            nameStr = baseName
        }

        let trimpStr = trimp != nil ? String(format: "%.0f", trimp!) : "onbekend"
        let rpeLabel: String
        switch rpe {
        case 1...3: rpeLabel = "licht (1-3)"
        case 4...6: rpeLabel = "matig (4-6)"
        case 7...8: rpeLabel = "zwaar (7-8)"
        default:    rpeLabel = "maximaal (9-10)"
        }
        lastWorkoutFeedbackContext = "Laatste workout: '\(nameStr)', TRIMP: \(trimpStr), RPE: \(rpe)/10 (\(rpeLabel)), Stemming: \(mood)."
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
            let weeksLeft = result.goal.targetDate.timeIntervalSince(Date()) / (7 * 86400)
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

        if let providedModel = aiModel {
            self.model = providedModel
        } else {
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
            Als de gebruiker een blessure of klacht heeft vermeld in zijn voorkeuren of berichten:
            - Kuit/Scheen blessure: Adviseer GEEN hardlopen. Wandelen is toegestaan als alternatief, maar NOOIT langer dan 60 minuten per sessie.
            - Rugklachten: Vermijd intensief hardlopen en krachttraining. Fietsen (rechtopzittend) en zwemmen zijn veilige alternatieven.
            - Benoem de blessure ALTIJD expliciet in je antwoord: 'Gezien je [blessure] raad ik [veilige activiteit] aan in plaats van [geplande activiteit].'
            - Pas het schema DIRECT aan — geef nooit een training die de blessure kan verergeren.

            KRITIEKE BEPERKING — WANDELEN:
            Wandelen mag uitsluitend als herstel-activiteit bij blessures of een Vibe Score < 50.
            Een wandelsessie mag NOOIT langer zijn dan 60 minuten. Stel in de JSON altijd suggestedDurationMinutes ≤ 60 in voor wandelingen.

            Belangrijke context voor je analyse:
            Wij berekenen lokaal een Banister TRIMP (Training Impulse) score om de trainingsbelasting te bepalen (niet de traditionele TSS die op 100/uur cap).
            - Een TRIMP van 70-100 is een pittige, solide training.
            - Een TRIMP van 100-140 is een zeer zware training, maar dit is op zichzelf geen teken van overtraining.

            BELANGRIJK: Zodra je een schema of status voor de komende 7 dagen plant of analyseert, MOET je antwoord een JSON object bevatten (eventueel in een codeblock) dat voldoet aan deze structuur:
            {
                "motivation": "Schrijf hier een empathische, beschrijvende analyse van maximaal 3 zinnen. Begin met een DIRECTE reactie op het laatste bericht van de gebruiker (benoem de specifieke activiteit). Leg daarna het WAAROM uit achter je strategische keuzes. Als je een aanpassing maakt in het schema, bevestig dit expliciet ('Ik heb X verschoven naar Y omdat...'). Geef de gebruiker het gevoel dat de coach écht meedenkt en écht luistert.",
                "workouts": [
                    {
                        "dateOrDay": "Maandag",
                        "activityType": "Hardlopen",
                        "suggestedDurationMinutes": 45,
                        "targetTRIMP": 60,
                        "description": "Herstel na de lange duurloop",
                        "heartRateZone": "Zone 2",
                        "targetPace": "5:30 min/km"
                    }
                ],
                "newPreferences": [
                    {
                        "text": "Ik heb last van mijn knie",
                        "expirationDate": "2024-05-20"
                    }
                ]
            }
            Extra instructie voor `newPreferences`: Als je opmerkt dat de gebruiker een vaste regel, langetermijnvoorkeur, of tijdelijke kwaal/blessure doorgeeft in hun LAATSTE bericht, vul dit array dan aan. Schat in of dit feit permanent is (zoals een vaste sportdag) of tijdelijk (zoals spierpijn, een lichte blessure of kramp). Als het tijdelijk is, bereken dan een logische verloopdatum (bijv. 1 of 2 weken vanaf vandaag) en retourneer deze in de JSON onder `expirationDate` als een "YYYY-MM-DD" string. Laat `expirationDate` leeg (null) bij permanente regels. Herhaal geen regels die je al kent.
            """

            let config = GenerationConfig(
                responseMIMEType: "application/json"
            )

            let options = RequestOptions(
                timeout: 120
            )

            // Epic 20: key inline berekenen — effectiveAPIKey() kan hier niet aangeroepen worden
            // omdat self.model nog niet geïnitialiseerd is (Swift-beperking in init).
            let initKey: String = {
                let stored = UserDefaults.standard.string(forKey: "vibecoach_userAPIKey") ?? ""
                return stored.isEmpty ? Secrets.geminiAPIKey : stored
            }()

            let googleModel = GenerativeModel(
                name: "gemini-2.5-flash",
                apiKey: initKey,
                generationConfig: config,
                systemInstruction: ModelContent(role: "system", parts: [.text(systemInstruction)]),
                requestOptions: options
            )
            self.model = RealGenerativeModel(model: googleModel)
        }
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
    private func buildContextPrefix(from profile: AthleticProfile?, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) -> String {
        var prefix = ""

        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        prefix += "[HUIDIGE DATUM: Vandaag is het \(dateFormatter.string(from: now)). Gebruik dit voor je berekeningen rondom 'expirationDate'.]\n\n"

        // Epic 14.4: Injecteer de Vibe Score als harde context — de AI MOET dit volgen (zie systeeminstructie)
        if !todayVibeScoreContext.isEmpty {
            prefix += "[HERSTELSTATUS VANDAAG: \(todayVibeScoreContext) Volg de kritieke regel over de Vibe Score autoriteit strikt.]\n\n"
        }

        // Epic 18.1: Injecteer de subjectieve feedback (RPE + stemming) van de laatste workout
        if !lastWorkoutFeedbackContext.isEmpty {
            prefix += "[SUBJECTIEVE FEEDBACK LAATSTE WORKOUT: \(lastWorkoutFeedbackContext) Let op discrepanties: als TRIMP laag is maar RPE ≥8, is dit een vroeg signaal van overtraining of naderende ziekte.]\n\n"
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
                let weeksLeft = goal.targetDate.timeIntervalSince(now) / (7 * 86400)
                let weeksLeftStr = String(format: "%.1f", weeksLeft)
                // Bereken de fase-gecorrigeerde wekelijkse target (lineaire baseline × multiplier)
                let linearRate = goal.computedTargetTRIMP / max(0.1, weeksLeft)
                let adjustedTarget = Int((linearRate * phase.multiplier).rounded())
                prefix += "• Doel '\(goal.title)' (\(weeksLeftStr) weken resterend): \(phase.aiInstruction)\n"
                prefix += "  Wiskundig aangepaste wekelijkse TRIMP-target: \(adjustedTarget) TRIMP/week (multiplier: ×\(String(format: "%.2f", phase.multiplier))). Houd je strikt aan deze target.\n"
            }
            prefix += "]\n\n"
        }

        // Filter expired preferences out context
        let validPreferences = activePreferences.filter { pref in
            if let expirationDate = pref.expirationDate {
                return expirationDate > now
            }
            return true
        }

        if !validPreferences.isEmpty {
            let prefStrings = validPreferences.map { "\"- \($0.preferenceText)\"" }.joined(separator: ", ")
            prefix += "[VASTE REGELS / VOORKEUREN VAN DE GEBRUIKER: \(prefStrings). Houd hier ten alle tijden rekening mee in je planning en advies.]\n\n"
        }

        // Detecteer blessure-gerelateerde voorkeuren en injecteer als aparte hoge-prioriteit context.
        // De AI moet blessure-context ALTIJD explicieter behandelen dan gewone voorkeuren.
        let injuryKeywords = ["kuit", "scheen", "shin", "rug", "rugpijn", "knie", "enkel", "blessure", "pijn", "klacht"]
        let activeInjuries = validPreferences.filter { pref in
            let text = pref.preferenceText.lowercased()
            return injuryKeywords.contains(where: { text.contains($0) })
        }
        if !activeInjuries.isEmpty {
            let injuryLines = activeInjuries.map { "• \($0.preferenceText)" }.joined(separator: "\n")
            prefix += "[ACTIEVE BLESSURES / KLACHTEN — HOOGSTE PRIORITEIT:\n\(injuryLines)\nInstructie: Pas het schema ALTIJD aan op basis van deze klachten. Benoem de blessure expliciet in je antwoord en geef aan welke sportalternatieven veilig zijn.]\n\n"
        }

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
        if !todayVibeScoreContext.isEmpty {
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

    /// Haalt een specifieke Strava activiteit op (bijv. vanuit een notificatie),
    /// formatteert deze als een Nederlandse prompt en stuurt deze naar de AI-coach.
    func analyzeWorkout(withId id: Int64, contextProfile: AthleticProfile? = nil, activeGoals: [FitnessGoal] = [], activePreferences: [UserPreference] = []) {
        guard !isFetchingWorkout else { return }
        isFetchingWorkout = true

        Task {
            do {
                let activity = try await fitnessDataService.fetchActivity(byId: id)

                // Converteer eenheden
                let distanceKm = String(format: "%.1f", activity.distance / 1000.0)
                let timeMinutes = activity.moving_time / 60
                let heartRateStr = activity.average_heartrate != nil ? "\(Int(activity.average_heartrate!))" : "onbekend"

                // Bereken TRIMP
                let avgHR = activity.average_heartrate ?? 140.0
                let calculatedTSS = fitnessCalculator.calculateTSS(durationInSeconds: Double(activity.moving_time), averageHeartRate: avgHR, maxHeartRate: 190.0, restingHeartRate: 60.0)
                let trimpScore = Int(calculatedTSS)

                // Formatteer de verborgen systeem prompt inclusief de referentie naar het actuele schema (Sprint 9.3)
                let storedPlanContext = getStoredPlanString()
                let uiPrompt = "\(storedPlanContext)\n\nIk heb zojuist deze training voltooid: '\(activity.name)' (Afstand: \(distanceKm) km, Tijd: \(timeMinutes) minuten, Gem. Hartslag: \(heartRateStr), TRIMP: \(trimpScore)). Vergelijk dit met de geplande belasting in het schema. Is het resterende schema voor deze week nog steeds optimaal? Zo niet, herbereken het schema (retourneer alle 7 dagen) en geef een korte motivatie of feedback op de zojuist voltooide training."

                Task { @MainActor in
                    // Verberg de technische JSON details uit de UI, toon een simpele zin.
                    messages.append(ChatMessage(role: .user, text: "Ik heb zojuist de training '\(activity.name)' voltooid. Hoe ziet de rest van mijn week eruit?"))
                    isTyping = true
                    isFetchingWorkout = false

                    let contextPrefix = buildContextPrefix(from: contextProfile, activeGoals: activeGoals, activePreferences: activePreferences)
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
                messages.append(ChatMessage(role: .ai, text: "Je AI Coach slaapt. Voer een API-sleutel in via de Instellingen om hem wakker te maken."))
                return
            }
        }

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

            // Retry logica: probeer maximaal 3 keer bij tijdelijke server-fouten (bijv. 503 overbelasting).
            let maxPogingen = 3
            var responseText: String? = nil
            var finalError: Error? = nil

            for poging in 1...maxPogingen {
                do {
                    responseText = try await model.generateContent(promptParts)
                    finalError = nil
                    break // Gelukt — stop de retry loop
                } catch let error as GenerateContentError {
                    if case .internalError = error, poging < maxPogingen {
                        // Tijdelijke server-fout (bijv. 503) — wacht even en probeer opnieuw
                        retryStatusMessage = "Server tijdelijk overbelast, opnieuw proberen (\(poging)/\(maxPogingen))..."
                        try? await Task.sleep(nanoseconds: UInt64(poging) * 2_000_000_000)
                        continue
                    }
                    finalError = error
                    break
                } catch {
                    finalError = error
                    break
                }
            }

            // Reset retry-statusbericht
            retryStatusMessage = ""

            // Verwerk fout als alle pogingen zijn mislukt
            if let error = finalError {
                if let geminiError = error as? GenerateContentError {
                    switch geminiError {
                    case .promptBlocked:
                        // Prompt geblokkeerd door veiligheidsfilters
                        messages.append(ChatMessage(role: .ai, text: "Je bericht kon niet verwerkt worden. Dit komt soms voor door veiligheidsfilters van de AI. Probeer het opnieuw of stel je vraag anders."))
                    case .invalidAPIKey:
                        messages.append(ChatMessage(role: .ai, text: "De API-sleutel is ongeldig. Controleer de sleutel via Instellingen → AI Coach Configuratie."))
                    case .internalError:
                        // Na 3 pogingen nog steeds een server-fout (bijv. 503) — herstelbaar via retry
                        messages.append(ChatMessage(role: .ai, text: "De AI-service is tijdelijk overbelast. Wacht even en probeer het opnieuw.", isError: true))
                    default:
                        messages.append(ChatMessage(role: .ai, text: "Er is een tijdelijk probleem met de AI-service. Probeer het opnieuw.", isError: true))
                    }
                } else {
                    messages.append(ChatMessage(role: .ai, text: "Er is een tijdelijk probleem. Probeer het opnieuw.", isError: true))
                }
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

                    // Update het centrale schema (ook opgeslagen in AppStorage)
                    trainingPlanManager?.updatePlan(plan)

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
