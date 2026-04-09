import Foundation


import SwiftData

/// Representeert een opgeslagen langetermijnvoorkeur of 'harde regel' van de gebruiker.
@Model
final class UserPreference {
    @Attribute(.unique) var id: UUID
    var preferenceText: String
    var createdAt: Date
    var isActive: Bool
    var expirationDate: Date?

    init(id: UUID = UUID(), preferenceText: String, createdAt: Date = Date(), isActive: Bool = true, expirationDate: Date? = nil) {
        self.id = id
        self.preferenceText = preferenceText
        self.createdAt = createdAt
        self.isActive = isActive
        self.expirationDate = expirationDate
    }
}

// MARK: - Epic 16: Dynamische Periodisering

/// De vier klassieke trainingsperioden van een macrocyclus.
/// Bepaalt welke AI-instructies de coach gebruikt bij het plannen van trainingen.
enum TrainingPhase: String, CaseIterable {
    case baseBuilding = "Base Building"
    case buildPhase   = "Build Phase"
    case peakPhase    = "Peak Phase"
    case tapering     = "Tapering"

    /// Korte beschrijving die zichtbaar is als badge in de UI.
    var displayName: String { rawValue }

    /// Kleur voor de UI-badge
    var color: String {
        switch self {
        case .baseBuilding: return "blue"
        case .buildPhase:   return "orange"
        case .peakPhase:    return "red"
        case .tapering:     return "purple"
        }
    }

    /// Sprint 16.2: Fase-multiplier voor de wekelijkse TRIMP-target.
    /// De lineaire baseline (resterend TRIMP / resterende weken) wordt hiermee gecorrigeerd
    /// zodat de trainingsintensiteit overeenkomt met de fysiologische fase.
    var multiplier: Double {
        switch self {
        case .baseBuilding: return 1.00  // Gewone lineaire baseline
        case .buildPhase:   return 1.15  // 15% meer belasting opbouwen
        case .peakPhase:    return 1.30  // 30% meer — maximale adaptatiefase
        case .tapering:     return 0.60  // 40% minder — rust is de training
        }
    }

    /// Harde AI-instructie die de coach krijgt voor deze fase.
    var aiInstruction: String {
        switch self {
        case .baseBuilding:
            return "Huidige fase: Base Building (>12 weken tot evenement). Instructie: Focus uitsluitend op laag-intensief volume (Zone 1-2). Geen intervaltraining. Bouw de wekelijkse TRIMP geleidelijk op met max. 10% per week. Leg het aerobe fundament."
        case .buildPhase:
            return "Huidige fase: Build Phase (4-12 weken tot evenement). Instructie: Verhoog zowel volume als intensiteit. Introduceer gecontroleerde intervaltraining (Zone 3-4). Wekelijkse TRIMP-stijging max. 12%. Afwisselen tussen belastingsweken en hersteldagen."
        case .peakPhase:
            return "Huidige fase: Peak Phase (2-4 weken tot evenement). Instructie: Maximale trainingsbelasting. Race-specifieke trainingen: tempo's op wedstrijdintensiteit. Hoge TRIMP, maar wel gecontroleerde hersteldagen inplannen. Dit is de laatste kans voor adaptatie."
        case .tapering:
            return "Huidige fase: Tapering (<2 weken tot evenement). KRITIEKE INSTRUCTIE: Verlaag het wekelijkse TRIMP-volume met minimaal 40%. Geen lange zware trainingen meer. Alleen korte, lichte sessies (max. 45 min) om de benen scherp te houden. De atleet is klaar — rust is nu de training."
        }
    }

    /// Berekent de fase op basis van het aantal weken tot de doeldatum.
    static func calculate(weeksRemaining: Double) -> TrainingPhase {
        switch weeksRemaining {
        case ..<2:    return .tapering
        case 2..<4:   return .peakPhase
        case 4..<12:  return .buildPhase
        default:      return .baseBuilding
        }
    }

    // MARK: Epic 17.1 — Success Criteria per fase

    /// Retourneert de sportwetenschappelijke succescriteria voor deze fase,
    /// uitgedrukt als breuken van de blueprint-doelwaarden.
    var successCriteria: PhaseSuccessCriteria {
        switch self {
        case .baseBuilding:
            // Fundament leggen: 40% van de piekduurloop volstaat, 60% van het TRIMP-doel.
            return PhaseSuccessCriteria(
                longestSessionPct: 0.40,
                weeklyTrimpPct: 0.60,
                sessionWindowWeeks: 4,
                coaching: "We zitten in de **Base Building**-fase. Focus op laag-intensief volume en het leggen van het aerobe fundament. Geen intervaltraining — nog niet."
            )
        case .buildPhase:
            // Opbouw: 60% van de piekduurloop, 80% van het TRIMP-doel.
            return PhaseSuccessCriteria(
                longestSessionPct: 0.60,
                weeklyTrimpPct: 0.80,
                sessionWindowWeeks: 3,
                coaching: "We zitten in de **Build**-fase — het is tijd om de intensiteit op te schroeven. Voeg gecontroleerde intervaltrainingen toe en bouw de langste sessie geleidelijk op."
            )
        case .peakPhase:
            // Piek: 80% van de piekduurloop is vereist, volledig TRIMP-doel behalen.
            return PhaseSuccessCriteria(
                longestSessionPct: 0.80,
                weeklyTrimpPct: 1.00,
                sessionWindowWeeks: 3,
                coaching: "We zitten in de **Peak**-fase — maximale trainingsbelasting. Race-specifieke trainingen op wedstrijdintensiteit. Daarna volgt de taper."
            )
        case .tapering:
            // Afbouw: langste sessie MAXIMAAL 50% van de piekduurloop (niet te zwaar!), TRIMP terug naar 60%.
            // Venster van 2 weken: geeft een betrouwbaar beeld of de atleet écht aan het afbouwen is
            // (raceweek kan nog leeg zijn — 1 week terugkijken is dan te kort).
            return PhaseSuccessCriteria(
                longestSessionPct: 0.50,
                weeklyTrimpPct: 0.60,
                sessionWindowWeeks: 2,
                coaching: "We zitten in de **Taper**-fase. Minder is meer — houd sessies kort en licht. De benen worden scherp door rust, niet door extra kilometers."
            )
        }
    }
}

// MARK: - Epic 17.1: PeriodizationEngine — Data Types

/// Sportwetenschappelijke succescriteria voor één trainingsfase.
/// Uitgedrukt als breuk (0.0–1.0) van de blueprint-doelwaarden zodat
/// dezelfde criteria gelden voor marathon, halve marathon én fietstochten.
struct PhaseSuccessCriteria {
    /// Minimale langste sessie als breuk van `GoalBlueprint.minLongRunDistance`.
    /// Voorbeeld: 0.80 in de Peak-fase = langste sessie moet ≥80% van 32 km = ≥25.6 km zijn.
    let longestSessionPct: Double
    /// Minimale wekelijkse TRIMP als breuk van `GoalBlueprint.weeklyTrimpTarget`.
    /// In de Taper-fase is dit een MAXIMUM (de atleet moet juist minder doen).
    let weeklyTrimpPct: Double
    /// Aantal weken terugkijken om de langste sessie te bepalen (korter in Peak/Taper).
    let sessionWindowWeeks: Int
    /// Coaching-boodschap die de coach meekrijgt voor deze fase.
    let coaching: String
}

/// Resultaat van een volledige PeriodizationEngine evaluatie voor één doel.
struct PeriodizationResult {
    let goal: FitnessGoal
    let blueprint: GoalBlueprint
    let phase: TrainingPhase
    let criteria: PhaseSuccessCriteria

    /// Langste sessie (in meters) van het sport-type dat bij het blueprint past,
    /// binnen het `criteria.sessionWindowWeeks` terugkijkvenster.
    let longestRecentSessionMeters: Double

    /// Minimaal vereiste sessielengte = `blueprint.minLongRunDistance × criteria.longestSessionPct`.
    var requiredSessionMeters: Double {
        blueprint.minLongRunDistance * criteria.longestSessionPct
    }

    /// True als de langste sessie aan de fase-eis voldoet.
    /// In de Tapering-fase is de logica omgekeerd: de sessie moet juist KORTER zijn.
    var meetsLongestSessionCriteria: Bool {
        if phase == .tapering {
            return longestRecentSessionMeters <= requiredSessionMeters
        }
        return longestRecentSessionMeters >= requiredSessionMeters
    }

    /// Wekelijkse TRIMP-target voor deze fase = `blueprint.weeklyTrimpTarget × criteria.weeklyTrimpPct`.
    var targetWeeklyTrimp: Double {
        blueprint.weeklyTrimpTarget * criteria.weeklyTrimpPct
    }

    /// True als de sporter op het juiste TRIMP-niveau zit voor deze fase.
    /// In de Tapering-fase geldt ook hier de omgekeerde logica.
    var meetsWeeklyTrimpCriteria: Bool {
        if phase == .tapering {
            return currentWeeklyTrimp <= targetWeeklyTrimp
        }
        return currentWeeklyTrimp >= targetWeeklyTrimp
    }

    /// Actueel gemiddeld wekelijks TRIMP over de afgelopen 4 weken (ongeacht fase).
    let currentWeeklyTrimp: Double

    /// True als de sporter aan BEIDE criteria voldoet.
    var isOnTrack: Bool { meetsLongestSessionCriteria && meetsWeeklyTrimpCriteria }

    /// Volledige coaching-context inclusief fase, criteria en actuele status — klaar voor AI-injectie.
    var coachingContext: String {
        let weeksLeft = goal.targetDate.timeIntervalSince(Date()) / (7 * 86400)
        let weeksLeftStr = String(format: "%.1f", weeksLeft)
        let longestKm    = String(format: "%.1f", longestRecentSessionMeters / 1000)
        let requiredKm   = String(format: "%.1f", requiredSessionMeters / 1000)
        let sessionCheck = meetsLongestSessionCriteria ? "✅" : "❌"
        let trimpCheck   = meetsWeeklyTrimpCriteria    ? "✅" : "❌"
        let trimpTarget  = String(format: "%.0f", targetWeeklyTrimp)
        let trimpActual  = String(format: "%.0f", currentWeeklyTrimp)

        var lines = [
            "Fase: \(phase.displayName) (\(weeksLeftStr) weken resterend voor '\(goal.title)')",
            criteria.coaching,
            "\(sessionCheck) Langste sessie (afgelopen \(criteria.sessionWindowWeeks) weken): \(longestKm) km (eis: \(phase == .tapering ? "≤" : "≥")\(requiredKm) km)",
            "\(trimpCheck) Wekelijkse TRIMP: \(trimpActual) (doel: \(phase == .tapering ? "≤" : "≥")\(trimpTarget))",
        ]
        if !isOnTrack {
            lines.append("⚠️ De sporter voldoet nog niet aan alle criteria voor deze fase. Pas het schema aan.")
        }
        return lines.joined(separator: "\n")
    }
}

/// Represents a user's fitness goal.
/// Dit model wordt opgeslagen in SwiftData om lokale doelen bij te houden.
@Model
final class FitnessGoal {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String?
    var targetDate: Date
    var createdAt: Date
    var isCompleted: Bool
    var sportCategory: SportCategory?
    var targetTRIMP: Double? // Sprint 12.1: Benodigde belasting om dit doel te halen.

    init(id: UUID = UUID(),
         title: String,
         details: String? = nil,
         targetDate: Date,
         createdAt: Date = Date(),
         isCompleted: Bool = false,
         sportCategory: SportCategory? = nil,
         targetTRIMP: Double? = nil) {
        self.id = id
        self.title = title
        self.details = details
        self.targetDate = targetDate
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.sportCategory = sportCategory
        self.targetTRIMP = targetTRIMP
    }

    /// Huidige trainingsfase van dit doel op basis van weken resterend (Epic 16).
    /// Retourneert nil als het doel is afgerond of al verlopen.
    var currentPhase: TrainingPhase? {
        guard !isCompleted, Date() < targetDate else { return nil }
        let weeksRemaining = targetDate.timeIntervalSince(Date()) / (7 * 86400)
        return TrainingPhase.calculate(weeksRemaining: weeksRemaining)
    }

    /// Berekent of retourneert de Target TRIMP veilig, inclusief fail-safe fallback formule
    var computedTargetTRIMP: Double {
        if let trimp = targetTRIMP, trimp > 0 {
            return trimp
        }
        let days = max(1.0, targetDate.timeIntervalSince(createdAt) / 86400)
        return (days / 7.0) * 350.0
    }
}

/// Een historisch verslag van een activiteit (gesynchroniseerd met externe bronnen zoals Strava of HealthKit).
/// Dit wordt lokaal opgeslagen met SwiftData voor snelle toegang en offline analyses,
/// zoals het berekenen van het atletisch profiel.
@Model
final class ActivityRecord {
    /// De unieke identificatie van de activiteit, vaak afkomstig van de externe provider (zoals Strava ID of HealthKit UUID).
    @Attribute(.unique)
    var id: String

    var name: String
    var distance: Double // Afstand in meters
    var movingTime: Int // Tijd in seconden
    var averageHeartrate: Double?
    var sportCategory: SportCategory // Epic 12 Refactor: Gebruik van type-veilige enum
    var startDate: Date

    /// Berekende Trainingsbelasting (TRIMP) voor deze specifieke activiteit.
    var trimp: Double?

    // Epic 18: Subjectieve Feedback — Rate of Perceived Exertion (1-10) en stemming
    var rpe: Int?    // 1 = heel makkelijk, 10 = maximale inspanning
    var mood: String? // Bijv. "😌", "🟢", "🚀", "🤕", "🥵"

    /// Menselijke naam voor UI en AI-context.
    /// Legacy HealthKit-records bevatten soms 'HealthKit <rawValue>' (bijv. 'HealthKit 52') —
    /// deze property vervangt dat altijd door de leesbare naam van de SportCategory.
    var displayName: String {
        if name.hasPrefix("HealthKit") {
            return sportCategory.workoutName.prefix(1).uppercased() + sportCategory.workoutName.dropFirst()
        }
        return name
    }

    init(id: String, name: String, distance: Double, movingTime: Int, averageHeartrate: Double?, sportCategory: SportCategory, startDate: Date, trimp: Double? = nil, rpe: Int? = nil, mood: String? = nil) {
        self.id = id
        self.name = name
        self.distance = distance
        self.movingTime = movingTime
        self.averageHeartrate = averageHeartrate
        self.sportCategory = sportCategory
        self.startDate = startDate
        self.trimp = trimp
        self.rpe = rpe
        self.mood = mood
    }
}

/// Een meting van de hartslag op een specifiek tijdstip
struct HeartRateSample: Codable, Equatable {
    let timestamp: Date
    let bpm: Double
}

/// Details van een voltooide workout inclusief fysiologische data
struct WorkoutDetails: Codable, Equatable {
    let name: String
    let startDate: Date
    let duration: Double
    let averageHeartRate: Double
    let maxHeartRate: Double
    let restingHeartRate: Double
    let heartRateSamples: [HeartRateSample]
}

// MARK: - Epic 20: BYOK Multi-Provider Support

/// De AI-provider die de gebruiker heeft geconfigureerd voor de coach.
/// Enkel Gemini is in Sprint 20.1 volledig geïntegreerd; de andere providers zijn
/// beschikbaar als keuze in de UI en worden stapsgewijs uitgerold.
enum AIProvider: String, CaseIterable, Identifiable {
    case gemini    = "gemini"
    case openAI    = "openai"
    case anthropic = "anthropic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini:    return "Google Gemini"
        case .openAI:    return "OpenAI GPT"
        case .anthropic: return "Anthropic Claude"
        }
    }

    /// Placeholder-tekst in het SecureField zodat de gebruiker weet wat het verwachte formaat is.
    var keyPlaceholder: String {
        switch self {
        case .gemini:    return "AIzaSy..."
        case .openAI:    return "sk-..."
        case .anthropic: return "sk-ant-..."
        }
    }

    /// Directe URL waar de gebruiker een gratis API-sleutel kan aanmaken.
    var getKeyURL: URL? {
        switch self {
        case .gemini:    return URL(string: "https://aistudio.google.com/app/apikey")
        case .openAI:    return URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        }
    }

    /// True als deze provider volledig geïntegreerd is en direct bruikbaar is.
    var isSupported: Bool {
        self == .gemini
    }
}

/// De databron die door de gebruiker is gekozen voor de fysiologische analyses en historie.
enum DataSource: String, CaseIterable, Identifiable {
    case healthKit = "Apple HealthKit"
    case strava = "Strava API"

    var id: String { self.rawValue }
}

/// Gestandaardiseerde sportcategorieën voor de applicatie (Epic 12 Refactor).
enum SportCategory: String, Codable, CaseIterable, Identifiable {
    case running = "running"
    case cycling = "cycling"
    case swimming = "swimming"
    case strength = "strength"
    case walking = "walking"
    case triathlon = "triathlon"
    case other = "other"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .running: return "Hardlopen"
        case .cycling: return "Wielrennen"
        case .swimming: return "Zwemmen"
        case .strength: return "Krachttraining"
        case .walking: return "Wandelen"
        case .triathlon: return "Triatlon"
        case .other: return "Anders"
        }
    }

    /// Menselijke naam voor gebruik in coach-context en banners (bijv. "hardloopsessie", "fietstocht").
    /// Zorgt dat de AI nooit technische termen zoals 'HealthKit 52' gebruikt.
    var workoutName: String {
        switch self {
        case .running:   return "hardloopsessie"
        case .cycling:   return "fietstocht"
        case .swimming:  return "zwemsessie"
        case .strength:  return "krachttraining"
        case .walking:   return "wandeling"
        case .triathlon: return "triatlonsessie"
        case .other:     return "training"
        }
    }

    /// Mapt direct vanaf een HealthKit type voor robuustheid in plaats van string beschrijvingen
    static func from(hkType: UInt) -> SportCategory {
        // We gebruiken UInt omdat we HealthKit hier wellicht niet expliciet willen importeren op elke plek
        // 13 = cycling, 37 = running, 52 = walking, 16 = elliptical, 50 = traditionalStrengthTraining, 82 = swimming
        switch hkType {
        case 13: return .cycling
        case 37: return .running
        case 46, 82: return .swimming
        case 50, 59: return .strength
        case 52: return .walking
        case 83: return .triathlon
        default: return .other
        }
    }

    /// Factory methode om ruwe externe API strings (zoals "Ride")
    /// robuust te mappen naar de gestandaardiseerde `SportCategory`.
    static func from(rawString: String?) -> SportCategory {
        guard let raw = rawString?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .other
        }

        if raw.contains("run") || raw.contains("hardlopen") || raw == "hkworkoutactivitytyperunning" {
            return .running
        }

        if raw.contains("ride") || raw.contains("cycl") || raw.contains("fiets") || raw.contains("wielrennen") || raw == "hkworkoutactivitytypecycling" {
            return .cycling
        }

        if raw.contains("swim") || raw.contains("zwem") || raw == "hkworkoutactivitytypeswimming" {
            return .swimming
        }

        if raw.contains("strength") || raw.contains("weight") || raw.contains("kracht") || raw == "hkworkoutactivitytypetraditionalstrengthtraining" {
            return .strength
        }

        if raw.contains("walk") || raw.contains("wandelen") || raw == "hkworkoutactivitytypewalking" {
            return .walking
        }

        if raw.contains("triathlon") || raw.contains("triatlon") {
            return .triathlon
        }

        return .other
    }
}


/// De individuele suggestie voor een specifieke dag in de komende week.
struct SuggestedWorkout: Codable, Identifiable, Equatable {
    var id: UUID = UUID()

    /// De dag, bijv. "Maandag" of een specifieke datum "2023-11-01"
    let dateOrDay: String

    /// Type activiteit: e.g. "Hardlopen", "Fietsen", of "Rust"
    let activityType: String

    /// Voorgestelde duur in minuten (0 voor rust)
    let suggestedDurationMinutes: Int

    /// Beoogde belasting (TRIMP), 0 voor rust. Soms stuurt Gemini dit als String, of laat hij het weg.
    let targetTRIMP: Int?

    /// Korte toelichting, bijv. "Zone 2 herstelrit" of "Intervaltraining: 5x1000m"
    let description: String

    /// Doel hartslagzone, bijv. "Zone 2"
    let heartRateZone: String?

    /// Doel tempo, bijv. "5:30 min/km"
    let targetPace: String?

    enum CodingKeys: String, CodingKey {
        case dateOrDay
        case activityType
        case suggestedDurationMinutes
        case targetTRIMP
        case description
        case heartRateZone
        case targetPace
    }

    init(id: UUID = UUID(), dateOrDay: String, activityType: String, suggestedDurationMinutes: Int, targetTRIMP: Int?, description: String, heartRateZone: String? = nil, targetPace: String? = nil) {
        self.id = id
        self.dateOrDay = dateOrDay
        self.activityType = activityType
        self.suggestedDurationMinutes = suggestedDurationMinutes
        self.targetTRIMP = targetTRIMP
        self.description = description
        self.heartRateZone = heartRateZone
        self.targetPace = targetPace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dateOrDay = try container.decode(String.self, forKey: .dateOrDay)
        activityType = try container.decode(String.self, forKey: .activityType)
        // Gemini stuurt null voor rustdagen — decodeIfPresent met fallback naar 0
        suggestedDurationMinutes = (try? container.decodeIfPresent(Int.self, forKey: .suggestedDurationMinutes)) ?? 0
        description = try container.decode(String.self, forKey: .description)
        heartRateZone = try container.decodeIfPresent(String.self, forKey: .heartRateZone)
        targetPace = try container.decodeIfPresent(String.self, forKey: .targetPace)

        // Probeer targetTRIMP te decoderen als Int, en anders als String en parse naar Int
        if let intTRIMP = try? container.decodeIfPresent(Int.self, forKey: .targetTRIMP) {
            targetTRIMP = intTRIMP
        } else if let stringTRIMP = try? container.decodeIfPresent(String.self, forKey: .targetTRIMP), let parsedInt = Int(stringTRIMP) {
            targetTRIMP = parsedInt
        } else {
            targetTRIMP = nil
        }
    }
}

// MARK: - Epic 17: Goal-Specific Blueprints — Data Types

/// Ondersteunde blueprint-typen — gedetecteerd via sleutelwoorden in de doeltitel.
enum GoalBlueprintType: String, CaseIterable {
    case marathon     = "marathon"
    case halfMarathon = "half_marathon"
    case cyclingTour  = "cycling_tour"

    /// Sleutelwoorden die in de doeltitel moeten voorkomen voor automatische detectie (lowercase).
    var detectionKeywords: [String] {
        switch self {
        case .marathon:
            return ["marathon"]
        case .halfMarathon:
            return ["halve marathon", "half marathon", "21km", "21 km", "21,1"]
        case .cyclingTour:
            return ["arnhem", "karlsruhe", "cycling tour", "fietstocht", "fietsdoel", "gran fondo", "sportieve rit"]
        }
    }

    var displayName: String {
        switch self {
        case .marathon:     return "Marathon"
        case .halfMarathon: return "Halve Marathon"
        case .cyclingTour:  return "Fietstocht"
        }
    }
}

/// Een kritieke trainingseis die vóór een bepaald moment behaald moet zijn.
/// Onderdeel van een GoalBlueprint — één openstaande eis houdt de milestone rood.
struct EssentialWorkout: Equatable {
    /// Stabiele identifier voor de milestone-check (bijv. "marathon_long_run_32")
    let id: String
    /// Leesbare beschrijving voor UI en AI-context (bijv. "32 km duurloop")
    let description: String
    /// Minimale afstand in meters voor deze eis, of nil als duur leidend is
    let minimumDistanceMeters: Double?
    /// Vereiste sportsoort (type-veilig via SportCategory)
    let requiredSportCategory: SportCategory
    /// Aantal weken vóór de einddatum waarbinnen deze workout voltooid moet zijn
    let mustCompleteByWeeksBefore: Int
}

/// Sportwetenschappelijk trainingsplan voor een specifiek doeltype.
/// Bevat harde regels die — ongeacht AI-output — altijd van toepassing zijn.
struct GoalBlueprint {
    let goalType: GoalBlueprintType
    /// Minimale afstand van de langste duurtraining in meters (bijv. 32.000 voor marathon)
    let minLongRunDistance: Double
    /// Weken vóór de race dat de afbouwperiode (taper) start
    let taperPeriodWeeks: Int
    /// Wekelijkse TRIMP-doelstelling tijdens de opbouwfase
    let weeklyTrimpTarget: Double
    /// Kritieke trainingen die verplicht in het schema moeten voorkomen
    let essentialWorkouts: [EssentialWorkout]
}

/// Voortgangsstatus van één kritieke trainingseis t.o.v. de deadline.
struct MilestoneStatus: Identifiable, Equatable {
    let id: String
    let description: String
    /// True als er een passende activiteit gevonden is die aan de eis voldoet
    let isSatisfied: Bool
    /// Datum waarop de eis behaald werd (alleen ingevuld als isSatisfied == true)
    let satisfiedByDate: Date?
    /// Uiterste datum waarop deze workout gedaan moet zijn (berekend vanuit targetDate)
    let deadline: Date
    /// Aantal weken vóór de race dat deze eis uiterlijk voltooid moet zijn
    let weeksBefore: Int
}

/// Volledige blauwdrukcheck voor één doel: blueprint + alle milestone statussen.
struct BlueprintCheckResult {
    let blueprint: GoalBlueprint
    let goal: FitnessGoal
    let milestones: [MilestoneStatus]

    /// True als alle kritieke eisen waarvan de deadline al verstreken is ook behaald zijn.
    var isOnTrack: Bool {
        milestones
            .filter { $0.deadline < Date() }
            .allSatisfy { $0.isSatisfied }
    }

    var satisfiedCount: Int { milestones.filter { $0.isSatisfied }.count }
    var totalCount: Int { milestones.count }
}

/// Slaat de dagelijkse Readiness Score op, berekend op basis van slaap en HRV (Epic 14).
/// Er wordt maximaal één record per dag bewaard — upsert via de ReadinessService.
@Model
final class DailyReadiness {
    /// Genormaliseerd naar het begin van de dag (00:00:00) voor consistente opslag en queries.
    var date: Date
    var sleepHours: Double
    /// Gemiddelde HRV van de afgelopen nacht in milliseconden.
    var hrv: Double
    /// De berekende Vibe/Readiness Score, 0 (volledig overtraind/uitgeput) t/m 100 (optimaal).
    var readinessScore: Int

    init(date: Date, sleepHours: Double, hrv: Double, readinessScore: Int) {
        self.date = Calendar.current.startOfDay(for: date)
        self.sleepHours = sleepHours
        self.hrv = hrv
        self.readinessScore = readinessScore
    }
}

/// Structuur om via JSON een nieuw geheugen inclusief optionele verloopdatum te ontvangen.
struct ExtractedPreference: Codable, Equatable {
    let text: String
    let expirationDate: String? // Verwacht formaat: "YYYY-MM-DD"
}

/// De gestructureerde JSON-output (vanuit Gemini) voor een compleet weekschema.
struct SuggestedTrainingPlan: Codable, Equatable {
    let motivation: String
    let workouts: [SuggestedWorkout]
    let newPreferences: [ExtractedPreference]?
}

import SwiftUI

/// Shared state manager for the active training plan.
/// It acts as the single source of truth for both DashboardView and ChatView.
@MainActor
class TrainingPlanManager: ObservableObject {
    @Published var activePlan: SuggestedTrainingPlan?
    @AppStorage("latestSuggestedPlanData") private var latestSuggestedPlanData: Data = Data()

    init() {
        loadPlan()
    }

    /// Loads the plan from AppStorage.
    private func loadPlan() {
        if let decodedPlan = try? JSONDecoder().decode(SuggestedTrainingPlan.self, from: latestSuggestedPlanData) {
            self.activePlan = decodedPlan
        }
    }

    /// Updates the plan, publishes the change, and persists it to AppStorage.
    func updatePlan(_ newPlan: SuggestedTrainingPlan) {
        self.activePlan = newPlan
        if let encoded = try? JSONEncoder().encode(newPlan) {
            latestSuggestedPlanData = encoded
        }
    }
}
