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
        var distanceMeters: Double = 0
        /// Set by `tagRaces` when this workout was the athlete's goal race.
        var race: RaceGoal?
    }

    /// A goal race that may fall inside the 14-day window. A DTO rather than `FitnessGoal`
    /// so the builder stays free of SwiftData.
    struct RaceGoal: Equatable {
        let title: String
        let date: Date
        let sport: SportCategory?
        let priority: RacePriority?
        var eventDays: Int = 1
    }

    /// Marks the workout(s) that were a goal race. Without this the coach only sees an
    /// anonymous "Hardlopen · 112 min" line and talks about whatever training run was longest
    /// — a 30 km long run the week before a half marathon buried the race itself.
    ///
    /// Per event day the longest matching workout (by distance, then duration) is the race;
    /// warm-ups and cool-downs on the same day are left untagged. Goals in the future match
    /// nothing because no workout exists for them yet.
    static func tagRaces(in entries: [WorkoutEntry],
                         goals: [RaceGoal],
                         calendar: Calendar = .current) -> [WorkoutEntry] {
        var tagged = entries
        for goal in goals {
            let firstDay = calendar.startOfDay(for: goal.date)
            for dayOffset in 0..<max(1, goal.eventDays) {
                guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: firstDay),
                      let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
                let candidates = tagged.indices.filter { index in
                    let entry = tagged[index]
                    guard entry.race == nil, entry.startDate >= dayStart, entry.startDate < dayEnd else { return false }
                    return goal.sport.map { $0 == entry.sportCategory } ?? true
                }
                let raceIndex = candidates.max { lhs, rhs in
                    let left = tagged[lhs], right = tagged[rhs]
                    if left.distanceMeters != right.distanceMeters { return left.distanceMeters < right.distanceMeters }
                    return left.movingTime < right.movingTime
                }
                if let raceIndex { tagged[raceIndex].race = goal }
            }
        }
        return tagged
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

    /// Structural prompt marker for a race line — pinned against the behaviour rule in
    /// `CoachPromptAssembler.buildContextPrefix` (§13: both sides must stay identical).
    static let raceMarker = "🏁 RACE:"

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

        if entry.distanceMeters > 0 {
            segments.append(String(format: "%.1f km", entry.distanceMeters / 1000))
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

        if let race = entry.race {
            let priority = race.priority.map { " (\($0.rawValue)-race)" } ?? ""
            line = "- \(raceMarker) '\(race.title)'\(priority) — " + line.dropFirst(2)
        }

        if let patternSnippet = WorkoutPatternFormatter.inlineSnippet(for: entry.patterns) {
            line += " — " + patternSnippet
        }

        return line
    }

    /// NL-locale short date label (e.g. "30 apr"). `dd MMM` keeps the line short
    /// and is unambiguous within a 14-day window.
    private static func dateLabel(for date: Date) -> String {
        let formatter = AppDateFormatters.prompt("dd MMM")
        return formatter.string(from: date)
    }
}
