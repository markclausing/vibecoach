import Foundation

extension CoachPromptAssembler {

    /// Risk data per goal, used to build a recovery-plan prompt. Value type with no view
    /// dependency (Sprint 13.3). `ChatViewModel.GoalRiskInfo` is a typealias to this.
    struct GoalRiskInfo {
        let title: String
        let currentWeeklyRate: Double
        let requiredWeeklyRate: Double
        let weeksRemaining: Double
    }

    /// One completed workout day, mapped from HealthKit/Strava, for the status prompt.
    struct DailyWorkout {
        let date: Date
        let name: String
        let durationMinutes: Int
        let trimp: Int
    }

    // MARK: - Stored plan

    /// Formats the currently stored plan as a string, so the AI can use it as reference
    /// material for post-workout evaluations.
    static func storedPlanString(from planData: Data) -> String {
        guard let decodedPlan = try? JSONDecoder().decode(SuggestedTrainingPlan.self, from: planData) else {
            return "No current planned schedule known."
        }

        var planString = "This is my currently planned schedule (always compare your advice against it):\n"
        for workout in decodedPlan.workouts {
            planString += "- \(workout.dateOrDay): \(workout.activityType) "
            if workout.suggestedDurationMinutes > 0 {
                planString += "(\(workout.suggestedDurationMinutes) min)"
            }
            if let trimp = workout.targetTRIMP {
                planString += " [Target TRIMP: \(trimp)]"
            }
            planString += "\n"
        }
        return planString
    }

    // MARK: - Current status prompt

    /// Generates a text prompt for the AI based on the physiological data from HealthKit/Strava.
    static func currentStatusPrompt(
        workouts: [DailyWorkout],
        days: Int,
        activeGoals: [FitnessGoal],
        storedPlanData: Data,
        now: Date = Date()
    ) -> String {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        let storedPlanContext = storedPlanString(from: storedPlanData)

        var lines: [String] = [storedPlanContext, "\nThese are my most recent completed workouts (including rest days):"]

        // Inject Goals explicitly
        let uncompletedGoals = activeGoals.filter { !$0.isCompleted }
        if uncompletedGoals.isEmpty {
            lines.append("- My saved goals: No specific goals.")
        } else {
            let goalsString = uncompletedGoals.map { goal in
                let formatter = AppDateFormatters.promptStyle(.medium)
                let dateStr = formatter.string(from: goal.targetDate)
                let sport = goal.sportCategory?.displayName ?? "Sport"
                return "\(goal.title) (\(sport)) for \(dateStr)"
            }.joined(separator: ", ")
            lines.append("- My saved goals: \(goalsString)")
        }

        lines.append("- My load (past \(days) days):")
        var totalTrimp = 0

        var workoutsByDay: [Int: [DailyWorkout]] = [:]

        for workout in workouts {
            let startOfWorkoutDay = calendar.startOfDay(for: workout.date)
            let components = calendar.dateComponents([.day], from: startOfWorkoutDay, to: startOfToday)
            let dayOffset = components.day ?? 0

            if dayOffset < days && dayOffset >= 0 {
                if workoutsByDay[dayOffset] == nil {
                    workoutsByDay[dayOffset] = []
                }
                workoutsByDay[dayOffset]?.append(workout)
                totalTrimp += workout.trimp
            }
        }

        var emptyDaysStreak: [Int] = []

        for dayOffset in 0..<days {
            let displayDay = days - dayOffset

            if let dailyWorkouts = workoutsByDay[dayOffset], !dailyWorkouts.isEmpty {
                if !emptyDaysStreak.isEmpty {
                    if emptyDaysStreak.count == 1 {
                        lines.append("- Day \(emptyDaysStreak[0]): Rest")
                    } else {
                        // swiftlint:disable:next force_unwrapping
                        lines.append("- Day \(emptyDaysStreak.first!) to \(emptyDaysStreak.last!): Rest") // else-branch: count >= 2, so first/last are non-nil
                    }
                    emptyDaysStreak.removeAll()
                }

                var dayName = "Day \(displayDay)"
                if dayOffset == 0 {
                    dayName += " (Today)"
                } else if dayOffset == 1 {
                    dayName += " (Yesterday)"
                }

                for workout in dailyWorkouts {
                    // L-1: the workout name is external free text (Strava/HK) — sanitize
                    // before it enters the prompt (prompt-injection defense-in-depth).
                    let safeName = PromptInputSanitizer.sanitizeExternalText(workout.name)
                    lines.append("- \(dayName): \(workout.durationMinutes) min \(safeName) (TRIMP: \(workout.trimp))")
                }
            } else {
                emptyDaysStreak.append(displayDay)
            }
        }

        if !emptyDaysStreak.isEmpty {
            if emptyDaysStreak.count == 1 {
                lines.append("- Day \(emptyDaysStreak[0]): Rest")
            } else {
                // swiftlint:disable:next force_unwrapping
                lines.append("- Day \(emptyDaysStreak.first!) to \(emptyDaysStreak.last!): Rest") // else-branch: count >= 2, so first/last are non-nil
            }
        }

        lines.append("Total Cumulative TRIMP: \(totalTrimp)")

        lines.append("\nInstruction for the Coach:")

        let dateString = now.formatted(date: .complete, time: .omitted)
        lines.append("NOTE: Today is \(dateString). The new 7-day schedule MUST start from today. Remove days in the past and fill out the week.")
        lines.append("CRITICAL: ALWAYS sort the workouts in the JSON array chronologically — day 1 (today) first, day 7 (6 days out) last. Never reversed, never random.")
        lines.append("Compare these recent activities with the current schedule above. Is the remaining schedule for this week still optimal and realistic? If not, recompute the schedule (always return all 7 days) and give a short motivation or feedback on my recent workouts.")

        return lines.joined(separator: "\n")
    }

    // MARK: - Recovery-plan action prompt

    /// Builds the (invisible) technical prompt asking the AI for a concrete recovery plan
    /// for goals that are behind schedule. Injects the recovery status (`vibeContext`) so
    /// the plan respects the current recovery state.
    static func recoveryPlanSystemPrompt(atRiskGoals: [GoalRiskInfo], vibeContext: String) -> String {
        var systemLines = [
            "RECOVERY CONTEXT — My goal(s) are behind schedule. Create a gradual recovery plan:",
            ""
        ]

        // Epic 14.4: Inject the Vibe Score so the recovery plan respects the current recovery status
        if vibeContext == VibeScoreContextFormatter.noVibeDataSentinel {
            systemLines.append("RECOVERY STATUS TODAY: No Watch data available. Base the recovery plan on the Symptom Tracker scores and the user's own feeling.")
            systemLines.append("")
        } else if !vibeContext.isEmpty {
            systemLines.append("RECOVERY STATUS TODAY: \(vibeContext) Adjust the intensity of the recovery plan STRICTLY to this score (see system instruction).")
            systemLines.append("")
        }
        for risk in atRiskGoals {
            let deficit = Int(risk.requiredWeeklyRate - risk.currentWeeklyRate)
            let weeksText = String(format: "%.1f", risk.weeksRemaining)
            let currentRate = Int(risk.currentWeeklyRate)

            // Determine the horizon strategy based on weeks remaining
            let horizonAdvice: String
            if risk.weeksRemaining > 8 {
                // Plenty of time left: give Base Building advice, spread the deficit gradually
                let gradualWeeklyIncrease = Int(Double(deficit) / max(risk.weeksRemaining * 0.5, 1))
                horizonAdvice = "The event is \(weeksText) weeks away. PRIORITY: Base Building. Increase the weekly volume very gradually — aim for +\(gradualWeeklyIncrease) TRIMP/week over the coming months. No panic workouts."
            } else if risk.weeksRemaining > 4 {
                horizonAdvice = "The event is \(weeksText) weeks away. Increase the volume in a controlled way, but don't build full peak load yet."
            } else {
                horizonAdvice = "The event is \(weeksText) weeks away. Focus on efficient, high-quality workouts — no more drastic volume increases."
            }

            systemLines.append("• Goal: '\(risk.title)'")
            systemLines.append("  - Current burn rate: \(currentRate) TRIMP/week")
            systemLines.append("  - Required burn rate (ideal): \(Int(risk.requiredWeeklyRate)) TRIMP/week")
            systemLines.append("  - Weekly deficit: \(deficit) TRIMP")
            systemLines.append("  - Weeks remaining: \(weeksText)")
            systemLines.append("  - Horizon advice: \(horizonAdvice)")
            systemLines.append("")

            // Compute the maximum allowed weekly volume (10-15% rule)
            let maxAllowedRate = Int(Double(currentRate) * 1.12) // 12% = middle of 10-15%
            systemLines.append("  ⛔️ HARD PHYSIOLOGICAL LIMIT: The total weekly TRIMP for the coming week must NEVER exceed \(maxAllowedRate) TRIMP (\(currentRate) × 1.12). This is the 10-15% progression rule to prevent overtraining. This is non-negotiable.")
            systemLines.append("")
        }
        systemLines.append(contentsOf: [
            "Give me a concrete, achievable recovery plan for the next 7 days.",
            "The plan must:",
            "1. Strictly respect the 10-15% progression rule — rather slightly too conservative than too aggressive.",
            "2. Spread the deficit over multiple weeks if the event is far away (see horizon advice above).",
            "3. Distribute extra volume via frequency (turn an extra rest day into a light session) instead of one mega session.",
            "4. Always return the full 7-day schedule in JSON format.",
            "",
            "⛔️ EXTRA INTENSITY LIMITS (non-negotiable):",
            "- Indoor sessions (indoor cycling, rowing, swimming) must NEVER be longer than 60 minutes, unless the goal explicitly requires an endurance session of >90 min.",
            "- No single session may be more than 40% higher in TRIMP than the average of the past 7 days. Preventing extreme spikes is a priority."
        ])

        return systemLines.joined(separator: "\n")
    }
}
