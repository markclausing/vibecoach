import Foundation

// MARK: - PreferencesContextFormatter
//
// Bouwt het preferences-blok in de Gemini system context. Splitst tijdelijke voorkeuren
// (met `expirationDate`) van vastgepinde voorkeuren (zonder `expirationDate`) en geeft
// de coach een expliciete prioriteit-regel: tijdelijke voorkeuren overrulen vastgepinde
// regels gedurende hun looptijd.
//
// Aanleiding: een gebruiker meldde dat de coach na een vakantie-mention ("Rome, alleen
// wandelen") in eerste instantie correct het schema aanpaste, maar bij een schema-refresh
// de vastgepinde "krachttraining elke di/do"-regel weer naar binnen liet sluipen — geen
// onderscheid tussen tijdelijk en permanent in de oude prompt-injectie.

enum PreferencesContextFormatter {

    /// Bouwt het preferences-blok voor de coach-context. Retourneert een lege string als
    /// er geen actieve voorkeuren zijn (zodat de prompt schoon blijft).
    /// - Parameters:
    ///   - activePreferences: alle preferences met `isActive == true` uit SwiftData.
    ///   - now: huidige tijd (injecteerbaar voor tests).
    static func format(activePreferences: [UserPreference], now: Date = Date()) -> String {
        // Filter verlopen tijdelijke voorkeuren — `expirationDate <= now` betekent verstreken.
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
