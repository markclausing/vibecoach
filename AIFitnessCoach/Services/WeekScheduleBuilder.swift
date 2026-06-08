import Foundation

// MARK: - Epic #55 story 55.2: app-side synthesized stage entries
//
// A multi-day event (e.g. "Arnhem → Karlsruhe in 5 days") is modelled with a single
// `FitnessGoal` whose `targetDate` is the START day and `eventDurationDays` the number
// of consecutive event days. The week schedule must show those days as the event itself
// ("Etappe X/N — <title>") rather than coach trainings — and suppress any planned
// workout that happens to fall on an event day.
//
// We synthesize these entries app-side instead of relying on the AI: the event window is
// deterministic (it comes straight from the goal's stored fields), so the app is the
// reliable source of truth. The prompt-level cross-goal suppression is story 55.3.
//
// Pure-Swift + AppStorage-free (CLAUDE.md §6): the caller injects the week days, the plan
// workouts and the active goals, so this is trivially unit-testable.

/// A single synthesized event-day entry in the week schedule.
struct EventStageEntry: Equatable {
    let date: Date
    /// 1-based stage number within the event (day 1 = `targetDate`).
    let stageIndex: Int
    /// Total number of stages (= the event's `resolvedEventDurationDays`).
    let totalStages: Int
    let goalTitle: String
}

/// What a given week day renders as: either a coach-planned workout or a synthesized
/// multi-day event stage. Stage entries take precedence over workouts on the same day.
enum WeekDayEntry: Equatable {
    case workout(SuggestedWorkout)
    case stage(EventStageEntry)

    /// The workout payload, or `nil` for stage days. Lets call sites that only care about
    /// trainings (icons, rest detection) keep their existing logic.
    var workout: SuggestedWorkout? {
        if case let .workout(w) = self { return w }
        return nil
    }

    /// The stage payload, or `nil` for ordinary workout days.
    var stage: EventStageEntry? {
        if case let .stage(s) = self { return s }
        return nil
    }
}

enum WeekScheduleBuilder {

    /// Builds the per-day entry list for the displayed week.
    ///
    /// For each day, in priority order:
    /// 1. If a multi-day event goal covers the day → a synthesized `.stage` entry
    ///    (replaces any coach training that day — visual cross-goal suppression).
    /// 2. Else if a plan workout matches the day (by `displayDate`) → a `.workout` entry.
    /// 3. Else the day is omitted (rest day / nothing planned), matching the prior behaviour.
    ///
    /// Only events with `resolvedEventDurationDays > 1` are treated as multi-day stages;
    /// a single-day race (`isEventDay(targetDate) == true` but duration 1) is left to the
    /// normal workout/rest rendering.
    static func entries(
        for days: [Date],
        workouts: [SuggestedWorkout],
        eventGoals: [FitnessGoal],
        calendar: Calendar = .current
    ) -> [(date: Date, entry: WeekDayEntry)] {
        // Multi-day events only, earliest first so overlapping events resolve deterministically.
        let multiDayGoals = eventGoals
            .filter { !$0.isCompleted && $0.resolvedEventDurationDays > 1 }
            .sorted { $0.targetDate < $1.targetDate }

        return days.compactMap { date in
            if let goal = multiDayGoals.first(where: { $0.isEventDay(date) }),
               let stageIndex = goal.eventStageIndex(for: date) {
                let stage = EventStageEntry(
                    date: date,
                    stageIndex: stageIndex,
                    totalStages: goal.resolvedEventDurationDays,
                    goalTitle: goal.title
                )
                return (date, .stage(stage))
            }

            if let workout = workouts.first(where: {
                calendar.isDate($0.displayDate, inSameDayAs: date)
            }) {
                return (date, .workout(workout))
            }

            return nil
        }
    }
}
