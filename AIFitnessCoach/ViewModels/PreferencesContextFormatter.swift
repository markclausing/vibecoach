import Foundation

// MARK: - PreferencesContextFormatter
//
// Builds the preferences block in the Gemini system context. Separates temporary
// preferences (with `expirationDate`) from pinned preferences (without `expirationDate`)
// and gives the coach an explicit priority rule: temporary preferences override pinned
// rules during their lifetime.
//
// Background: a user reported that after a vacation mention ("Rome, walking only") the
// coach initially adjusted the schedule correctly, but on a schedule refresh let the
// pinned "strength training every Tue/Thu" rule sneak back in — no distinction between
// temporary and permanent in the old prompt injection.

enum PreferencesContextFormatter {

    /// Builds the preferences block for the coach context. Returns an empty string if
    /// there are no active preferences (so the prompt stays clean).
    /// - Parameters:
    ///   - activePreferences: all preferences with `isActive == true` from SwiftData.
    ///   - now: current time (injectable for tests).
    static func format(activePreferences: [UserPreference], now: Date = Date()) -> String {
        // Filter expired temporary preferences — `expirationDate <= now` means elapsed.
        let valid = activePreferences.filter { pref in
            if let exp = pref.expirationDate { return exp > now }
            return true
        }
        guard !valid.isEmpty else { return "" }

        let temporary = valid.filter { $0.expirationDate != nil }
        let permanent = valid.filter { $0.expirationDate == nil }

        var output = ""

        if !permanent.isEmpty {
            let lines = permanent.map { "- \($0.preferenceText)" }.joined(separator: "\n")
            output += """
            [PINNED RULES (long-term, apply unless a temporary preference overrides them):
            \(lines)]


            """
        }

        if !temporary.isEmpty {
            let formatter = AppDateFormatters.fixed("yyyy-MM-dd")
            let lines = temporary.map { pref in
                "- \(pref.preferenceText) (temporary, valid until \(formatter.string(from: pref.expirationDate!)))"
            }.joined(separator: "\n")
            output += """
            [TEMPORARY PREFERENCES (override pinned rules for their duration):
            \(lines)

            CRITICAL INSTRUCTION: While a temporary preference is active it takes precedence OVER any pinned rule it conflicts with. Example: if 'on holiday, walking only' is active, do NOT schedule strength training or bike rides in that period — not even if there is a pinned Tue/Thu gym rule.]


            """
        }

        return output
    }
}
