import Foundation

// MARK: - PlanResetPromptBuilder
//
// Builds the Gemini system instruction for Story 33.2b "Reset Schedule". Pure Swift,
// testable without ChatViewModel state.
//
// The prompt asks the coach to plan the remaining days AROUND the moved sessions —
// those are sacred. App-side, `TrainingPlanManager.mergeReplannedPlan` still filters
// out AI output that lands on reserved days (defense in depth).

enum PlanResetPromptBuilder {

    /// Builds the system prompt + associated user-facing text for the plan reset.
    /// - Parameters:
    ///   - swappedWorkouts: The manually moved workouts from the current plan.
    ///   - now: Reference date for the "from today" phrasing (injectable for tests).
    /// - Returns: Tuple of `systemText` (hidden from the user) and `userText` (visible in chat).
    static func build(swappedWorkouts: [SuggestedWorkout], now: Date = Date()) -> (systemText: String, userText: String) {
        let dateFormatter = AppDateFormatters.prompt("EEEE d MMM")
        let isoFormatter = AppDateFormatters.fixed("yyyy-MM-dd")

        let todayLabel = dateFormatter.string(from: now).capitalized
        let todayIso = isoFormatter.string(from: now)

        var lines: [String] = [
            "PLAN-RESET CONTEXT — The user has manually moved one or more sessions and now asks to re-plan the rest of the week.",
            ""
        ]

        if swappedWorkouts.isEmpty {
            // Edge case: no swaps → reset anyway; we ask for a clean 7-day plan.
            lines.append("There are no manually moved sessions. Build a clean 7-day plan from \(todayLabel) (\(todayIso)).")
        } else {
            lines.append("Sacred moved sessions (DO NOT touch — keep exactly this day, exactly this session):")
            for workout in swappedWorkouts {
                let dayLabel = dateFormatter.string(from: workout.displayDate).capitalized
                let dayIso = isoFormatter.string(from: workout.displayDate)
                let trimpStr = workout.targetTRIMP.map { " (TRIMP \($0))" } ?? ""
                lines.append("- \(dayLabel) (\(dayIso)): '\(workout.activityType)'\(trimpStr)")
            }
            lines.append("")
            lines.append("INSTRUCTION: Plan the other 6 days from \(todayLabel) (\(todayIso)). The moved sessions above must stay EXACTLY on their date with EXACTLY their activityType. Don't invent alternatives, don't shift, don't replace. Adjust your weekly volume target around these fixed sessions — you have less free space than usual.")
        }
        lines.append(contentsOf: [
            "",
            "IMPORTANT:",
            "1. Return the FULL 7-day schedule in JSON format (including the sacred sessions — copy them verbatim from the list above).",
            "2. Use ISO dates (yyyy-MM-dd) in `dateOrDay` so the mapping is unambiguous, not 'Maandag'.",
            "3. Respect the 10-15% progression rule and the current TrainingPhase target (see earlier context).",
            "4. App-side merge still filters out any session that lands on a sacred day — so rather too conservative than too creative."
        ])

        let systemText = lines.joined(separator: "\n")

        let userText: String
        if swappedWorkouts.count == 1 {
            userText = String(localized: "Herschrijf de rest van mijn week rondom de verplaatste sessie.")
        } else if swappedWorkouts.isEmpty {
            userText = String(localized: "Herschrijf mijn week vanaf vandaag.")
        } else {
            userText = String(localized: "Herschrijf de rest van mijn week rondom de \(swappedWorkouts.count) verplaatste sessies.")
        }
        return (systemText, userText)
    }
}
