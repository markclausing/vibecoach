import Foundation

/// Epic #55 story 55.3: pure-Swift formatter for the multi-day event-window block
/// injected into the coach prompt.
///
/// A multi-day event (e.g. a 5-day stage tour) is the training stimulus itself. The
/// coach must NOT plan other trainings or honour fixed preferences (gym/strength) on
/// those days, must suppress other goals' base work in the window, and must plan
/// recovery immediately AFTER the event. The event window is deterministic — it comes
/// straight from the goal's stored fields — so the app injects it rather than hoping
/// the AI infers it.
///
/// Called by `ChatViewModel.cacheEventWindow`; AppStorage-free and directly testable
/// (CLAUDE.md §6). Prompt body is English per CLAUDE.md §13.
enum EventWindowContextFormatter {

    /// Builds the `[EVENT WINDOW …]` block(s) for every multi-day event that is upcoming,
    /// ongoing, or still inside its post-event recovery tail.
    ///
    /// - Parameters:
    ///   - goals: active goals (single-day events and completed goals are filtered out).
    ///   - now: reference date (injectable for testing).
    ///   - calendar: calendar (injectable for testing).
    /// - Returns: the formatted block(s), or "" when no multi-day event is relevant.
    static func format(goals: [FitnessGoal], now: Date = Date(), calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: 14, to: today) else { return "" }

        let iso = DateFormatter()
        iso.calendar = calendar
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.dateFormat = "yyyy-MM-dd"

        let relevant = goals
            .filter { !$0.isCompleted && $0.resolvedEventDurationDays > 1 }
            // Upcoming within the planning horizon …
            .filter { calendar.startOfDay(for: $0.targetDate) <= horizon }
            // … and not fully past (event + recovery tail still ahead of today).
            .filter { goal in
                let recDays = recoveryDays(for: goal.resolvedEventDurationDays)
                guard let recoveryEnd = calendar.date(byAdding: .day, value: recDays, to: goal.eventEndDate) else { return false }
                return calendar.startOfDay(for: recoveryEnd) >= today
            }
            .sorted { $0.targetDate < $1.targetDate }

        let blocks = relevant.map { block(for: $0, iso: iso, calendar: calendar) }
        return blocks.isEmpty ? "" : blocks.joined(separator: "\n\n")
    }

    /// Post-event easy/rest days, scaled to event length: 2-day event → 1, 3 → 2, 5 → 3.
    static func recoveryDays(for durationDays: Int) -> Int {
        min(3, max(1, (durationDays + 1) / 2))
    }

    private static func block(for goal: FitnessGoal, iso: DateFormatter, calendar: Calendar) -> String {
        let n = goal.resolvedEventDurationDays
        let startStr = iso.string(from: calendar.startOfDay(for: goal.targetDate))
        let endStr = iso.string(from: goal.eventEndDate)
        let recDays = recoveryDays(for: n)
        let afterDate = calendar.date(byAdding: .day, value: 1, to: goal.eventEndDate) ?? goal.eventEndDate
        let afterStr = iso.string(from: afterDate)

        return """
        [EVENT WINDOW — '\(goal.title)': \(startStr) … \(endStr) (\(n) consecutive event days) — THESE DAYS ARE THE EVENT ITSELF:
        This is a multi-day stage event, NOT a race. The athlete completes a stage on each of these \(n) days; the event IS the training stimulus.

        ABSOLUTE RULES FOR THESE DATES:
        1. PLAN NO OTHER TRAINING on \(startStr)…\(endStr) — no strength/gym, no separate runs or rides, no sessions for any OTHER goal. The stage of that day is the only entry.
        2. IGNORE FIXED PREFERENCES inside this window — recurring 'gym day' / 'strength session' preferences are SUSPENDED for these dates; do not schedule or mention them.
        3. CROSS-GOAL SUPPRESSION — base/endurance work for other active goals also yields; never stack it onto an event day.

        AFTER THE EVENT (from \(afterStr)):
        4. PLAN RECOVERY FIRST. The athlete will be fatigued after \(n) consecutive event days. Schedule \(recDays) easy recovery day(s) (rest or Zone 1, ≤45 min) immediately after the event before any intensity. Briefly acknowledge the completed event before proposing the next block.]
        """
    }
}
