import Foundation

/// Pure-Swift formatter voor het symptomen-/blessure-context-blok (Epic 18 Sprint 2).
///
/// `SymptomTracker` is de 'Single Source of Truth' voor blessure-status:
/// - Score > 0 → actieve klacht, met hard-constraints op basis van ernst
/// - Score == 0 → hersteld, vervangt elke nog actieve `UserPreference`-tekst
/// - Geen score ingevuld + actieve `UserPreference` → toon als 'onbekend, score nog niet ingevuld'
///
/// Wordt aangeroepen door `ChatViewModel.cacheSymptomContext` en in tests direct testbaar
/// zonder `@AppStorage` of `UserDefaults`-fixture.
enum SymptomContextFormatter {

    /// Formatteert symptomen + blessure-voorkeuren naar een context-string voor de AI-coach.
    /// - Parameters:
    ///   - symptoms: Alle `Symptom`-records (de formatter filtert zelf op vandaag).
    ///   - preferences: Actieve `UserPreference`-records (verlopen prefs worden uitgefilterd).
    ///   - now: Datum voor het bepalen van "vandaag" en "actieve" prefs (default `Date()`).
    /// - Returns: De geformatteerde context-string. Lege string als er niets te rapporteren is.
    static func format(symptoms: [Symptom],
                       preferences: [UserPreference] = [],
                       now: Date = Date()) -> String {
        let todayStart = Calendar.current.startOfDay(for: now)
        // Haal ALLE records van vandaag op — inclusief score 0 (= hersteld)
        let todayAll    = symptoms.filter { $0.date >= todayStart }
        let todayActive = todayAll.filter { $0.severity > 0 }

        // Bepaal actieve blessure-voorkeuren (niet verlopen)
        let injuryKeywords = ["kuit", "scheen", "shin", "rug", "rugpijn", "knie", "enkel",
                              "blessure", "pijn", "klacht", "hand", "pols", "schouder"]
        let activeInjuryPrefs = preferences.filter { pref in
            guard pref.expirationDate == nil || pref.expirationDate! > now else { return false }
            let text = pref.preferenceText.lowercased()
            return injuryKeywords.contains(where: { text.contains($0) })
        }

        // Alle gebieden die VANDAAG gemeten zijn (score 0 én > 0) tellen als 'tracked'
        let allTrackedAreas = Set(todayAll.map { $0.bodyArea.rawValue.lowercased() })

        // Niets te rapporteren: geen meting van vandaag en geen actieve klacht-voorkeur
        guard !todayAll.isEmpty || !activeInjuryPrefs.isEmpty else {
            return ""
        }

        var scoreLines:    [String] = []
        var constraintLines:[String] = []
        var recoveryLines: [String] = []

        // 1. Actieve klachten (score > 0) — met hard constraints op basis van ernst
        for s in todayActive {
            let label = BodyArea.severityLabel(s.severity)
            scoreLines.append("• \(s.bodyArea.rawValue): \(s.severity)/10 (\(label))")

            if s.severity > 5 {
                switch s.bodyArea {
                case .calf:
                    constraintLines.append("🚫 HARD CONSTRAINT Kuit (\(s.severity)/10 > 5): HARDLOPEN IS STRIKT VERBODEN. Fietsen en zwemmen zijn toegestaan.")
                case .ankle:
                    constraintLines.append("🚫 HARD CONSTRAINT Enkel (\(s.severity)/10 > 5): HARDLOPEN IS STRIKT VERBODEN. Fietsen is veilig.")
                case .back:
                    constraintLines.append("🚫 HARD CONSTRAINT Rug (\(s.severity)/10 > 5): geen hardlopen of krachttraining. Fietsen (rechtop) en zwemmen zijn veilig.")
                case .knee:
                    constraintLines.append("🚫 HARD CONSTRAINT Knie (\(s.severity)/10 > 5): geen hardlopen of springen. Fietsen en zwemmen zijn veilig.")
                case .hand:
                    constraintLines.append("🚫 HARD CONSTRAINT Hand (\(s.severity)/10 > 5): geen krachttraining of gewichtdragende oefeningen.")
                case .shoulder:
                    constraintLines.append("🚫 HARD CONSTRAINT Schouder (\(s.severity)/10 > 5): geen zwemmen of push-oefeningen.")
                }
            } else if s.severity > 0 && s.severity < 3 {
                if s.bodyArea == .calf || s.bodyArea == .ankle {
                    scoreLines.append("  ↳ Score < 3: voorzichtige hardloop-alternatieven bespreekbaar (kort, Zone 1, max 30 min).")
                }
            }
        }

        // 2. Herstelde gebieden (score == 0 vandaag) — alleen als er een matchende blessure-voorkeur
        //    bestaat. Zo voorkomt we valse herstelberichten voor lichaamsdelen die nooit geblesseerd waren.
        for s in todayAll where s.severity == 0 {
            let matchesPref = activeInjuryPrefs.contains { pref in
                s.bodyArea.injuryKeywords.contains(where: { pref.preferenceText.lowercased().contains($0) })
            }
            guard matchesPref else { continue }
            let areaName = s.bodyArea.rawValue
            recoveryLines.append(
                "✅ HERSTELD (\(areaName): 0/10): De gebruiker is vandaag klachtenvrij voor \(areaName). " +
                "INSTRUCTIE: Vier dit expliciet in je Insight ('Wat goed dat je \(areaName.lowercased())pijn op 0 staat!'). " +
                "Normale belasting mag weer worden voorgesteld, maar adviseer een voorzichtige, stapsgewijze opbouw."
            )
        }

        // 3. Blessure-voorkeuren zonder score van vandaag — alleen tonen als het gebied NIET al
        //    gemeten is (voorkomt duplicaten met scoreLines of recoveryLines)
        for pref in activeInjuryPrefs {
            let alreadyTracked = BodyArea.allCases.contains { area in
                allTrackedAreas.contains(area.rawValue.lowercased()) &&
                area.injuryKeywords.contains(where: { pref.preferenceText.lowercased().contains($0) })
            }
            if !alreadyTracked {
                scoreLines.append("• \(pref.preferenceText) (score nog niet ingevuld vandaag — gebruik voorzichtigheid)")
            }
        }

        // Combineer in vaste volgorde: scores → hard constraints → herstelberichten
        var combined = scoreLines
        if !constraintLines.isEmpty {
            combined += ["", "ACTIEVE BEPERKINGEN:"] + constraintLines
        }
        if !recoveryLines.isEmpty {
            combined += ["", "HERSTEL MELDINGEN:"] + recoveryLines
        }

        // Lege context als er uitsluitend score-0 records zijn zonder matchende preference
        // (bijv. een willekeurig lichaamsdeel op 0 ingevuld zonder eerdere klacht)
        if combined.isEmpty {
            return ""
        }

        return combined.joined(separator: "\n")
    }
}
