import Foundation

/// Story 65.3: pure assembly of the coach prompt.
///
/// Extracted from `ChatViewModel` so the entire context-prefix / system-instruction /
/// status-prompt construction is unit-testable without a `@MainActor` view model or any
/// AppStorage/SwiftData state (CLAUDE.md §6). Every input is passed in; nothing is read
/// from `UserDefaults` here. The structural prompt markers this file emits
/// (`[CURRENT COMPLAINTS]`, `🚨 CRITICAL MILESTONE SHORTFALL`, …) are pinned against the
/// `systemInstruction` reference by `CoachPromptAssemblerTests` per §13.
///
/// Split across three files (all one `CoachPromptAssembler` type):
/// - this file: the `CoachContextSnapshot` value + `buildContextPrefix` + thresholds block
/// - `CoachPromptAssembler+SystemInstruction.swift`: the coach `systemInstruction`
/// - `CoachPromptAssembler+StatusPrompt.swift`: stored-plan / status / action prompts
enum CoachPromptAssembler {

    /// A deterministic snapshot of the ~16 PHI context strings that feed the prompt.
    /// Built by `CoachContextStore.snapshot()` and passed to `buildContextPrefix` so the
    /// assembler stays a pure function of its inputs.
    struct CoachContextSnapshot {
        var todayVibeScoreContext: String = ""
        var lastWorkoutFeedbackContext: String = ""
        var userOverrideContext: String = ""
        var intentExecutionContext: String = ""
        var symptomContext: String = ""
        var workoutPatternsContext: String = ""
        var workoutHistoryContext: String = ""
        var weatherContext: String = ""
        var blueprintContext: String = ""
        var periodizationContext: String = ""
        var intentContext: String = ""
        var eventWindowContext: String = ""
        var gapAnalysisContext: String = ""
        var projectionContext: String = ""
        var nutritionContext: String = ""
        var profileUpdateNote: String = ""
    }

    // MARK: - Context prefix

    /// Generates the context-prefix string that is prepended to every coach payload.
    ///
    /// - Parameters:
    ///   - context: snapshot of the cached PHI context strings.
    ///   - profile: the athletic profile for the `[ATHLETE CONTEXT]` block.
    ///   - activeGoals: active goals — drive the `[PERIODIZATION — ACTIVE TRAINING PHASES]` block.
    ///   - activePreferences: active preferences (pinned + temporary).
    ///   - thresholdProfile: the cached physiological profile for `[TRAINING THRESHOLDS]`.
    ///   - now: injected clock (defaults to now) so date output is deterministic in tests.
    static func buildContextPrefix(
        context: CoachContextSnapshot,
        profile: AthleticProfile?,
        activeGoals: [FitnessGoal] = [],
        activePreferences: [UserPreference] = [],
        thresholdProfile: UserPhysicalProfile,
        now: Date = Date()
    ) -> String {
        var prefix = ""

        let dateFormatter = AppDateFormatters.fixed("yyyy-MM-dd")
        prefix += "[CURRENT DATE: Today is \(dateFormatter.string(from: now)). Use this for your calculations around 'expirationDate'.]\n\n"

        // Epic 14.4: Inject the Vibe Score as hard context — the AI MUST follow this (see system instruction)
        if context.todayVibeScoreContext == VibeScoreContextFormatter.noVibeDataSentinel {
            // No Watch data available — give the coach an explicit instruction to communicate this correctly
            prefix += "[RECOVERY STATUS TODAY: No objective biometric data is available (the user probably didn't wear the Apple Watch overnight). Rely fully on the Symptom Tracker scores and the planned goals. NEVER use phrases like 'I can see from your HRV that...' or 'Your biometrics indicate...'. Instead say: 'Because we have no Watch data today, we'll go by your own feeling and the entered scores.']\n\n"
        } else if !context.todayVibeScoreContext.isEmpty {
            prefix += "[RECOVERY STATUS TODAY: \(context.todayVibeScoreContext) Follow the critical rule about Vibe Score authority strictly.]\n\n"
        }

        // Epic 18.1: Inject the subjective feedback (RPE + mood) of the last workout
        if !context.lastWorkoutFeedbackContext.isEmpty {
            prefix += "[SUBJECTIVE FEEDBACK LAST WORKOUT: \(context.lastWorkoutFeedbackContext) Watch for discrepancies: if TRIMP is low but RPE ≥8, this is an early sign of overtraining or oncoming illness.]\n\n"
        }

        // Story 33.2a: manually moved workouts — coach must respect this.
        if !context.userOverrideContext.isEmpty {
            prefix += context.userOverrideContext
        }

        // Story 33.4: intent-vs-execution analysis for the most recent workout.
        if !context.intentExecutionContext.isEmpty {
            prefix += context.intentExecutionContext
        }

        // Epic 18: Inject the current pain scores per body area (updated daily)
        if !context.symptomContext.isEmpty {
            let symptomBlock = """
            [CURRENT COMPLAINTS — SINGLE SOURCE OF TRUTH (updated daily by the user):
            \(context.symptomContext)
            Behaviour rules:
            1. 🚫 HARD CONSTRAINT present → follow the constraint strictly. Name the injury and the alternative explicitly.
            2. ✅ RECOVERED present → open your Insight with a celebratory confirmation. Propose a careful build-up (e.g. 'Begin met 20 min Zone 1, bouw volgende week op naar normaal volume').
            3. Score ≥7 → extra careful; consider a full rest day or an alternative sport.
            4. Score lower than yesterday → name this as a positive sign of recovery.]
            """
            prefix += symptomBlock + "\n\n"
        }

        // Epic #44 story 44.6: personal training thresholds to the coach. The
        // coach must know that 146 BPM is zone 2 for THIS user, not zone 3.
        // We only add the block if at least one threshold is set —
        // otherwise there is nothing more to say than population defaults and the
        // coach just keeps its own assumptions.
        let thresholdsBlock = buildTrainingThresholdsBlock(profile: thresholdProfile)
        if !thresholdsBlock.isEmpty {
            prefix += thresholdsBlock + "\n\n"
        }

        // Epic 32 Story 32.3c: inject significant physiological patterns from
        // recent workouts. Only medium/significant patterns land in this
        // cache (see `WorkoutPatternFormatter.chatContextLine`); mild patterns
        // would make the prompt too busy.
        if !context.workoutPatternsContext.isEmpty {
            let patternsBlock = """
            [PHYSIOLOGICAL PATTERNS IN RECENT WORKOUTS:
            \(context.workoutPatternsContext)
            Behaviour rules:
            1. If the user asks about recent workouts, refer to these patterns where relevant — be concrete, not a list of technical terms.
            2. On significant cardiac drift + decoupling: ask whether it was deliberate threshold work, or whether external causes were at play (heat, sleep, stress).
            3. Slow HR recovery is a fatigue signal — combine with TRIMP and VibeScore before advising recovery.
            4. Do NOT mention these patterns unprompted in every turn; only when the user reflects on recent execution or asks about training-plan adjustments.]
            """
            prefix += patternsBlock + "\n\n"
        }

        // Epic 45 Story 45.2: richer per-workout context over the past 14 days.
        // Complement to the 1-line pulse above — that gives an aggregate signal,
        // this block gives the specific evidence per workout so plan adjustments
        // can refer to concrete sessions. Deliberately placed right after the patterns block
        // so the coach first reads the signal and then the details.
        if !context.workoutHistoryContext.isEmpty {
            let historyBlock = """
            [RECENT TRAINING — 14 DAYS (newest first):
            \(context.workoutHistoryContext)
            Behaviour rules:
            1. Refer specifically to date + session type on every workout reference ("op 18 april in je tempo-rit met cardiac drift 8% …"). No vague terms like "recent".
            2. On ≥3 consecutive workouts with aerobic_decoupling or cardiac_drift: propose sub-LTHR work and motivate it with the specific data from this list.
            3. Use this data only on reflection/schedule questions/goal analysis — don't recite it unprompted in every turn.
            4. Combine with [TRAINING THRESHOLDS] for zone-correct interpretation of the average HR. Use the same zone terminology ("Zone 2"/"Z2", "Zone 3"/"Z3", "LTHR") — don't invent new labels.
            5. Weigh this data against [CURRENT COMPLAINTS]. On an active injury: interpret patterns like cardiac_drift more cautiously (may be recovery fatigue, not a training need). Don't suggest volume increases if the user is recovering.]
            """
            prefix += historyBlock + "\n\n"
        }

        // Epic 21: Inject the 7-day weather forecast for outdoor-activities coaching
        if !context.weatherContext.isEmpty {
            let weatherBlock = """
            [WEATHER CONDITIONS NEXT 7 DAYS (user's location):
            \(context.weatherContext)
            Behaviour rules:
            1. DAY-SWAP STRATEGY: If a day with ⚠️ BAD OUTDOOR WEATHER has a key workout, look at the next 3 days. Is there a better day? Then EXPLICITLY swap days and state this in the `motivation` field.
            2. TRIMP PREPARATION: If the key workout moves to tomorrow or the day after, advise max. 40-50% TRIMP today as a 'charge day'. State this explicitly.
            3. Always be specific about percentages: not "het kan regenen" but "Zaterdag 72% neerslag → ik verplaats de 60 km naar zondag (5% neerslag, windstil)".
            4. Wind > 30 km/h = relevant for cycling. Always look for a less windy day if there is one.
            5. Temperature < 5°C or > 30°C → tip about clothing or hydration.
            6. You don't need to mention good weather unless it's a bonus ("Sunday looks ideal — perfect for your long ride").]
            """
            prefix += weatherBlock + "\n\n"
        }

        // Epic 17 / Sprint 17.2: Inject the blueprint + periodization context
        // and print the full content to the console for debugging.
        let hasBlueprintData  = !context.blueprintContext.isEmpty
        let hasPeriodization  = !context.periodizationContext.isEmpty

        if hasBlueprintData {
            prefix += "[SPORTS-SCIENCE REQUIREMENTS (BLUEPRINT):\n\(context.blueprintContext)\nInstruction: ALWAYS check whether the user is on schedule for their critical workouts. If there is an outstanding (❌) requirement with an approaching deadline, make this explicit in your advice and schedule that workout.]\n\n"
        }

        if hasPeriodization {
            prefix += "[PERIODIZATION — PHASE, SUCCESS CRITERIA & COACH BEHAVIOUR:\n\(context.periodizationContext)\n\nCoach behaviour rules for this context:\n1. COMPLIMENTS (🎉): If a COMPLIMENT TRIGGER is present, open your answer with it. Name the achievement.\n2. URGENCY (🚨): If a CRITICAL MILESTONE SHORTFALL is present, be direct and motivating. Name the exact distance or TRIMP still missing, and plan it as the first priority in the schedule.\n3. SCHEDULE ADJUSTMENT: If you adjust the schedule, always explain how the phase requirements are still achievable despite the change (SCHEDULE ACCOUNTABILITY).]\n\n"
        }

        // Epic Doel-Intenties: inject the intent and format instructions as a separate section.
        // This tells the coach HOW to train (cruising vs. performing, stage ride vs. one-day)
        // and whether stretch-pace trainings are safe based on the current VibeScore.
        if !context.intentContext.isEmpty {
            let intentBlock = """
            [GOAL INTENTS AND APPROACH — READ THIS BEFORE YOU BUILD THE SCHEDULE:
            \(context.intentContext)

            Binding coach rules:
            1. INTENT TAKES PRIORITY: ALWAYS adapt the schedule to the intent and the format. A 'finish/complete' goal NEVER gets interval or tempo training unless explicitly requested.
            2. BACK-TO-BACK (multi-day stage): Plan hard sessions on consecutive days (e.g. Sat+Sun). Lower the single-session peak load compared to a one-day race.
            3. STRETCH GOAL SAFETY: If '✅ DOELTIJD' is present, plan one tempo session per week at target pace. If '🔴 DOELTIJD' is present, drop all tempo elements and return to pure endurance training.
            4. VIBE SCORE OVERRIDE: If a VibeScore < 65 is mentioned, recovery has absolute priority — drop intensive elements regardless of the rest of the plan.]
            """
            prefix += intentBlock + "\n\n"
        }

        // Epic #55 story 55.3: multi-day event window — the event days ARE the training;
        // suppress other sessions + fixed preferences in the window and plan recovery after.
        if !context.eventWindowContext.isEmpty {
            prefix += context.eventWindowContext + "\n\n"
        }

        // Epic 23 Sprint 1: Inject the gap analysis with TRIMPTranslator hints
        if !context.gapAnalysisContext.isEmpty {
            let gapBlock = """
            [GAP ANALYSIS — BLUEPRINT VS. REALITY (Epic 23):
            \(context.gapAnalysisContext)
            Coach behaviour rules:
            1. TRIMP TRANSLATION (MANDATORY): If there is a 📈 VOLUME ADJUSTMENT with an "X TRIMP ≈ +Y min …" hint, ALWAYS use that translation. NEVER state a bare TRIMP number without the accompanying time indication. Correct: "This week you need about 8 TRIMP extra — that's roughly +4 minutes on your Saturday ride." Wrong: "You're 8 TRIMP short."
            2. TIE TO THE SCHEDULE: Always translate the adjustment into a change to an existing training day. E.g. "Extend your Tuesday endurance run by 5 minutes" or "Ride 10 minutes longer on Saturday along the familiar route."
            3. If there is a 🚴 KM-BIJSTURING: give a concrete weekly schedule with extra km per workout, not as an abstract total.
            4. If the athlete is ahead of schedule: compliment briefly and advise consistency — don't prescribe extra volume.
            5. Always tie it to the phase: adjusting in the Taper phase is undesirable — then advise NOT to make up the deficit but to continue with the tapering schedule.]
            """
            prefix += gapBlock + "\n\n"
        }

        // Epic 23 Sprint 2: Inject the future projection (Future Projection Engine)
        if !context.projectionContext.isEmpty {
            prefix += "\(context.projectionContext)\n\n"
        }

        // Epic 24 Sprint 1: Inject the physiological profile + nutrition plan into the prompt
        if !context.nutritionContext.isEmpty {
            prefix += "\(context.nutritionContext)\n\n"
        }

        // Epic 24 Sprint 3: One-time profile-change notice — inject only once. The caller
        // (`ChatViewModel`) clears the stored note after building so it is not repeated.
        if !context.profileUpdateNote.isEmpty {
            prefix += "\(context.profileUpdateNote)\n\n"
        }

        // Debug: blueprint/periodization context is PHI — log only at .debug
        // level with .private redaction (stripped in release).
        if hasBlueprintData {
            AppLoggers.coach.debug("Blueprint context → coach: \(context.blueprintContext, privacy: .private)")
        }
        if hasPeriodization {
            AppLoggers.coach.debug("Periodization context → coach: \(context.periodizationContext, privacy: .private)")
        }

        // Epic 16: Inject the training phase per active goal — the AI MUST follow the phase instructions strictly
        let activeGoalsWithPhase = activeGoals.compactMap { goal -> (FitnessGoal, TrainingPhase)? in
            guard let phase = goal.currentPhase else { return nil }
            return (goal, phase)
        }
        if !activeGoalsWithPhase.isEmpty {
            prefix += "[PERIODIZATION — ACTIVE TRAINING PHASES:\n"
            for (goal, phase) in activeGoalsWithPhase {
                let weeksLeft = goal.weeksRemaining(from: now)
                let weeksLeftStr = String(format: "%.1f", weeksLeft)
                // Compute the phase-corrected weekly target (linear baseline × multiplier)
                let linearRate = goal.computedTargetTRIMP / max(0.1, weeksLeft)
                let adjustedTarget = Int((linearRate * phase.multiplier).rounded())
                prefix += "• Goal '\(goal.title)' (\(weeksLeftStr) weeks remaining): \(phase.aiInstruction)\n"
                prefix += "  Mathematically adjusted weekly TRIMP target: \(adjustedTarget) TRIMP/week (multiplier: ×\(String(format: "%.2f", phase.multiplier))). Adhere strictly to this target.\n"
            }
            prefix += "]\n\n"
        }

        // Split preferences into pinned (without end date) vs. temporary (with end date) and
        // inject them as two separate blocks — a temporary preference must explicitly take precedence over
        // a conflicting pinned rule during its lifetime. Filtering of
        // expired items + format logic lives in `PreferencesContextFormatter` (testable).
        prefix += PreferencesContextFormatter.format(activePreferences: activePreferences, now: now)

        // Epic 18: Injury context is fully handled via symptomContext (see top of buildContextPrefix).
        // The old static block based on UserPreference texts has been replaced by the dynamic
        // pain scores + HARD CONSTRAINTS generated in cacheSymptomContext(_:preferences:).

        if let p = profile {
            let peakDistanceKm = String(format: "%.1f", p.peakDistanceInMeters / 1000)
            let peakDurationMin = p.peakDurationInSeconds / 60
            let weeklyVolumeMin = p.averageWeeklyVolumeInSeconds / 60

            prefix += "[ATHLETE CONTEXT: Has a peak performance of \(peakDistanceKm) km in \(peakDurationMin) minutes. Trains on average \(weeklyVolumeMin) minutes per week (avg. last 4 weeks), and last trained \(p.daysSinceLastTraining) days ago."

            // SPRINT 6.3: Overtraining warning
            if p.isRecoveryNeeded {
                prefix += " URGENT: The athlete shows signs of overtraining based on recent volume. Be strict, actively advise taking rest, and analyse this workout purely for recovery."
            }

            // SPRINT 9.3: Pace Baseline Injection
            if let avgPaceInSeconds = p.averagePacePerKmInSeconds {
                let minutes = avgPaceInSeconds / 60
                let seconds = avgPaceInSeconds % 60
                let paceString = String(format: "%d:%02d", minutes, seconds)
                prefix += " Important physiological context: The user's current average running pace is around \(paceString) min/km (top of Zone 2). Use this as the absolute baseline to compute realistic 'targetPace' goals for the upcoming workouts."
            }

            prefix += " Take this into account in your analysis about recovery and performance.]\n\n"
        }

        guard !prefix.isEmpty else { return "" }
        prefix += "[QUESTION]: "
        return prefix
    }

    // MARK: - Training thresholds block

    /// Epic #44 story 44.6: builds the `[TRAINING THRESHOLDS]` block based on the given
    /// physiological profile. Returns an empty string if no thresholds are set — then the
    /// coach keeps using its own population assumptions. With a set LTHR we report Friel
    /// zones (more precise), otherwise Karvonen on max+rest.
    static func buildTrainingThresholdsBlock(profile: UserPhysicalProfile) -> String {
        var lines: [String] = []
        if let max = profile.maxHeartRate {
            lines.append("- Max HR: \(Int(max.value)) BPM (\(thresholdSourceLabel(max.source)))")
        }
        if let rest = profile.restingHeartRate {
            lines.append("- Resting HR: \(Int(rest.value)) BPM (\(thresholdSourceLabel(rest.source)))")
        }
        if let lthr = profile.lactateThresholdHR {
            lines.append("- LTHR: \(Int(lthr.value)) BPM (\(thresholdSourceLabel(lthr.source)))")
        }
        if let ftp = profile.ftp {
            lines.append("- FTP: \(Int(ftp.value)) W (\(thresholdSourceLabel(ftp.source)))")
        }
        guard !lines.isEmpty else { return "" }

        // Add explicit Z2/Z3 boundaries so the coach does not
        // misinterpret a 'quiet' ride. Z2 endurance + Z3 tempo are the two zones
        // users reflect on most often.
        var zonesLine: String?
        if let zones = WorkoutPatternDetector.heartRateZones(from: profile),
           zones.count >= 3 {
            let z2 = zones[1]
            let z3 = zones[2]
            zonesLine = "- Zone 2 (endurance): \(z2.lowerBPM)-\(z2.upperBPM) BPM · Zone 3 (tempo): \(z3.lowerBPM)-\(z3.upperBPM) BPM"
        }

        var block = "[TRAINING THRESHOLDS (persoonlijk profiel):\n"
        block += lines.joined(separator: "\n")
        if let zonesLine {
            block += "\n\(zonesLine)"
        }
        block += """

        Behaviour rules:
        1. Always interpret "rustig"/"easy"/"recovery" in the context of THESE thresholds — not population averages. A user with max 200 BPM training at 146 BPM is in Z2, not Z3.
        2. On subjective feedback about exertion: tie it to the zone, not just the BPM number ("145 BPM is voor jou Z2 — dat klopt met 'rustig'").
        3. On plan adjustments where zones are explicitly named, use the BPM boundaries above for the instruction to the user.]
        """
        return block
    }

    static func thresholdSourceLabel(_ source: ThresholdSource) -> String {
        switch source {
        case .automatic: return "auto"
        case .manual:    return "handmatig"
        case .strava:    return "Strava"
        }
    }
}
