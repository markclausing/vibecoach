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
                coachingSummary: "Maximum aerobic stimulus. Short intervals at zone 5 (>90% HRmax) with full recovery in between. Goal: raise VO₂max."
            )
        case .threshold:
            return SessionIntent(
                targetZoneRange: 4...4,
                expectedRPERange: 7...8,
                coachingSummary: "Lactate-threshold work. Sustained zone 4 (88-92% HRmax) between 8 and 30 minutes. Goal: raise threshold power."
            )
        case .tempo:
            return SessionIntent(
                targetZoneRange: 3...3,
                expectedRPERange: 5...7,
                coachingSummary: "Sub-threshold tempo (zone 3, 80-87% HRmax). Comfortably hard, longer than threshold. Builds aerobic capacity and mental toughness."
            )
        case .endurance:
            return SessionIntent(
                targetZoneRange: 2...2,
                expectedRPERange: 3...5,
                coachingSummary: "Aerobic base (zone 2, 65-78% HRmax). Long session, can hold a conversation. Goal: fat burning and mitochondrial density."
            )
        case .recovery:
            return SessionIntent(
                targetZoneRange: 1...1,
                expectedRPERange: 1...3,
                coachingSummary: "Active recovery (zone 1, <65% HRmax). Short session, low HR. Stimulates circulation without adding load."
            )
        case .social:
            return SessionIntent(
                targetZoneRange: 1...3,
                expectedRPERange: 2...6,
                coachingSummary: "Social session — intensity follows the group's pace, not a physiological goal. Don't judge on zone discipline but on mental recovery."
            )
        case .race:
            return SessionIntent(
                targetZoneRange: 4...5,
                expectedRPERange: 9...10,
                coachingSummary: "Race effort. All-out per race strategy. Don't measure with training zones — this is performance execution."
            )
        }
    }
}
