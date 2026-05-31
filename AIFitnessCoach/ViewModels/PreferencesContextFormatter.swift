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
            [VASTGEPINDE REGELS (langlopend, gelden tenzij een tijdelijke voorkeur ze overruled):
            \(lines)]


            """
        }

        if !temporary.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let lines = temporary.map { pref in
                "- \(pref.preferenceText) (tijdelijk, geldt tot \(formatter.string(from: pref.expirationDate!)))"
            }.joined(separator: "\n")
            output += """
            [TIJDELIJKE VOORKEUREN (overrulen vastgepinde regels gedurende hun looptijd):
            \(lines)

            KRITIEKE INSTRUCTIE: Tijdens de looptijd van een tijdelijke voorkeur gaat deze BOVEN elke vastgepinde regel waar een conflict mee is. Voorbeeld: als 'op vakantie, alleen wandelen' actief is, plan je GEEN krachttraining of fietsritten in die periode — ook niet als er een vastgepinde di/do gym-regel staat.]


            """
        }

        return output
    }
}
