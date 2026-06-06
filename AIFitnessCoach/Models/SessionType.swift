import Foundation

// MARK: - Epic 33 Story 33.1: Session-Type Taxonomy
//
// `SessionType` describes the physiological intent of a training session — not the
// activity form. That is deliberate: an interval workout can be either `.vo2Max` or `.threshold`
// depending on the zone, and `.endurance` fits both a long run and a
// relaxed bike ride. The coach uses this type to calibrate feedback ("well recovered"
// for a Social Ride with low HR instead of "you were too slow").

/// Physiological intent of one training session. Chosen from seven common
/// training-domain categories — no sport-specific names.
enum SessionType: String, Codable, CaseIterable, Identifiable {
    case vo2Max     // 95-100% HRmax — short intervals 3-5 min, maximal aerobic stimulus
    case threshold  // 88-92% HRmax — lactate threshold, 8-30 min sustained
    case tempo      // 80-87% HRmax — sub-threshold "comfortably hard", aerobic stress
    case endurance  // 65-78% HRmax — long aerobic session, foundation
    case recovery   // <65% HRmax — active recovery, metabolically low
    case social     // intensity not leading — mental recovery, social ride/run
    case race       // race effort — all-out, race day

    var id: String { rawValue }

    /// Short name for UI context (Picker, badges).
    /// Epic #37 story 37.1c: NOT localized — this displayName is interpolated into coach prompts
    /// (LastWorkoutContextFormatter, IntentExecutionContextFormatter, WorkoutHistoryContextBuilder),
    /// so it stays Dutch for prompt stability until 37.4 splits the UI label from the prompt term.
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

    /// SF Symbol for UI presentation. No accent colour — that comes from ThemeManager.
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

/// Describes the physiological expectation per session type — zone range and perceived effort
/// (RPE, Borg scale 1-10). Used by the coach to detect deviations
/// ("high HR on a Recovery session suggests fatigue") and to give the planner concrete
/// targets.
struct SessionIntent {
    /// Target zone range on a 1-5 scale of training zones.
    let targetZoneRange: ClosedRange<Int>
    /// Expected RPE on the Borg 1-10 scale.
    let expectedRPERange: ClosedRange<Int>
    /// Short coaching description — intended for AI-prompt injection and UI tooltips.
    let coachingSummary: String
}

extension SessionType {
    /// Physiological blueprint of this session type.
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
