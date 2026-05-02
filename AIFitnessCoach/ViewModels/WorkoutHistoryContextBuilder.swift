import Foundation

// MARK: - Epic 45 Story 45.1: WorkoutHistoryContextBuilder
//
// Pure-Swift helper die een lijst pre-fetched workout-entries omzet in een
// 1-regel-per-workout prompt-blok voor de coach (`[RECENTE TRAINING — 14 DAGEN]`).
// Zoals `LastWorkoutContextFormatter` en `WorkoutPatternFormatter`: geen AppStorage,
// geen SwiftData, geen HealthKit. Caller (DashboardView) doet de async sample-fetch
// en geeft `WorkoutEntry`-DTO's mee — de builder zelf is synchroon en testbaar.
//
// De builder produceert alleen de data-regels. De [RECENTE TRAINING — 14 DAGEN…]-
// header en gedragsregels worden in `ChatViewModel.buildContextPrefix` om de output
// heen gewikkeld — zelfde split als bij `WorkoutPatternFormatter.chatContextLine`,
// zodat prompt-engineering-keuzes centraal in `ChatViewModel` blijven.

enum WorkoutHistoryContextBuilder {

    /// Eén workout-rij met al zijn pre-fetched data. Caller bouwt deze structs
    /// op nadat samples per workout-UUID zijn opgehaald — de builder doet geen I/O.
    struct WorkoutEntry {
        let startDate: Date
        let displayName: String
        let sportCategory: SportCategory
        let sessionType: SessionType?
        let movingTime: Int            // seconden
        let trimp: Double?
        let averageHeartrate: Double?
        let averagePower: Double?      // Watts, optioneel — caller geeft nu nil door;
                                       // aansluiting op Strava-power uit Epic #40 is
                                       // een 1-regel-aanvulling zonder API-wijziging.
        let patterns: [WorkoutPattern] // detector-output, kan leeg zijn
    }

    /// Bouwt de body van het [RECENTE TRAINING — 14 DAGEN]-blok. Eén regel per
    /// workout, sortering nieuwste→oudste (chat-leesvolgorde: "wat nu" → "trend").
    /// Lege array → `""` zodat de caller het hele blok kan skippen.
    static func build(entries: [WorkoutEntry]) -> String {
        guard !entries.isEmpty else { return "" }

        let sorted = entries.sorted { $0.startDate > $1.startDate }
        let lines = sorted.map { line(for: $0) }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    /// Bouwt één compacte regel volgens het in §2 van de Epic-45-plan vastgelegde format:
    /// `- 30 apr · Hardlopen · Drempel · 52 min · TRIMP 78 · gem-HR 162 · gem-W 215 — [SIGNIFICANT] cardiac_drift: 8.2% …`
    /// Optionele segmenten (sessieType, TRIMP, HR, power, patronen) worden volledig weggelaten
    /// als de bron-waarde nil/leeg is — geen "Onbepaald" of "TRIMP onbekend".
    private static func line(for entry: WorkoutEntry) -> String {
        var segments: [String] = []
        segments.append(dateLabel(for: entry.startDate))
        segments.append(entry.sportCategory.displayName)

        if let session = entry.sessionType {
            segments.append(session.displayName)
        }

        let minutes = max(0, entry.movingTime / 60)
        segments.append("\(minutes) min")

        if let trimp = entry.trimp {
            segments.append("TRIMP \(Int(trimp.rounded()))")
        }

        if let hr = entry.averageHeartrate {
            segments.append("gem-HR \(Int(hr.rounded()))")
        }

        if let power = entry.averagePower {
            segments.append("gem-W \(Int(power.rounded()))")
        }

        var line = "- " + segments.joined(separator: " · ")

        if let patternSnippet = WorkoutPatternFormatter.inlineSnippet(for: entry.patterns) {
            line += " — " + patternSnippet
        }

        return line
    }

    /// NL-locale korte datum-label (bijv. "30 apr"). `dd MMM` houdt de regel kort
    /// en is ondubbelzinnig binnen een 14-daagse window.
    private static func dateLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "dd MMM"
        return formatter.string(from: date)
    }
}
