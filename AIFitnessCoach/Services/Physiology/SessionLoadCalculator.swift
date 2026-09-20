import Foundation

// MARK: - Epic #74: Session load (Foster sRPE × duration)

/// Turns a post-workout check-in into a *session load* — the strain of the session as a
/// whole, not just how intense it felt minute to minute.
///
/// Why this exists: RPE on its own measures **intensity**. A 3-hour endurance run at a
/// conversational pace scores a low RPE while still being one of the heaviest sessions of
/// the month, because strain is intensity *times* time. Reading the bare RPE made the coach
/// treat exactly that session as "an easy day with room to spare" — the opposite of the
/// recovery it demands.
///
/// The model is Foster's session-RPE: `load = RPE × duration in minutes`, expressed in
/// arbitrary units (AU). It is deliberately simple and needs no extra user input — `rpe` and
/// `movingTime` are already on `ActivityRecord`, so there is no schema change here.
///
/// Pure Swift, no AppStorage/UserDefaults (CLAUDE.md §6) — the caller passes everything in.
enum SessionLoadCalculator {

    /// Qualitative band for a session load, used to steer the coach's recovery advice.
    /// The cut-offs are heuristic: they are tuned so that a long endurance session at a
    /// low RPE still lands in `demanding`/`veryDemanding`, which is the whole point of
    /// the metric. They are not a validated clinical scale.
    enum Band: String, CaseIterable {
        /// < 150 AU — a short or genuinely easy session.
        case light
        /// 150–299 AU — a normal training session.
        case moderate
        /// 300–499 AU — a substantial session; noticeable the next day.
        case substantial
        /// 500–699 AU — demanding; plan an easy day after it.
        case demanding
        /// ≥ 700 AU — very demanding; typically needs multiple recovery days.
        case veryDemanding

        /// English label for the coach prompt (the prompt body is English, CLAUDE.md §13).
        var promptLabel: String {
            switch self {
            case .light:         return "light"
            case .moderate:      return "moderate"
            case .substantial:   return "substantial"
            case .demanding:     return "demanding"
            case .veryDemanding: return "very demanding"
            }
        }

        /// Whether this band means the session needs deliberate recovery even when the
        /// reported RPE was low. This is the flag that stops "low RPE + high volume" from
        /// being read as spare capacity.
        var requiresRecovery: Bool {
            switch self {
            case .light, .moderate, .substantial: return false
            case .demanding, .veryDemanding:      return true
            }
        }
    }

    /// A computed session load plus the band it falls in.
    struct Result: Equatable {
        /// Load in arbitrary units (AU), rounded to a whole number.
        let load: Int
        /// Duration that produced it, in whole minutes.
        let durationMinutes: Int
        /// The RPE the user reported (1–10).
        let rpe: Int
        let band: Band
    }

    /// Computes the session load for a rated activity.
    ///
    /// - Parameters:
    ///   - rpe: the reported RPE. `nil`, the 'ignored' sentinel (0) and out-of-scale values
    ///     yield `nil` — there is no session-RPE without a rating.
    ///   - durationSeconds: `movingTime` of the activity. Must be positive.
    /// - Returns: the load + band, or `nil` when the inputs cannot produce a meaningful load.
    static func calculate(rpe: Int?, durationSeconds: Int?) -> Result? {
        guard let rpe, (1...10).contains(rpe) else { return nil }
        guard let durationSeconds, durationSeconds > 0 else { return nil }

        // Round to the nearest minute rather than truncating: a 90-second effort should not
        // collapse to a 1-minute session, and the load is an arbitrary-unit heuristic anyway.
        let minutes = Int((Double(durationSeconds) / 60).rounded())
        guard minutes > 0 else { return nil }

        let load = rpe * minutes
        return Result(load: load, durationMinutes: minutes, rpe: rpe, band: band(for: load))
    }

    /// Maps a raw load in AU onto its qualitative band.
    static func band(for load: Int) -> Band {
        switch load {
        case ..<150:   return .light
        case ..<300:   return .moderate
        case ..<500:   return .substantial
        case ..<700:   return .demanding
        default:       return .veryDemanding
        }
    }
}
