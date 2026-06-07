import Foundation

/// The individual suggestion for a specific day in the coming week.
struct SuggestedWorkout: Codable, Identifiable, Equatable {
    var id: UUID = UUID()

    /// The day, e.g. "Maandag" or a specific date "2023-11-01"
    let dateOrDay: String

    /// Activity type: e.g. "Hardlopen", "Fietsen", or "Rust"
    let activityType: String

    /// Suggested duration in minutes (0 for rest)
    let suggestedDurationMinutes: Int

    /// Intended load (TRIMP), 0 for rest. Sometimes Gemini sends this as a String, or omits it.
    let targetTRIMP: Int?

    /// Short explanation, e.g. "Zone 2 herstelrit" or "Intervaltraining: 5x1000m"
    let description: String

    /// Target heart-rate zone, e.g. "Zone 2"
    let heartRateZone: String?

    /// Target pace, e.g. "5:30 min/km"
    let targetPace: String?

    /// Sprint 17.3: short explanation of why this workout is in the schedule (phase + success-criteria basis).
    /// E.g. "60 km = 50% of your cycling goal. Mandatory milestone in the Build phase."
    let reasoning: String?

    // Epic 33 Story 33.2a: Flexible planning — "Move session".
    // Optional override on the AI-suggested day. Default `nil` —
    // then `displayDate` falls back to `resolvedDate` (the string-parse route).
    // Existing AppStorage plans without this field decode without issue via
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
        // Gemini sends null for rest days — decodeIfPresent with a fallback to 0
        suggestedDurationMinutes = (try? container.decodeIfPresent(Int.self, forKey: .suggestedDurationMinutes)) ?? 0
        description = try container.decode(String.self, forKey: .description)
        heartRateZone = try container.decodeIfPresent(String.self, forKey: .heartRateZone)
        targetPace    = try container.decodeIfPresent(String.self, forKey: .targetPace)
        reasoning     = try container.decodeIfPresent(String.self, forKey: .reasoning)

        // Try to decode targetTRIMP as an Int, otherwise as a String and parse to Int
        if let intTRIMP = try? container.decodeIfPresent(Int.self, forKey: .targetTRIMP) {
            targetTRIMP = intTRIMP
        } else if let stringTRIMP = try? container.decodeIfPresent(String.self, forKey: .targetTRIMP), let parsedInt = Int(stringTRIMP) {
            targetTRIMP = parsedInt
        } else {
            targetTRIMP = nil
        }

        // Story 33.2a — backwards-compat: older persisted plans don't have these fields.
        scheduledDate = try container.decodeIfPresent(Date.self, forKey: .scheduledDate)
        isSwapped     = (try? container.decodeIfPresent(Bool.self, forKey: .isSwapped)) ?? false
    }

    // MARK: - Calendar logic

    /// Computes the next calendar day matching `dateOrDay`.
    /// Supports Dutch, English, German and Spanish day names (Epic #37 story 37.4),
    /// compound strings ("Maandag 21 apr") and ISO date strings ("2026-04-10").
    /// Today is treated as offset 0 — a day in the past gets +7 days.
    var resolvedDate: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Try to parse an ISO date
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let parsed = formatter.date(from: dateOrDay) {
            return calendar.startOfDay(for: parsed)
        }

        // Map day names → weekday number (Calendar: 1=Sunday … 7=Saturday).
        // Epic #37 story 37.4: Dutch + English + German + Spanish so the coach reply is parsed
        // correctly in every supported language. Spanish accents are listed both with and
        // without the diacritic (the model is inconsistent about "miércoles" vs "miercoles").
        let dayMap: [String: Int] = [
            "zondag": 1, "sunday": 1, "sonntag": 1, "domingo": 1,
            "maandag": 2, "monday": 2, "montag": 2, "lunes": 2,
            "dinsdag": 3, "tuesday": 3, "dienstag": 3, "martes": 3,
            "woensdag": 4, "wednesday": 4, "mittwoch": 4, "miércoles": 4, "miercoles": 4,
            "donderdag": 5, "thursday": 5, "donnerstag": 5, "jueves": 5,
            "vrijdag": 6, "friday": 6, "freitag": 6, "viernes": 6,
            "zaterdag": 7, "saturday": 7, "samstag": 7, "sonnabend": 7, "sábado": 7, "sabado": 7
        ]

        // Use only the first word so "Maandag 21 apr" is correctly recognised as "maandag".
        // Epic #37 story 37.4 fix: strip punctuation so a localized format like the German
        // "Sonntag, 7. Juni" (first word "Sonntag,") still matches "sonntag" in the map —
        // otherwise every workout failed the lookup, fell back to `today` and the whole week
        // collapsed onto a single day.
        let firstWord = (dateOrDay.lowercased().components(separatedBy: .whitespaces).first ?? dateOrDay.lowercased())
            .trimmingCharacters(in: .punctuationCharacters)
        guard let targetWeekday = dayMap[firstWord] else { return today }

        let todayWeekday = calendar.component(.weekday, from: today)
        var daysAhead = targetWeekday - todayWeekday
        if daysAhead < 0 { daysAhead += 7 }

        return calendar.date(byAdding: .day, value: daysAhead, to: today) ?? today
    }

    /// Story 33.2a: the real date the session is on. If the user has
    /// moved it (`scheduledDate != nil`) that override counts; otherwise it falls
    /// back to `resolvedDate` (string parse from the AI suggestion).
    /// Used for sorting, UI labels and the coach prompt.
    var displayDate: Date {
        if let scheduledDate {
            return Calendar.current.startOfDay(for: scheduledDate)
        }
        return resolvedDate
    }

    /// Returns the day as an explicit date, e.g. "Vrijdag 10 apr".
    /// No 'Today'/'Tomorrow' — explicit dates prevent confusion with stale data.
    /// Uses `displayDate` so moved sessions immediately show the new label.
    var displayDayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.currentLocale
        formatter.dateFormat = "EEEE d MMM"
        let label = formatter.string(from: displayDate)
        return label.prefix(1).uppercased() + label.dropFirst()
    }
}

/// Structure to receive, via JSON, a new memory including an optional expiry date.
struct ExtractedPreference: Codable, Equatable {
    let text: String
    let expirationDate: String? // Expected format: "YYYY-MM-DD"
}

/// The structured JSON output (from Gemini) for a complete weekly schedule.
struct SuggestedTrainingPlan: Codable, Equatable {
    let motivation: String
    let workouts: [SuggestedWorkout]
    let newPreferences: [ExtractedPreference]?

    // Custom init so a Gemini response with only {"motivation": "..."} does not crash.
    // Missing arrays get an empty default value instead of a decode error.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        motivation     = try c.decode(String.self, forKey: .motivation)
        workouts       = (try? c.decodeIfPresent([SuggestedWorkout].self, forKey: .workouts))       ?? []
        newPreferences = (try? c.decodeIfPresent([ExtractedPreference].self, forKey: .newPreferences)) ?? nil
    }

    init(motivation: String, workouts: [SuggestedWorkout], newPreferences: [ExtractedPreference]? = nil) {
        self.motivation     = motivation
        self.workouts       = workouts
        self.newPreferences = newPreferences
    }
}
