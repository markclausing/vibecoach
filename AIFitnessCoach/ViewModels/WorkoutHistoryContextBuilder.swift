import Foundation

// MARK: - Epic 45 Story 45.1: WorkoutHistoryContextBuilder
//
// Pure-Swift helper that turns a list of pre-fetched workout entries into a
// 1-line-per-workout prompt block for the coach (`[RECENT TRAINING — 14 DAYS]`).
// Like `LastWorkoutContextFormatter` and `WorkoutPatternFormatter`: no AppStorage,
// no SwiftData, no HealthKit. The caller (DashboardView) does the async sample fetch
// and passes `WorkoutEntry` DTOs — the builder itself is synchronous and testable.
//
// The builder produces only the data lines. The [RECENT TRAINING — 14 DAYS…]
// header and behaviour rules are wrapped around the output in
// `ChatViewModel.buildContextPrefix` — same split as with
// `WorkoutPatternFormatter.chatContextLine`, so prompt-engineering choices stay
// centralized in `ChatViewModel`.

enum WorkoutHistoryContextBuilder {

    /// One workout row with all its pre-fetched data. The caller builds these structs
    /// after samples per workout UUID have been fetched — the builder does no I/O.
    struct WorkoutEntry {
        let startDate: Date
        let displayName: String
        let sportCategory: SportCategory
        let sessionType: SessionType?
        let movingTime: Int            // seconds
        let trimp: Double?
        let averageHeartrate: Double?
        let averagePower: Double?      // Watts, optional — the caller passes nil for now;
                                       // hooking up Strava power from Epic #40 is a
                                       // 1-line addition without an API change.
        let patterns: [WorkoutPattern] // detector output, can be empty
    }

    /// Builds the body of the [RECENT TRAINING — 14 DAYS] block. One line per
    /// workout, sorted newest→oldest (chat reading order: "what now" → "trend").
    /// Empty array → `""` so the caller can skip the whole block.
    static func build(entries: [WorkoutEntry]) -> String {
        guard !entries.isEmpty else { return "" }

        let sorted = entries.sorted { $0.startDate > $1.startDate }
        let lines = sorted.map { line(for: $0) }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    /// Builds one compact line per the format defined in §2 of the Epic-45 plan:
    /// `- 30 apr · Hardlopen · Drempel · 52 min · TRIMP 78 · gem-HR 162 · gem-W 215 — [SIGNIFICANT] cardiac_drift: 8.2% …`
    /// Optional segments (sessionType, TRIMP, HR, power, patterns) are fully omitted
    /// when the source value is nil/empty — no "Onbepaald" or "TRIMP onbekend".
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

    /// NL-locale short date label (e.g. "30 apr"). `dd MMM` keeps the line short
    /// and is unambiguous within a 14-day window.
    private static func dateLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "dd MMM"
        return formatter.string(from: date)
    }
}
