import Foundation

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
    /// Korte focusomschrijving voor de status-badge op het dashboard.
    var focusDescription: String {
        switch self {
        case .baseBuilding: return "Aerobe basis leggen"
        case .buildPhase:   return "Uithoudingsvermogen opbouwen"
        case .peakPhase:    return "Race-intensiteit bereiken"
        case .tapering:     return "Herstellen en scherp worden"
        }
    }

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

// MARK: Epic Doel-Intenties: IntentModifier

/// Trainingsmodifier op basis van de gebruiker's doel-intentie, evenementformaat en VibeScore.
/// Gegenereerd door PeriodizationEngine en doorgegeven aan de AI-coach via coachingContext.
struct IntentModifier {
    /// Vermenigvuldigingsfactor op de wekelijkse TRIMP-target (1.0 = ongewijzigd, 0.90 = uitlopen-modus).
    let weeklyTrimpMultiplier: Double
    /// Of hoge intensiteit (lactaat/tempo-intervallen) deze week toegestaan is.
    let allowHighIntensity: Bool
    /// Of back-to-back zware sessies benadrukt worden (true bij .multiDayStage).
    let backToBackEmphasis: Bool
    /// Of stretch-pace trainingen gepland mogen worden (alleen bij .peakPerformance + VibeScore > 65).
    let stretchPaceAllowed: Bool
    /// AI-instructie voor de coach — gegenereerd op basis van intentie + formaat + VibeScore.
    let coachingInstruction: String
}

/// Sportwetenschappelijke succescriteria voor één trainingsfase.
/// Uitgedrukt als breuk (0.0–1.0) van de blueprint-doelwaarden zodat
/// dezelfde criteria gelden voor marathon, halve marathon én fietstochten.
struct PhaseSuccessCriteria {
    /// Minimale langste sessie als breuk van `GoalBlueprint.minLongRunDistance`.
    /// Voorbeeld: 0.80 in de Peak-fase = langste sessie moet ≥80% van 32 km = ≥25.6 km zijn.
    let longestSessionPct: Double
    /// Minimale wekelijkse TRIMP als breuk of `GoalBlueprint.weeklyTrimpTarget`.
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

    /// Modifier op basis van intentie, formaat en VibeScore — gegenereerd door PeriodizationEngine.
    let intentModifier: IntentModifier

    /// Gecorrigeerd wekelijks TRIMP-target na toepassing van de intentie-multiplier.
    var adjustedWeeklyTrimpTarget: Double { targetWeeklyTrimp * intentModifier.weeklyTrimpMultiplier }

    /// True als de sporter aan BEIDE criteria voldoet.
    var isOnTrack: Bool { meetsLongestSessionCriteria && meetsWeeklyTrimpCriteria }

    /// Fase + focus voor de status-badge boven het schema.
    var phaseBadgeText: String { "\(phase.displayName) — \(phase.focusDescription)" }

    /// Voortgangsitems voor de MilestoneProgressCard.
    /// Elk item heeft een label, huidige waarde, vereiste waarde en of het behaald is.
    struct MilestoneItem {
        let label: String
        let detail: String          // bijv. "60 km langste rit afgelopen 3 weken"
        let current: Double
        let required: Double
        let isMet: Bool
        let isInverted: Bool        // true bij tapering: lager is beter
        var progress: Double {
            guard required > 0 else { return 0 }
            let ratio = current / required
            return isInverted ? min(1.0, 2.0 - ratio) : min(1.0, ratio)
        }
    }

    var milestoneItems: [MilestoneItem] {
        let sessionUnit = blueprint.goalType == .cyclingTour ? "km rit" : "km loop"
        let sessionItem = MilestoneItem(
            label: "Langste sessie",
            detail: "\(String(format: "%.0f", requiredSessionMeters / 1000)) \(sessionUnit) \(phase == .tapering ? "(max)" : "(min)") — \(criteria.sessionWindowWeeks) weken venster",
            current: longestRecentSessionMeters / 1000,
            required: requiredSessionMeters / 1000,
            isMet: meetsLongestSessionCriteria,
            isInverted: phase == .tapering
        )
        let trimpItem = MilestoneItem(
            label: "Wekelijkse belasting",
            detail: "\(String(format: "%.0f", targetWeeklyTrimp)) TRIMP/week \(phase == .tapering ? "(max)" : "(min)")",
            current: currentWeeklyTrimp,
            required: targetWeeklyTrimp,
            isMet: meetsWeeklyTrimpCriteria,
            isInverted: phase == .tapering
        )
        return [sessionItem, trimpItem]
    }

    /// Volledige coaching-context inclusief fase, criteria, status en gedragsinstructies — klaar voor AI-injectie.
    /// Sprint 17.2: Bevat nu expliciete compliment-triggers, urgente mijlpaal-alerts en schema-verantwoordingsplicht.
    var coachingContext: String {
        let weeksLeft    = goal.weeksRemaining
        let weeksLeftStr = String(format: "%.1f", weeksLeft)
        let longestKm    = String(format: "%.1f", longestRecentSessionMeters / 1000)
        let requiredKm   = String(format: "%.1f", requiredSessionMeters / 1000)
        let sessionCheck = meetsLongestSessionCriteria ? "✅" : "❌"
        let trimpCheck   = meetsWeeklyTrimpCriteria    ? "✅" : "❌"
        let trimpTarget  = String(format: "%.0f", targetWeeklyTrimp)
        let trimpActual  = String(format: "%.0f", currentWeeklyTrimp)
        let sessionLabel = phase == .tapering ? "≤\(requiredKm) km (tapering: bewust MINDER)" : "≥\(requiredKm) km"

        var lines = [
            "═══ PERIODISERING: '\(goal.title)' ═══",
            "Fase: \(phase.displayName) | \(weeksLeftStr) weken resterend",
            criteria.coaching,
            "",
            "SUCCESCRITERIA DEZE FASE:",
            "\(sessionCheck) Langste sessie (afgelopen \(criteria.sessionWindowWeeks) weken): \(longestKm) km (eis: \(sessionLabel))",
            "\(trimpCheck) Wekelijkse TRIMP: \(trimpActual) TRIMP/week (eis: \(phase == .tapering ? "≤" : "≥")\(trimpTarget))",
        ]

        // Compliment-triggers — coach MOET dit gebruiken als opening
        if meetsLongestSessionCriteria {
            lines.append("")
            lines.append("🎉 COMPLIMENT TRIGGER: De langste-sessie-eis is behaald! Begin je antwoord met een oprecht compliment hierover. Benoem de specifieke afstand.")
        } else {
            let shortfallKm = String(format: "%.1f", max(0, requiredSessionMeters - longestRecentSessionMeters) / 1000)
            lines.append("")
            lines.append("🚨 KRITIEKE MIJLPAAL ACHTERSTAND: De langste sessie is \(shortfallKm) km te kort voor de \(phase.displayName). Dit is de #1 prioriteit voor het schema deze week. Wees direct maar motiverend — noem de concrete doelafstand.")
        }

        if meetsWeeklyTrimpCriteria && phase != .tapering {
            lines.append("🎉 COMPLIMENT TRIGGER: Het wekelijkse TRIMP-doel is behaald. Benoem dit als positief signaal van consistentie.")
        }

        // Schema-verantwoordingsplicht bij blessure of aanpassing
        lines.append("")
        lines.append("SCHEMA-VERANTWOORDINGSPLICHT: Als je het schema aanpast (bijv. wegens blessure of overbelasting), MOET je expliciet uitleggen hoe de \(phase.displayName)-eis (\(sessionLabel)) nog steeds haalbaar blijft. Gebruik sportspecifieke alternatieven als de primaire sport tijdelijk niet kan. Bijv: 'Ik vervang je hardloopsessie door fietsen, maar de aerobe basis voor \(goal.title) bewaken we zo...'")

        // Doel-Intentie sectie — altijd injecteren zodat de coach weet hoe te prioriteren
        lines.append("")
        lines.append(intentModifier.coachingInstruction)

        return lines.joined(separator: "\n")
    }
}
