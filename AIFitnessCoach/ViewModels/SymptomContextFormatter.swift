import Foundation

/// Pure-Swift formatter for the symptom/injury context block (Epic 18 Sprint 2).
///
/// `SymptomTracker` is the 'Single Source of Truth' for injury status:
/// - Score > 0 → active complaint, with hard constraints based on severity
/// - Score == 0 → recovered, replaces any still-active `UserPreference` text
/// - No score entered + active `UserPreference` → show as 'unknown, score not yet entered'
///
/// Called by `ChatViewModel.cacheSymptomContext` and directly testable in tests
/// without an `@AppStorage` or `UserDefaults` fixture.
enum SymptomContextFormatter {

    /// Formats symptoms + injury preferences into a context string for the AI coach.
    /// - Parameters:
    ///   - symptoms: All `Symptom` records (the formatter filters for today itself).
    ///   - preferences: Active `UserPreference` records (expired prefs are filtered out).
    ///   - now: Date for determining "today" and "active" prefs (default `Date()`).
    /// - Returns: The formatted context string. Empty string if there's nothing to report.
    static func format(symptoms: [Symptom],
                       preferences: [UserPreference] = [],
                       now: Date = Date()) -> String {
        let todayStart = Calendar.current.startOfDay(for: now)
        // Fetch ALL records of today — including score 0 (= recovered)
        let todayAll    = symptoms.filter { $0.date >= todayStart }
        let todayActive = todayAll.filter { $0.severity > 0 }

        // Determine active injury preferences (not expired).
        // Epic #37 story 37.4: body-part keywords are reused from the BodyArea enum (NL+EN+DE+ES
        // union, single source of truth) and combined with general injury words in all four
        // supported languages so a complaint typed in any language is detected.
        let bodyPartKeywords = BodyArea.allCases.flatMap { $0.injuryKeywords }
        let generalInjuryWords = ["blessure", "pijn", "klacht",
                                  "injury", "pain", "hurt", "sore", "ache",
                                  "verletzung", "schmerz", "weh",
                                  "lesión", "lesion", "dolor", "molestia"]
        let injuryKeywords = bodyPartKeywords + generalInjuryWords
        let activeInjuryPrefs = preferences.filter { pref in
            // swiftlint:disable:next force_unwrapping
            guard pref.expirationDate == nil || pref.expirationDate! > now else { return false } // `||` short-circuits: `!` only reached when expirationDate != nil
            let text = pref.preferenceText.lowercased()
            return injuryKeywords.contains(where: { text.contains($0) })
        }

        // All areas measured TODAY (score 0 and > 0) count as 'tracked'
        let allTrackedAreas = Set(todayAll.map { $0.bodyArea.rawValue.lowercased() })

        // Nothing to report: no measurement today and no active complaint preference
        guard !todayAll.isEmpty || !activeInjuryPrefs.isEmpty else {
            return ""
        }

        var scoreLines: [String] = []
        var constraintLines: [String] = []
        var recoveryLines: [String] = []

        // 1. Active complaints (score > 0) — with hard constraints based on severity
        for s in todayActive {
            let label = BodyArea.severityLabel(s.severity)
            scoreLines.append("• \(s.bodyArea.rawValue): \(s.severity)/10 (\(label))")

            if s.severity > 5 {
                switch s.bodyArea {
                case .calf:
                    constraintLines.append("🚫 HARD CONSTRAINT Calf (\(s.severity)/10 > 5): RUNNING IS STRICTLY FORBIDDEN. Cycling and swimming are allowed.")
                case .ankle:
                    constraintLines.append("🚫 HARD CONSTRAINT Ankle (\(s.severity)/10 > 5): RUNNING IS STRICTLY FORBIDDEN. Cycling is safe.")
                case .back:
                    constraintLines.append("🚫 HARD CONSTRAINT Back (\(s.severity)/10 > 5): no running or strength training. Cycling (upright) and swimming are safe.")
                case .knee:
                    constraintLines.append("🚫 HARD CONSTRAINT Knee (\(s.severity)/10 > 5): no running or jumping. Cycling and swimming are safe.")
                case .hand:
                    constraintLines.append("🚫 HARD CONSTRAINT Hand (\(s.severity)/10 > 5): no strength training or weight-bearing exercises.")
                case .shoulder:
                    constraintLines.append("🚫 HARD CONSTRAINT Shoulder (\(s.severity)/10 > 5): no swimming or push exercises.")
                }
            } else if s.severity > 0 && s.severity < 3 {
                if s.bodyArea == .calf || s.bodyArea == .ankle {
                    scoreLines.append("  ↳ Score < 3: cautious running alternatives negotiable (short, Zone 1, max 30 min).")
                }
            }
        }

        // 2. Recovered areas (score == 0 today) — only if a matching injury preference
        //    exists. This prevents false recovery messages for body parts that were never injured.
        for s in todayAll where s.severity == 0 {
            let matchesPref = activeInjuryPrefs.contains { pref in
                s.bodyArea.injuryKeywords.contains(where: { pref.preferenceText.lowercased().contains($0) })
            }
            guard matchesPref else { continue }
            let areaName = s.bodyArea.rawValue
            recoveryLines.append(
                "✅ RECOVERED (\(areaName): 0/10): The user is complaint-free for \(areaName) today. " +
                "INSTRUCTION: Celebrate this explicitly in your Insight ('Great that your \(areaName.lowercased()) is back to 0!'). " +
                "Normal load may be proposed again, but advise a cautious, step-by-step build-up."
            )
        }

        // 3. Injury preferences without a score today — only show if the area is NOT already
        //    measured (prevents duplicates with scoreLines or recoveryLines)
        for pref in activeInjuryPrefs {
            let alreadyTracked = BodyArea.allCases.contains { area in
                allTrackedAreas.contains(area.rawValue.lowercased()) &&
                area.injuryKeywords.contains(where: { pref.preferenceText.lowercased().contains($0) })
            }
            if !alreadyTracked {
                scoreLines.append("• \(pref.preferenceText) (score not entered today — use caution)")
            }
        }

        // Combine in fixed order: scores → hard constraints → recovery messages
        var combined = scoreLines
        if !constraintLines.isEmpty {
            combined += ["", "ACTIVE CONSTRAINTS:"] + constraintLines
        }
        if !recoveryLines.isEmpty {
            combined += ["", "RECOVERY MESSAGES:"] + recoveryLines
        }

        // Empty context if there are only score-0 records without a matching preference
        // (e.g. a random body part entered at 0 without an earlier complaint)
        if combined.isEmpty {
            return ""
        }

        return combined.joined(separator: "\n")
    }
}
