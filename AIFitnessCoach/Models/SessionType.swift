import Foundation

// MARK: - Epic 33 Story 33.1: Sessie-Type Taxonomie
//
// `SessionType` beschrijft de fysiologische intentie van een trainingssessie — niet de
// activiteit-vorm. Dat is bewust: een interval-training kan zowel `.vo2Max` als `.threshold`
// zijn afhankelijk van de zone, en `.endurance` past zowel bij een lange duurloop als een
// rustige fietstocht. De coach gebruikt dit type om feedback te kalibreren ("goed hersteld"
// bij een Social Ride met lage HR i.p.v. "je was te langzaam").

/// Fysiologische intentie van één trainingssessie. Gekozen uit zeven gangbare
/// trainings-domein-categorieën — geen sport-specifieke benamingen.
enum SessionType: String, Codable, CaseIterable, Identifiable {
    case vo2Max     // 95-100% HRmax — korte intervallen 3-5 min, maximale aerobe stimulus
    case threshold  // 88-92% HRmax — lactaat-drempel, 8-30 min sustained
    case tempo      // 80-87% HRmax — sub-threshold "comfortabel hard", aerobe stress
    case endurance  // 65-78% HRmax — lange aerobe sessie, fundament
    case recovery   // <65% HRmax — actief herstel, metabool laag
    case social     // intensiteit niet leidend — mentaal herstel, sociale rit/run
    case race       // wedstrijd-effort — alle-out, raceday

    var id: String { rawValue }

    /// Korte Nederlandstalige naam voor UI-context (Picker, badges).
    var displayName: String {
        switch self {
        case .vo2Max:    return "VO₂max"
        case .threshold: return "Drempel"
        case .tempo:     return "Tempo"
        case .endurance: return "Duurtraining"
        case .recovery:  return "Herstel"
        case .social:    return "Sociaal"
        case .race:      return "Wedstrijd"
        }
    }

    /// SF Symbol voor UI-presentatie. Geen accent-kleur — die komt van ThemeManager.
    var icon: String {
        switch self {
        case .vo2Max:    return "lungs.fill"
        case .threshold: return "waveform.path.ecg"
        case .tempo:     return "speedometer"
        case .endurance: return "figure.run.circle"
        case .recovery:  return "leaf.fill"
        case .social:    return "person.2.fill"
        case .race:      return "flag.checkered"
        }
    }
}

// MARK: - SessionIntent

/// Beschrijft de fysiologische verwachting per sessie-type — zonebereik en gevoelde inspanning
/// (RPE, Borg-schaal 1-10). Wordt door de coach gebruikt om afwijkingen te detecteren
/// ("hoge HR bij een Recovery-sessie suggereert vermoeidheid") en om de planner concrete
/// targets te geven.
struct SessionIntent {
    /// Doel-zonebereik op een 1-5 schaal van trainingszones.
    let targetZoneRange: ClosedRange<Int>
    /// Verwachte RPE op de Borg 1-10 schaal.
    let expectedRPERange: ClosedRange<Int>
    /// Korte coaching-omschrijving — bedoeld voor AI-prompt-injectie en UI-tooltips.
    let coachingSummary: String
}

extension SessionType {
    /// Fysiologische blauwdruk van dit sessie-type.
    var intent: SessionIntent {
        switch self {
        case .vo2Max:
            return SessionIntent(
                targetZoneRange: 5...5,
                expectedRPERange: 8...10,
                coachingSummary: "Maximale aerobe stimulus. Korte intervallen op zone 5 (>90% HRmax) met volledig herstel ertussen. Doel: VO₂max verhogen."
            )
        case .threshold:
            return SessionIntent(
                targetZoneRange: 4...4,
                expectedRPERange: 7...8,
                coachingSummary: "Lactaat-drempel werk. Sustained zone 4 (88-92% HRmax) tussen 8 en 30 minuten. Doel: drempel-power omhoog."
            )
        case .tempo:
            return SessionIntent(
                targetZoneRange: 3...3,
                expectedRPERange: 5...7,
                coachingSummary: "Sub-threshold tempo (zone 3, 80-87% HRmax). Comfortabel hard, langer dan threshold. Bouwt aerobe capaciteit en mentale taaiheid."
            )
        case .endurance:
            return SessionIntent(
                targetZoneRange: 2...2,
                expectedRPERange: 3...5,
                coachingSummary: "Aerobe basis (zone 2, 65-78% HRmax). Lange sessie, kan praten. Doel: vetverbranding en mitochondriale dichtheid."
            )
        case .recovery:
            return SessionIntent(
                targetZoneRange: 1...1,
                expectedRPERange: 1...3,
                coachingSummary: "Actief herstel (zone 1, <65% HRmax). Korte sessie, lage HR. Stimuleert circulatie zonder belasting toe te voegen."
            )
        case .social:
            return SessionIntent(
                targetZoneRange: 1...3,
                expectedRPERange: 2...6,
                coachingSummary: "Sociale sessie — intensiteit volgt het tempo van de groep, niet een fysiologisch doel. Beoordeel niet op zone-discipline maar op mentaal herstel."
            )
        case .race:
            return SessionIntent(
                targetZoneRange: 4...5,
                expectedRPERange: 9...10,
                coachingSummary: "Wedstrijd-effort. Alle-out volgens race-strategie. Niet meten met training-zones — dit is performance-uitvoering."
            )
        }
    }
}
