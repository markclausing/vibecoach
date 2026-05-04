import Foundation

/// De individuele suggestie voor een specifieke dag in de komende week.
struct SuggestedWorkout: Codable, Identifiable, Equatable {
    var id: UUID = UUID()

    /// De dag, bijv. "Maandag" of een specifieke datum "2023-11-01"
    let dateOrDay: String

    /// Type activiteit: e.g. "Hardlopen", "Fietsen", of "Rust"
    let activityType: String

    /// Voorgestelde duur in minuten (0 voor rust)
    let suggestedDurationMinutes: Int

    /// Beoogde belasting (TRIMP), 0 voor rust. Soms stuurt Gemini dit als String, of laat hij het weg.
    let targetTRIMP: Int?

    /// Korte toelichting, bijv. "Zone 2 herstelrit" of "Intervaltraining: 5x1000m"
    let description: String

    /// Doel hartslagzone, bijv. "Zone 2"
    let heartRateZone: String?

    /// Doel tempo, bijv. "5:30 min/km"
    let targetPace: String?

    /// Sprint 17.3: Korte uitleg waarom deze training in het schema staat (fase + succescriteria basis).
    /// Bijv: "60 km = 50% van je fietsdoel. Verplichte mijlpaal in de Build-fase."
    let reasoning: String?

    // Epic 33 Story 33.2a: Flexibele Planning — "Verplaats sessie".
    // Optionele override op de door de AI gesuggereerde dag. Default `nil` —
    // dan valt `displayDate` terug op `resolvedDate` (de string-parse-route).
    // Bestaande AppStorage-plans zonder dit veld decoderen probleemloos via
    // `decodeIfPresent` in `init(from:)`.
    var scheduledDate: Date?
    var isSwapped: Bool

    enum CodingKeys: String, CodingKey {
        case dateOrDay
        case activityType
        case suggestedDurationMinutes
        case targetTRIMP
        case description
        case heartRateZone
        case targetPace
        case reasoning
        case scheduledDate
        case isSwapped
    }

    init(id: UUID = UUID(),
         dateOrDay: String,
         activityType: String,
         suggestedDurationMinutes: Int,
         targetTRIMP: Int?,
         description: String,
         heartRateZone: String? = nil,
         targetPace: String? = nil,
         reasoning: String? = nil,
         scheduledDate: Date? = nil,
         isSwapped: Bool = false) {
        self.id = id
        self.dateOrDay = dateOrDay
        self.activityType = activityType
        self.suggestedDurationMinutes = suggestedDurationMinutes
        self.targetTRIMP = targetTRIMP
        self.description = description
        self.heartRateZone = heartRateZone
        self.targetPace = targetPace
        self.reasoning = reasoning
        self.scheduledDate = scheduledDate
        self.isSwapped = isSwapped
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dateOrDay = try container.decode(String.self, forKey: .dateOrDay)
        activityType = try container.decode(String.self, forKey: .activityType)
        // Gemini stuurt null voor rustdagen — decodeIfPresent met fallback naar 0
        suggestedDurationMinutes = (try? container.decodeIfPresent(Int.self, forKey: .suggestedDurationMinutes)) ?? 0
        description = try container.decode(String.self, forKey: .description)
        heartRateZone = try container.decodeIfPresent(String.self, forKey: .heartRateZone)
        targetPace    = try container.decodeIfPresent(String.self, forKey: .targetPace)
        reasoning     = try container.decodeIfPresent(String.self, forKey: .reasoning)

        // Probeer targetTRIMP te decoderen als Int, en anders als String en parse naar Int
        if let intTRIMP = try? container.decodeIfPresent(Int.self, forKey: .targetTRIMP) {
            targetTRIMP = intTRIMP
        } else if let stringTRIMP = try? container.decodeIfPresent(String.self, forKey: .targetTRIMP), let parsedInt = Int(stringTRIMP) {
            targetTRIMP = parsedInt
        } else {
            targetTRIMP = nil
        }

        // Story 33.2a — backwards-compat: oudere persisted plans hebben deze velden niet.
        scheduledDate = try container.decodeIfPresent(Date.self, forKey: .scheduledDate)
        isSwapped     = (try? container.decodeIfPresent(Bool.self, forKey: .isSwapped)) ?? false
    }

    // MARK: - Kalenderlogica

    /// Berekent de eerstvolgende kalenderdag die overeenkomt met `dateOrDay`.
    /// Ondersteunt Nederlandse dagnamen ("Maandag"…"Zondag"), Engelse dagnamen ("Monday"…"Sunday"),
    /// samengestelde strings ("Maandag 21 apr") en ISO-datumstrings ("2026-04-10").
    /// Vandaag wordt als offset 0 beschouwd — een dag in het verleden krijgt +7 dagen.
    var resolvedDate: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Probeer ISO-datum te parsen
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let parsed = formatter.date(from: dateOrDay) {
            return calendar.startOfDay(for: parsed)
        }

        // Map dagnamen → weekday-getal (Calendar: 1=zondag … 7=zaterdag)
        // Ondersteunt Nederlands én Engels zodat ook Gemini-fallback-responses correct worden verwerkt.
        let dayMap: [String: Int] = [
            "zondag": 1, "sunday": 1,
            "maandag": 2, "monday": 2,
            "dinsdag": 3, "tuesday": 3,
            "woensdag": 4, "wednesday": 4,
            "donderdag": 5, "thursday": 5,
            "vrijdag": 6, "friday": 6,
            "zaterdag": 7, "saturday": 7
        ]

        // Gebruik alleen het eerste woord zodat "Maandag 21 apr" correct als "maandag" wordt herkend.
        let firstWord = dateOrDay.lowercased().components(separatedBy: .whitespaces).first ?? dateOrDay.lowercased()
        guard let targetWeekday = dayMap[firstWord] else { return today }

        let todayWeekday = calendar.component(.weekday, from: today)
        var daysAhead = targetWeekday - todayWeekday
        if daysAhead < 0 { daysAhead += 7 }

        return calendar.date(byAdding: .day, value: daysAhead, to: today) ?? today
    }

    /// Story 33.2a: de echte datum waarop de sessie staat. Indien de gebruiker hem
    /// heeft verplaatst (`scheduledDate != nil`) telt die override; anders valt-ie
    /// terug op `resolvedDate` (string-parse uit de AI-suggestie).
    /// Wordt gebruikt voor sortering, UI-labels én voor de coach-prompt.
    var displayDate: Date {
        if let scheduledDate {
            return Calendar.current.startOfDay(for: scheduledDate)
        }
        return resolvedDate
    }

    /// Geeft de dag als expliciete datum terug, bijv. "Vrijdag 10 apr".
    /// Geen 'Vandaag'/'Morgen' — expliciete datums voorkomen verwarring bij stale data.
    /// Gebruikt `displayDate` zodat verplaatste sessies meteen het nieuwe label tonen.
    var displayDayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "EEEE d MMM"
        let label = formatter.string(from: displayDate)
        return label.prefix(1).uppercased() + label.dropFirst()
    }
}

/// Structuur om via JSON een nieuw geheugen inclusief optionele verloopdatum te ontvangen.
struct ExtractedPreference: Codable, Equatable {
    let text: String
    let expirationDate: String? // Verwacht formaat: "YYYY-MM-DD"
}

/// De gestructureerde JSON-output (vanuit Gemini) voor een compleet weekschema.
struct SuggestedTrainingPlan: Codable, Equatable {
    let motivation: String
    let workouts: [SuggestedWorkout]
    let newPreferences: [ExtractedPreference]?

    // Custom init zodat een Gemini-response met alleen {"motivation": "..."} niet crasht.
    // Ontbrekende arrays krijgen een lege standaardwaarde in plaats van een decode-fout.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        motivation     = try c.decode(String.self, forKey: .motivation)
        workouts       = (try? c.decodeIfPresent([SuggestedWorkout].self,     forKey: .workouts))       ?? []
        newPreferences = (try? c.decodeIfPresent([ExtractedPreference].self,  forKey: .newPreferences)) ?? nil
    }

    init(motivation: String, workouts: [SuggestedWorkout], newPreferences: [ExtractedPreference]? = nil) {
        self.motivation     = motivation
        self.workouts       = workouts
        self.newPreferences = newPreferences
    }
}
