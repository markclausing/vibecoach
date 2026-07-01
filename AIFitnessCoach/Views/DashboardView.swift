import SwiftUI
import SwiftData
import Charts
import HealthKit

// MARK: - SPRINT 12.2: TRIMP Explainer Card
struct TRIMPExplainerCard: View {
    /// Collapsed by default — the user opens it when they want to read the details.
    @State private var isExpanded: Bool = false
    @State private var durationMinutes: Double = 60
    @State private var intensityZone: Double = 2.0 // 1 to 5

    // Simple Banister mapping based on Zone (Zone 2 = slight heart rate increase, Zone 5 = max)
    // Z1 ~ 60%, Z2 ~ 70%, Z3 ~ 80%, Z4 ~ 90%, Z5 ~ 95% deltaHR
    private var simulatedDeltaHR: Double {
        switch Int(intensityZone) {
        case 1: return 0.60
        case 2: return 0.70
        case 3: return 0.80
        case 4: return 0.90
        case 5: return 0.95
        default: return 0.70
        }
    }

    private var calculatedTRIMP: Double {
        return durationMinutes * simulatedDeltaHR * 0.64 * exp(1.92 * simulatedDeltaHR)
    }

    struct ExplainerPoint: Identifiable {
        let id = UUID()
        let zone: Int
        let trimp: Double
    }

    private var curveData: [ExplainerPoint] {
        var points: [ExplainerPoint] = []
        for z in 1...5 {
            let hr: Double
            switch z {
            case 1: hr = 0.60; case 2: hr = 0.70; case 3: hr = 0.80; case 4: hr = 0.90; case 5: hr = 0.95; default: hr = 0.70
            }
            let trimpValue = durationMinutes * hr * 0.64 * exp(1.92 * hr)
            points.append(ExplainerPoint(zone: z, trimp: trimpValue))
        }
        return points
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible, tap to expand/collapse
            Button(action: { withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() } }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wat is TRIMP?")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("TRIMP meet de échte fysiologische impact van je training.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            if isExpanded {
            Divider()
            VStack(alignment: .leading, spacing: 16) {
            // Interactive sliders
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Duur: \(Int(durationMinutes)) min")
                        .font(.caption)
                        .fontWeight(.bold)
                    Slider(value: $durationMinutes, in: 10...180, step: 5)
                        .accentColor(.blue)
                }

                VStack(alignment: .leading) {
                    Text("Intensiteit: Zone \(Int(intensityZone))")
                        .font(.caption)
                        .fontWeight(.bold)
                    Slider(value: $intensityZone, in: 1...5, step: 1)
                        .accentColor(.red)
                }
            }
            .padding(.vertical, 8)

            // Dynamic score & chart
            HStack(alignment: .bottom) {
                VStack(alignment: .leading) {
                    Text("TRIMP Score")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(calculatedTRIMP))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(calculatedTRIMP > 100 ? .red : (calculatedTRIMP > 60 ? .orange : .green))
                }

                Spacer()

                Chart(curveData) { point in
                    LineMark(
                        x: .value("Zone", point.zone),
                        y: .value("TRIMP", point.trimp)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.red.gradient)

                    PointMark(
                        x: .value("Zone", point.zone),
                        y: .value("TRIMP", point.trimp)
                    )
                    .symbolSize(point.zone == Int(intensityZone) ? 150 : 50)
                    .foregroundStyle(point.zone == Int(intensityZone) ? .red : .gray)
                }
                .frame(width: 120, height: 60)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            }

            Divider()

            // Fixed explanation text
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(systemName: "clock.fill").foregroundColor(.blue).frame(width: 24)
                    Text("**Volume:** De basis is de tijd die je sport.").font(.caption)
                }
                HStack(alignment: .top) {
                    Image(systemName: "heart.fill").foregroundColor(.red).frame(width: 24)
                    Text("**Intensiteit:** Je hartslag gemeten tegen je persoonlijke maximum.").font(.caption)
                }
                HStack(alignment: .top) {
                    Image(systemName: "flame.fill").foregroundColor(.orange).frame(width: 24)
                    Text("**De Prijs:** In het rood (Zone 4-5) trainen scoort exponentieel hoger door verzuring en spierschade.").font(.caption)
                }
            }
            .padding(.top, 4)
        }
        .padding([.horizontal, .bottom])
        } // end if isExpanded
        }
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

/// Educational info card that explains what the Vibe Score is and how it is calculated.
struct VibeScoreExplainerCard: View {
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { withAnimation(.easeInOut) { isExpanded.toggle() } }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wat is de Vibe Score?")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Jouw dagelijkse lichaamsbatterij (0-100)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text("De Vibe Score (0-100) is jouw dagelijkse lichaamsbatterij. We combineren je slaap van afgelopen nacht met je Heart Rate Variability (HRV) trend.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(alignment: .top) {
                        Image(systemName: "moon.fill").foregroundColor(.indigo).frame(width: 24)
                        Text("**Slaap (50%):** 8+ uur = vol hersteld. Onder de 5 uur = uitgeput zenuwstelsel.").font(.caption)
                    }
                    HStack(alignment: .top) {
                        Image(systemName: "waveform.path.ecg").foregroundColor(.pink).frame(width: 24)
                        Text("**HRV (50%):** Hoger dan jouw 7-daagse gemiddelde = klaar voor belasting. Meer dan 20% eronder = rode vlag voor overtraining.").font(.caption)
                    }
                    HStack(alignment: .top) {
                        Image(systemName: "bolt.fill").foregroundColor(.green).frame(width: 24)
                        Text("**Hoge score:** Je zenuwstelsel is optimaal hersteld en klaar voor zware trainingsbelasting.").font(.caption)
                    }
                    HStack(alignment: .top) {
                        Image(systemName: "battery.0").foregroundColor(.red).frame(width: 24)
                        Text("**Lage score:** Signaal van je lichaam om gas terug te nemen en overtraining te voorkomen.").font(.caption)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

// MARK: - EPIC 18: Post-Workout Check-in Configuration

/// Sprint 19: Central threshold values for the RPE check-in.
/// Always use these constants instead of loose magic numbers across the codebase.
enum WorkoutCheckinConfig {
    /// Minimum duration (seconds) to consider a workout a 'real training' — 15 minutes.
    static let minimumDurationSeconds = 900
    /// Minimum TRIMP for a 'real training'; filters out commutes and short walks.
    static let minimumTRIMP: Double = 15
    /// Sentinel value for 'ignored': falls outside the valid RPE scale (1–10) and marks
    /// that the user deliberately labelled the activity as not a training.
    static let ignoredRPESentinel = 0
}

// MARK: - EPIC 18 / 57: Post-Workout Check-in Card

/// One holistic post-workout feedback choice (Epic #57). Each option maps to an
/// (rpe, mood) pair persisted on `ActivityRecord`, so the coach prompt,
/// `LastWorkoutContextFormatter` and `SessionType.expectedRPERange` keep working on the
/// stored `Int` — no schema migration, no prompt change. The talk-test descriptions make
/// "what do I pick" obvious; one tap saves. The numeric values still land in the four
/// downstream RPE buckets (light 1–3 / moderate 4–6 / hard 7–8 / maximal 9–10), and the
/// 8/9 values keep triggering the low-TRIMP-vs-high-RPE overtraining check.
private struct WorkoutCheckinOption: Identifiable {
    let id: String
    let icon: String
    let label: LocalizedStringKey
    let detail: LocalizedStringKey
    let rpe: Int
    /// Existing mood SF Symbol name, kept verbatim for downstream compatibility.
    let mood: String
    let color: Color

    static let all: [WorkoutCheckinOption] = [
        WorkoutCheckinOption(id: "easy", icon: "leaf.fill",
            label: "Makkelijk", detail: "Kon makkelijk doorpraten",
            rpe: 2, mood: "checkmark.circle.fill", color: .green),
        WorkoutCheckinOption(id: "good", icon: "hand.thumbsup.fill",
            label: "Lekker gewerkt", detail: "Stevig, maar voelde goed",
            rpe: 5, mood: "bolt.fill", color: Color(red: 0.85, green: 0.65, blue: 0.13)),
        WorkoutCheckinOption(id: "hard", icon: "flame.fill",
            label: "Zwaar", detail: "Flink afgezien, praten lukte amper",
            rpe: 8, mood: "zzz", color: Color(red: 0.88, green: 0.58, blue: 0.32)),
        WorkoutCheckinOption(id: "empty", icon: "zzz",
            label: "Leeg / uitgeput", detail: "Kon echt niet meer",
            rpe: 9, mood: "zzz", color: .red),
        WorkoutCheckinOption(id: "pain", icon: "bandage.fill",
            label: "Pijn / klacht", detail: "Er deed iets zeer",
            rpe: 5, mood: "bandage.fill", color: .pink)
    ]
}

/// Card that appears when the most recent real workout (≤48h, ≥15 min, TRIMP ≥15) still has no RPE.
/// Epic #57: the user picks one holistic option (effort + feel combined); one tap saves and the
/// card disappears immediately. rpe == 0 is used as a sentinel for 'Ignored' (not a training).
struct PostWorkoutCheckinCard: View {
    @Bindable var activity: ActivityRecord
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var themeManager: ThemeManager

    /// Callback so DashboardView can update the AI cache immediately after saving.
    /// rpe == 0 means ignored — the caller does not store this as real feedback.
    var onSaved: ((Int, String) -> Void)?

    /// Format the subtitle: '[Sport name] • [Duration] min • [Today/Yesterday]'
    private var subtitle: String {
        let sport = activity.sportCategory.displayName
        let durationMin = activity.movingTime / 60
        let calendar = Calendar.current
        let relativeDay: String
        if calendar.isDateInToday(activity.startDate) {
            relativeDay = String(localized: "Vandaag")
        } else if calendar.isDateInYesterday(activity.startDate) {
            relativeDay = String(localized: "Gisteren")
        } else {
            relativeDay = AppDateFormatters.display("d MMM").string(from: activity.startDate)
        }
        return "\(sport) • \(durationMin) min • \(relativeDay)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with ignore button at the top right
            HStack(alignment: .top) {
                Image(systemName: "checkmark.bubble.fill")
                    .foregroundStyle(themeManager.primaryAccentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hoe ging je laatste training?")
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: ignoreActivity) {
                    Text("Negeer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Epic #57: one tap on a holistic option (effort + feel combined) saves immediately.
            VStack(spacing: 8) {
                ForEach(WorkoutCheckinOption.all) { option in
                    Button(action: { saveFeedback(option) }) {
                        HStack(spacing: 12) {
                            Image(systemName: option.icon)
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(option.color)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.label)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    // Fixed dark text: the option cards use a white background
                                    // (below), so .primary would vanish in dark mode.
                                    .foregroundColor(.black)
                                Text(option.detail)
                                    .font(.caption2)
                                    .foregroundColor(Color(white: 0.45))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Color(white: 0.6))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // White card with a soft drop shadow so each option reads as a
                        // distinct, tappable element against the card's material background.
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("RPEOption_\(option.id)")
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .accessibilityIdentifier("RPECheckinCard")
    }

    private func saveFeedback(_ option: WorkoutCheckinOption) {
        activity.rpe = option.rpe
        activity.mood = option.mood
        try? modelContext.save()
        onSaved?(option.rpe, option.mood)
    }

    /// Marks the activity as 'not a training' via the sentinel value from WorkoutCheckinConfig.
    /// The card disappears immediately; onSaved is not called so the AI cache stays unchanged.
    private func ignoreActivity() {
        activity.rpe = WorkoutCheckinConfig.ignoredRPESentinel
        try? modelContext.save()
    }
}

#Preview {
    ContentView()
        .environmentObject(AppNavigationState())
        .environmentObject(TrainingPlanManager())
}

struct DashboardView: View {
    @EnvironmentObject var appState: AppNavigationState
    @EnvironmentObject var planManager: TrainingPlanManager
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: ChatViewModel

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FitnessGoal.targetDate, order: .forward) private var goals: [FitnessGoal]
    @Query(filter: #Predicate<UserPreference> { $0.isActive == true }, sort: \UserPreference.createdAt, order: .forward) private var activePreferences: [UserPreference]

    @State private var currentProfile: AthleticProfile?
    private let profileManager = AthleticProfileManager()

    @Query(sort: \ActivityRecord.startDate, order: .forward) private var activities: [ActivityRecord]

    @AppStorage("latestCoachInsight") private var latestCoachInsight: String = ""

    // Epic 14.3: Fetch all DailyReadiness records (few records — max 1 per day)
    @Query(sort: \DailyReadiness.date, order: .reverse) private var readinessRecords: [DailyReadiness]

    // Epic 18: Daily symptom scores
    @Query(sort: \Symptom.date, order: .reverse) private var symptoms: [Symptom]

    // Epic 14.3: Loading state for the Vibe Score card
    @State private var isVibeScoreLoading: Bool = false
    @State private var isVibeScoreUnavailable: Bool = false
    @State private var dashboardRestingHR: Double?
    @State private var dashboardVO2Max: Double?

    // Epic #56: location-aware per-stage weather for multi-day events.
    @StateObject private var stageWeatherService = StageWeatherService()

    // Epic 17: BlueprintChecker results for all active goals
    /// Used in the background for coaching context; full UI follows in Sprint 17.3.
    private var blueprintResults: [BlueprintCheckResult] {
        BlueprintChecker.checkAllGoals(Array(goals), activities: Array(activities))
    }

    // Epic 17.1: PeriodizationEngine results — phase + success criteria per active goal
    // Epic Doel-Intenties: pass the current VibeScore so the IntentModifier
    // can correctly evaluate the VibeScore threshold (> 65) for stretch-pace and intensity.
    private var periodizationResults: [PeriodizationResult] {
        PeriodizationEngine.evaluateAllGoals(
            Array(goals),
            activities: Array(activities),
            latestReadinessScore: todayReadiness?.readinessScore
        )
    }

    /// Returns today's DailyReadiness record, or nil if there is none yet.
    private var todayReadiness: DailyReadiness? {
        let todayStart = Calendar.current.startOfDay(for: Date())
        return readinessRecords.first { $0.date >= todayStart }
    }

    /// Epic 18: Today's pain scores.
    private var todaySymptoms: [Symptom] {
        let todayStart = Calendar.current.startOfDay(for: Date())
        return symptoms.filter { $0.date >= todayStart }
    }

    /// Epic 18: Injury risk level based on the highest pain score of today.
    enum InjuryRiskLevel { case safe, caution, risk }
    private var injuryRiskLevel: InjuryRiskLevel {
        let maxSeverity = todaySymptoms.map { $0.severity }.max() ?? 0
        if maxSeverity >= 7 { return .risk }
        if maxSeverity >= 4 { return .caution }
        return .safe
    }

    /// Epic 18: Detect which body areas are active based on UserPreference texts.
    private var activeInjuryAreas: [BodyArea] {
        let now = Date()
        let validPrefs = activePreferences.filter {
            $0.expirationDate == nil || $0.expirationDate! > now
        }
        return BodyArea.allCases.filter { area in
            validPrefs.contains { pref in
                let text = pref.preferenceText.lowercased()
                return area.injuryKeywords.contains(where: { text.contains($0) })
            }
        }
    }

    /// Epic 18.2: Returns the most recent ActivityRecord that asks for a check-in.
    /// Threshold values come from WorkoutCheckinConfig (Sprint 19 — no magic numbers).
    /// rpe == nil → unrated. rpe == ignoredRPESentinel → deliberately ignored. Both excluded.
    private var recentUncheckedActivity: ActivityRecord? {
        let fortyEightHoursAgo = Calendar.current.date(byAdding: .hour, value: -48, to: Date()) ?? Date()
        return activities
            .filter { record in
                guard record.startDate >= fortyEightHoursAgo else { return false }
                guard record.rpe == nil else { return false }
                guard record.movingTime >= WorkoutCheckinConfig.minimumDurationSeconds else { return false }
                guard (record.trimp ?? 0) >= WorkoutCheckinConfig.minimumTRIMP else { return false }
                return true
            }
            .max(by: { $0.startDate < $1.startDate })
    }

    /// Reads directly from viewModel (backed by CoachContextCache SwiftData since Story 61.7).
    /// @AppStorage("vibecoach_lastAnalysisTimestamp") was a stale mirror that no longer updated.
    private var lastAnalysisTimestamp: Double { viewModel.lastAnalysisTimestamp }

    // Epic 34.1: V2.0 Fit & Finish — material overlay on the status bar once the
    // user scrolls, so content does not slide visibly under the clock/battery.
    @State private var isDashboardScrolled: Bool = false

    /// Epic 18: Becomes true once the user adjusts a symptom score after the last analysis.
    /// Indicates that the CoachInsight is stale and needs a new analysis.
    @State private var symptomChangedSinceAnalysis: Bool = false

    /// Returns a readable timestamp string, e.g. "Laatste update: vandaag om 17:15".
    private var lastAnalysisText: String {
        guard lastAnalysisTimestamp > 0 else { return "" }
        let date = Date(timeIntervalSince1970: lastAnalysisTimestamp)
        // Epic #37 story 37.1c: the quoted literals inside the date format ('vandaag om') and
        // the prefix below are localized via the String Catalog; HH:mm / d MMM are locale-driven.
        let format: String
        if Calendar.current.isDateInToday(date) {
            format = String(localized: "'vandaag om' HH:mm")
        } else if Calendar.current.isDateInYesterday(date) {
            format = String(localized: "'gisteren om' HH:mm")
        } else {
            format = String(localized: "d MMM 'om' HH:mm")
        }
        return String(localized: "Laatste update: \(AppDateFormatters.display(format).string(from: date))")
    }

    // MARK: - Contextual TRIMP banner status (ACWR-based)

    /// The most recent workout (last 48h) with a TRIMP value.
    private var lastWorkout: ActivityRecord? {
        let cutoff = Calendar.current.date(byAdding: .hour, value: -48, to: Date()) ?? Date()
        return activities
            .filter { $0.startDate >= cutoff && ($0.trimp ?? 0) >= WorkoutCheckinConfig.minimumTRIMP }
            .max(by: { $0.startDate < $1.startDate })
    }

    /// Average TRIMP per session over the last 14 days (chronic load).
    /// Requires at least 3 sessions for a reliable baseline; otherwise nil.
    private var chronicTRIMPPerSession: Double? {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) else { return nil }
        let recentSessions = activities.filter {
            $0.startDate >= cutoff && ($0.trimp ?? 0) >= WorkoutCheckinConfig.minimumTRIMP
        }
        guard recentSessions.count >= 3 else { return nil }
        let totalTRIMP = recentSessions.compactMap { $0.trimp }.reduce(0, +)
        return totalTRIMP / Double(recentSessions.count)
    }

    /// Weekly TRIMP target based on the active goal with the highest required weekly rate.
    private var weeklyTRIMPTarget: Double {
        let now = Date()
        let activeGoals = goals.filter { !$0.isCompleted && now < $0.targetDate }
        guard !activeGoals.isEmpty else { return 0 }
        return activeGoals.compactMap { goal -> Double? in
            let weeksRemaining = max(0.1, goal.weeksRemaining(from: now))
            let phase = goal.currentPhase ?? .baseBuilding
            let linearRate = goal.computedTargetTRIMP / weeksRemaining
            return linearRate * phase.multiplier
        }.max() ?? 0
    }

    /// Sum of TRIMP over the last 7 days.
    private var currentWeekTRIMP: Double {
        guard let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return 0 }
        return activities
            .filter { $0.startDate >= weekAgo }
            .compactMap { $0.trimp }
            .reduce(0, +)
    }

    enum BannerState {
        /// Acute:Chronic ratio > 1.5 — peak too large relative to chronic load.
        /// percentageAbove = how many % above the chronic norm (e.g. 73 = +73%).
        /// injuryContext = optional injury description (e.g. "kuitklachten") if the sport is extra straining.
        case overreached(workoutName: String, actualTRIMP: Int, chronicTRIMP: Int, percentageAbove: Int, injuryContext: String?)
        /// Low Vibe Score + heavy training — physiologically double stress.
        case lowVibeHighLoad(workoutName: String, vibeScore: Int, actualTRIMP: Int)
        /// Cumulative weekly TRIMP is <50% of the weekly target.
        case behindOnPlan(currentTRIMP: Int, targetTRIMP: Int)
        case none
    }

    private var bannerState: BannerState {
        // Trigger 1: ACWR > 1.5 — acute load significantly higher than chronic average.
        // Compares the LAST workout with the average session TRIMP of the last 14 days.
        // Injury penalty via InjuryImpactMatrix: with calf complaints a running session counts 1.4× heavier.
        if let last = lastWorkout, let acuteTRIMP = last.trimp,
           let chronic = chronicTRIMPPerSession, chronic > 0 {
            let injuryPenalty = InjuryImpactMatrix.penaltyMultiplier(for: last.sportCategory, given: Array(activePreferences))
            let effectiveTRIMP = acuteTRIMP * injuryPenalty
            let ratio = effectiveTRIMP / chronic
            if ratio > 1.5 {
                let percentAbove = Int((ratio - 1.0) * 100)
                let injury = InjuryImpactMatrix.injuryDescription(for: last.sportCategory, given: Array(activePreferences))
                return .overreached(
                    workoutName: last.displayName,
                    actualTRIMP: Int(acuteTRIMP),
                    chronicTRIMP: Int(chronic),
                    percentageAbove: percentAbove,
                    injuryContext: injury
                )
            }

            // Trigger 2: Low Vibe Score (<40) combined with heavy training (>chronic average).
            // Even a normal training is too much when the body is already exhausted.
            if let vibe = todayReadiness?.readinessScore, vibe < 40, acuteTRIMP > chronic {
                return .lowVibeHighLoad(
                    workoutName: last.displayName,
                    vibeScore: vibe,
                    actualTRIMP: Int(acuteTRIMP)
                )
            }
        }

        // Trigger 3: Blue — behind on the weekly plan (only halfway through the week or later).
        let target = weeklyTRIMPTarget
        if target > 0 {
            let dayOfWeek = Calendar.current.component(.weekday, from: Date())
            let isHalfwayThrough = dayOfWeek >= 4 // Wednesday or later
            if isHalfwayThrough && currentWeekTRIMP < target * 0.5 {
                return .behindOnPlan(currentTRIMP: Int(currentWeekTRIMP), targetTRIMP: Int(target))
            }
        }

        return .none
    }

    private func refreshProfileContext() {
        do {
            self.currentProfile = try profileManager.calculateProfile(context: modelContext)
        } catch {
            AppLoggers.dashboard.error("Profile load failed in DashboardView: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Sprint 13.1: Risk assessment per goal

    /// Lightweight status struct per goal that falls behind on the burndown.
    struct GoalRiskStatus {
        let goal: FitnessGoal
        let currentWeeklyRate: Double       // Actual burn rate (TRIMP/week)
        let requiredWeeklyRate: Double      // Phase-corrected required burn rate
        /// Sprint 16.2: True if the user trains too hard in Tapering (>110% of the lowered target)
        let isTaperingOverload: Bool
    }

    /// Sprint 16.2: Returns active goals with a phase-aware risk status.
    /// - Underperformance: actual burn rate < 75% of phase-corrected target → Red
    /// - Tapering overload: actual burn rate > 110% of tapering target → Red (different reason)
    private var atRiskGoals: [GoalRiskStatus] {
        let now = Date()
        let calendar = Calendar.current
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let trainingBlockStart = calendar.date(byAdding: .weekOfYear, value: -16, to: now) ?? now

        return goals.compactMap { goal in
            guard !goal.isCompleted, now < goal.targetDate else { return nil }

            let targetTRIMP = goal.computedTargetTRIMP
            let weeksRemaining = max(0.1, goal.weeksRemaining(from: now))
            let phase = goal.currentPhase ?? .baseBuilding

            // Filter relevant activities to the training block for this goal + sport category.
            let relevantActivities = activities.filter { record in
                guard record.startDate >= trainingBlockStart && record.startDate <= now else { return false }
                guard let goalCategory = goal.sportCategory else { return true }
                if goalCategory == .triathlon {
                    return [.running, .cycling, .swimming, .triathlon].contains(record.sportCategory)
                }
                return record.sportCategory == goalCategory
            }

            // Calculate how much TRIMP remains
            let achievedTRIMP = relevantActivities.compactMap { $0.trimp }.reduce(0, +)
            let currentRemaining = max(0, targetTRIMP - achievedTRIMP)
            guard currentRemaining > 0 else { return nil }

            // Burn rate based on the last 2 weeks
            let recentTRIMP = relevantActivities
                .filter { $0.startDate >= twoWeeksAgo }
                .compactMap { $0.trimp }
                .reduce(0, +)
            let currentBurnRate = recentTRIMP / 2.0

            // Sprint 16.2: Phase-corrected target
            let linearRate = currentRemaining / weeksRemaining
            let adjustedRequired = linearRate * phase.multiplier

            // Tapering: training too hard is more dangerous than too little
            if phase == .tapering && currentBurnRate > adjustedRequired * 1.10 {
                return GoalRiskStatus(goal: goal, currentWeeklyRate: currentBurnRate, requiredWeeklyRate: adjustedRequired, isTaperingOverload: true)
            }

            // Normal underperformance: actual rate < 75% of phase target
            guard currentBurnRate < adjustedRequired * 0.75 else { return nil }
            return GoalRiskStatus(goal: goal, currentWeeklyRate: currentBurnRate, requiredWeeklyRate: adjustedRequired, isTaperingOverload: false)
        }
        .sorted { ($0.requiredWeeklyRate - $0.currentWeeklyRate) > ($1.requiredWeeklyRate - $1.currentWeeklyRate) }
    }

    /// Checks and backfills missing `targetTRIMP` for legacy goals (Epic 12 Data Migration)
    private func backfillLegacyGoals() {
        var hasChanges = false
        for goal in goals {
            if goal.targetTRIMP == nil || goal.targetTRIMP == 0 {
                let days = max(1.0, goal.totalDays)
                goal.targetTRIMP = (days / 7.0) * 350.0
                hasChanges = true
            }
        }

        if hasChanges {
            try? modelContext.save()
        }
    }

    /// V2.0: Name of today's training for the coach hint in the Vibe Score card.
    private var todayPlanWorkoutName: String? {
        planManager.activePlan?.workouts
            .first {
                Calendar.current.isDateInToday($0.resolvedDate) && !$0.isRestDay
            }
            .map { $0.activityType }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // V2.0: Contextual header (day · phase · week)
                    DashboardHeaderView(
                        periodizationResults: periodizationResults,
                        goals: Array(goals)
                    )

                    // V2.0: Integrated Vibe Score card with metrics grid
                    VibeScoreCardV2(
                        readiness: todayReadiness,
                        isLoading: isVibeScoreLoading,
                        isUnavailable: isVibeScoreUnavailable,
                        injuryRiskLevel: injuryRiskLevel,
                        todayWorkoutName: todayPlanWorkoutName,
                        onAskWhy: { appState.showingChatSheet = true },
                        liveRestingHeartRate: dashboardRestingHR,
                        liveVO2Max: dashboardVO2Max
                    )
                    .padding(.horizontal)

                    // Epic 18: Symptom check-in — only visible with active injuries
                    if !activeInjuryAreas.isEmpty {
                        SymptomCheckinCard(
                            areas: activeInjuryAreas,
                            todaySymptoms: todaySymptoms,
                            onSave: { area, severity in
                                saveOrUpdateSymptom(area: area, severity: severity)
                            }
                        )
                        .padding(.horizontal)
                    }

                    // Post-workout RPE check-in
                    if let recentActivity = recentUncheckedActivity {
                        PostWorkoutCheckinCard(activity: recentActivity) { rpe, mood in
                            viewModel.cacheLastWorkoutFeedback(
                                rpe: rpe,
                                mood: mood,
                                workoutName: recentActivity.displayName,
                                trimp: recentActivity.trimp,
                                startDate: recentActivity.startDate,
                                sessionType: recentActivity.sessionType
                            )
                        }
                        .padding(.horizontal)
                    }

                    // Epic #51-H: migration fallback banner. Only appears if
                    // the SwiftData migration failed during the last app launch
                    // and the fresh-DB fallback (CLAUDE.md §12) wiped local-only data
                    // (FitnessGoal/UserPreference/Symptom).
                    MigrationFallbackBanner()

                    // Epic #51-F1/F2/F5: one central banner for sync errors,
                    // Strava rate limits and offline detection. Priority:
                    // offline > rate-limited > error > nil (see
                    // `SyncBannerStateBuilder`). Renders nothing if the status
                    // is healthy.
                    SyncStatusBanner()

                    // Epic #38 Story 38.2: silent-sync detection. Only shows
                    // when the last HK sync yielded 0 workouts and the
                    // workout auth status is not `sharingAuthorized`. Silent
                    // no-op otherwise — no extra spacing/divider.
                    HealthKitPermissionWarningBanner()

                    // ACWR banners — based on Acute:Chronic Workload Ratio
                    switch bannerState {
                    case .overreached(let name, _, let chronic, let pct, let injury):
                        DashboardBannerView(icon: "exclamationmark.triangle.fill", color: .orange) {
                            VStack(alignment: .leading, spacing: 2) {
                                // Epic #37: pre-format Ints as String so the generated format key
                                // uses %@ (not %lld) and matches the catalog entry — otherwise the
                                // lookup misses and the banner falls back to Dutch on device.
                                let pctStr = "\(pct)"
                                let chronicStr = "\(chronic)"
                                Text("**\(name)** was +\(pctStr)% boven je gemiddelde training (\(chronicStr) TRIMP).")
                                    .font(.caption)
                                if let inj = injury {
                                    Text("Let op: Gezien je \(inj) was deze training extra belastend voor je herstel.")
                                        .font(.caption)
                                } else {
                                    Text("Hoewel je weekdoel nog niet bereikt is, is rust nu de slimste stap.")
                                        .font(.caption)
                                }
                            }
                        }
                    case .lowVibeHighLoad(let name, let vibe, let actual):
                        DashboardBannerView(icon: "exclamationmark.triangle.fill", color: .orange) {
                            // Epic #37: pre-format Ints as String → %@ key matches the catalog.
                            let vibeStr = "\(vibe)"
                            let actualStr = "\(actual)"
                            Text("Je Vibe Score is \(vibeStr)/100 — je lichaam is uitgeput. **\(name)** (TRIMP: \(actualStr)) was zwaarder dan je herstel toelaat. Neem rust.")
                                .font(.caption)
                        }
                    case .behindOnPlan(let current, let target):
                        DashboardBannerView(icon: "info.circle.fill", color: themeManager.primaryAccentColor) {
                            // Epic #37: pre-format Ints as String → %@ key matches the catalog.
                            let currentStr = "\(current)"
                            let targetStr = "\(target)"
                            Text("Je TRIMP deze week (\(currentStr)) ligt achter op het weekdoel (\(targetStr)). Pak de geplande trainingen op.")
                                .font(.caption)
                        }
                    case .none:
                        EmptyView()
                    }

                    // AI analysis loading indicator
                    if viewModel.isFetchingWorkout || viewModel.isTyping {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(viewModel.retryStatusMessage.isEmpty
                                 ? String(localized: "Coach analyseert schema...")
                                 : viewModel.retryStatusMessage)
                                .font(.caption)
                                .foregroundColor(viewModel.retryStatusMessage.isEmpty ? .secondary : .orange)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }

                    // Error banner for failed AI analysis (pull-to-refresh timeout etc).
                    // Otherwise the error message is only shown in the invisible chat bubble.
                    if let aiError = viewModel.lastAIErrorMessage, !viewModel.isFetchingWorkout, !viewModel.isTyping {
                        DashboardBannerView(icon: "exclamationmark.triangle.fill", color: .orange) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(aiError)
                                    .font(.caption)
                                HStack(spacing: 12) {
                                    Button("Opnieuw proberen") {
                                        refreshProfileContext()
                                        viewModel.analyzeCurrentStatus(days: 7, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                                    }
                                    .font(.caption.weight(.semibold))
                                    Button("Sluit") {
                                        viewModel.lastAIErrorMessage = nil
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }

                    // Coach Insight card — V2.0 style
                    if !latestCoachInsight.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(themeManager.primaryAccentColor)
                                Text("Coach Insight")
                                    .font(.headline)
                                Spacer()
                                if symptomChangedSinceAnalysis {
                                    Text("Verouderd — score gewijzigd")
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange)
                                        .cornerRadius(6)
                                } else if !lastAnalysisText.isEmpty {
                                    Text(lastAnalysisText)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Text(latestCoachInsight)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
                        .padding(.horizontal)
                    }

                    // V2.0: Week timeline + daily workout overview
                    WeekTimelineView(
                        plan: planManager.activePlan,
                        activities: Array(activities),
                        currentWeekTRIMP: currentWeekTRIMP,
                        weeklyTRIMPTarget: weeklyTRIMPTarget,
                        weeklyForecast: WeatherManager.shared.weeklyForecast,
                        // Epic #55 story 55.2: synthesize multi-day event stage entries.
                        eventGoals: Array(goals),
                        // Epic #56: location-aware per-stage forecasts along the event route.
                        stageWeather: stageWeatherService.stageWeather,
                        onSkipWorkout: { workout in
                            refreshProfileContext()
                            viewModel.skipWorkout(workout, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                            appState.showingChatSheet = true
                        },
                        onAlternativeWorkout: { workout in
                            refreshProfileContext()
                            viewModel.requestAlternativeWorkout(workout, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                            appState.showingChatSheet = true
                        },
                        onResetSchema: {
                            // Story 33.2b: ask the coach to replan the week
                            // around the moved sessions. The merge happens app-side.
                            let swapped = planManager.activePlan?.workouts.filter { $0.isSwapped } ?? []
                            refreshProfileContext()
                            viewModel.requestPlanReset(
                                swappedWorkouts: swapped,
                                contextProfile: currentProfile,
                                activeGoals: goals,
                                activePreferences: activePreferences
                            )
                            appState.showingChatSheet = true
                        },
                        isResettingSchema: viewModel.isTyping
                    )

                    // V2.0: 14-day trend widget
                    TrendWidgetView(
                        readinessRecords: Array(readinessRecords),
                        activities: Array(activities)
                    )

                    // Epic 32 Story 32.2: list of recent workouts. HealthKit records are
                    // tappable and navigate to the WorkoutAnalysisView with the granular 5s charts.
                    RecentWorkoutsSection()

                    // TRIMP & Vibe Score educational cards
                    TRIMPExplainerCard()
                        .padding(.horizontal)
                    VibeScoreExplainerCard()
                        .padding(.horizontal)
                }
                .padding(.bottom, 40)
            }
            .refreshable {
                NotificationCenter.default.post(name: NSNotification.Name("TriggerAutoSync"), object: nil)
                refreshProfileContext()
                isVibeScoreUnavailable = false
                await calculateAndSaveVibeScore()
                viewModel.cacheVibeScore(todayReadiness)
                viewModel.analyzeCurrentStatus(days: 7, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                ProactiveNotificationService.shared.updateRiskCache(
                    atRiskGoalTitles: atRiskGoals.map { $0.goal.title }
                )
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            // Epic 34.1: detect scroll to make material appear under the status bar.
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > 4
            } action: { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDashboardScrolled = newValue
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(Color(.secondarySystemBackground).ignoresSafeArea())
            // Epic 34.1: material band in the top safe area — only visible when scrolling.
            .scrollEdgeMaterial(isActive: isDashboardScrolled)
            // Epic 18: Reset the staleness badge once a new analysis has finished.
            .onChange(of: lastAnalysisTimestamp) { _, _ in
                symptomChangedSinceAnalysis = false
            }
            .onAppear {
                backfillLegacyGoals()
                refreshProfileContext()
                // SPRINT 13.2: Update the risk cache on every app open so
                // the background engines always have current data
                ProactiveNotificationService.shared.updateRiskCache(
                    atRiskGoalTitles: atRiskGoals.map { $0.goal.title }
                )
                // Sprint 20.2: HealthKit permission is requested exclusively via the
                // OnboardingView (first use) or via Settings (afterwards).
                // EPIC 14.3: Calculate the Vibe Score automatically if there is no record for today yet.
                if todayReadiness == nil {
                    Task { await calculateAndSaveVibeScore() }
                }
                // Fetch resting heart rate live so the card is always current,
                // even if the DailyReadiness record predates our change.
                Task {
                    let hk = HealthKitManager()
                    dashboardRestingHR = await hk.fetchRestingHeartRate()
                    dashboardVO2Max = await hk.fetchVO2Max()
                }
                // Auto-refresh: if the last analysis is from a previous day, request a new one immediately.
                // This way the day always starts with a current schedule — even after midnight.
                let lastAnalysisDate = Date(timeIntervalSince1970: lastAnalysisTimestamp)
                if lastAnalysisTimestamp == 0 || !Calendar.current.isDateInToday(lastAnalysisDate) {
                    viewModel.analyzeCurrentStatus(days: 7, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                }
                // EPIC 14.4: Write today's Vibe Score to the AI prompt cache
                // so every coach interaction knows the current recovery status.
                viewModel.cacheVibeScore(todayReadiness)
                // Epic 17: Write the blueprint status to the AI prompt cache
                // so the coach knows which critical trainings are open per goal.
                viewModel.cacheSymptomContext(Array(symptoms), preferences: Array(activePreferences))
                viewModel.cacheActiveBlueprints(blueprintResults)
                // Epic 17.1: Write the periodization status to the AI prompt cache
                // so the coach knows the current training phase and success criteria.
                viewModel.cachePeriodizationStatus(periodizationResults)
                // Epic Doel-Intenties: write the intent instructions to the separate cache
                // so the coach receives a targeted [DOEL INTENTIES EN BENADERING] section.
                viewModel.cacheIntentContext(periodizationResults)
                // Epic #55 story 55.3: write the multi-day event-window block(s) so the coach
                // suppresses other training in the event window and plans post-event recovery.
                viewModel.cacheEventWindow(Array(goals))
                // Epic #56: resolve routes + fetch per-stage forecasts for multi-day events.
                let eventGoalsSnapshot = Array(goals)
                Task { await stageWeatherService.refresh(goals: eventGoalsSnapshot) }
                // Epic 23 Sprint 1: Write the gap analysis to the AI prompt cache
                // so the coach knows how much TRIMP/km the athlete is behind on the linear schedule.
                let gapResults = ProgressService.analyzeGaps(for: Array(goals), activities: Array(activities))
                viewModel.cacheGapAnalysis(gapResults)
                // Epic 23 Sprint 2: Write the future projection to the AI prompt cache
                // so the coach can proactively warn if a goal is "At Risk" or "Unreachable".
                let projectionResults = FutureProjectionService.calculateProjections(for: Array(goals), activities: Array(activities))
                viewModel.cacheProjections(projectionResults)
                // EPIC 18: Write the most recent real workout rating to the AI prompt cache.
                // rpe == WorkoutCheckinConfig.ignoredRPESentinel (0) does not count as real feedback.
                let lastRatedActivity = activities
                    .filter { ($0.rpe ?? WorkoutCheckinConfig.ignoredRPESentinel) > WorkoutCheckinConfig.ignoredRPESentinel }
                    .max(by: { $0.startDate < $1.startDate })
                viewModel.cacheLastWorkoutFeedback(
                    rpe: lastRatedActivity?.rpe,
                    mood: lastRatedActivity?.mood,
                    workoutName: lastRatedActivity?.displayName,
                    trimp: lastRatedActivity?.trimp,
                    startDate: lastRatedActivity?.startDate,
                    sessionType: lastRatedActivity?.sessionType
                )
                // Story 33.2a: write the USER_OVERRIDE cache so the coach respects manually
                // moved sessions in every prompt build.
                viewModel.cacheUserOverrides(planManager.activePlan?.workouts ?? [])

                // Story 33.4: find the most recent ActivityRecord that matches a
                // SuggestedWorkout on the same calendar day, run the analyzer and cache the
                // result so the coach gets the [ANALYSIS — INTENT vs UITVOERING].
                let plannedWorkouts = planManager.activePlan?.workouts ?? []
                if let mostRecent = activities.max(by: { $0.startDate < $1.startDate }),
                   let plannedMatch = plannedWorkouts.first(matching: mostRecent) {
                    // 33.4 uses the classifier only for `classifyByKeywords` —
                    // which ignores maxHeartRate. So the default suffices without a dateOfBirth fetch.
                    let verdict = IntentExecutionAnalyzer.analyze(
                        planned: plannedMatch,
                        actual: mostRecent,
                        maxHeartRate: HeartRateZones.defaultMaxHeartRate
                    )
                    let formatted = IntentExecutionContextFormatter.format(
                        verdict: verdict,
                        plannedActivity: plannedMatch.activityType,
                        actualActivityName: mostRecent.displayName,
                        plannedTRIMP: plannedMatch.targetTRIMP,
                        actualTRIMP: mostRecent.trimp
                    )
                    viewModel.cacheIntentExecution(formatted)
                } else {
                    viewModel.cacheIntentExecution("")
                }

                // Epic 24 Sprint 1: Fetch the physiological profile and calculate the nutrition plan
                // for today's and tomorrow's workouts. Cached in AppStorage for the AI prompt.
                Task { await viewModel.refreshNutritionContext() }
                // Epic 21: Request weather data via the singleton (asks for location permission if not done yet).
                // WeatherManager.shared is a singleton — no property passing needed from ContentView.
                WeatherManager.shared.onWeatherUpdated = { context in
                    viewModel.weatherContext = context
                }
                WeatherManager.shared.requestWeatherIfNeeded()
            }
            // Epic 32 Story 32.1: 30-day Deep Sync of workout samples.
            // Since fix/workout-samples-loading: no more one-shot completion flag —
            // the service keeps running once the Dashboard reappears, idempotent via
            // the processed-UUID set. New workouts from auto-sync get their chart data
            // along with it without the user being stuck endlessly on the placeholder
            // "Deep Sync loopt op de achtergrond".
            .task {
                let store = WorkoutSampleStore(modelContainer: modelContext.container)
                let ingest = WorkoutSampleIngestService()
                let service = DeepSyncService(ingestService: ingest, store: store)
                await service.runIfNeeded()
            }
            // Epic 40 Story 40.3: backfill of Strava streams for the last 10
            // Strava records without samples. 100ms throttle between calls to
            // comfortably respect Strava's rate limit (100 req/15min). A per-record error
            // does not block the batch — just continue with the next.
            // Right after that: Epic 41 auto-dedupe — cleans up any duplicates
            // (HK + Strava of the same ride) so the user does not get a double list.
            .task {
                await backfillStravaStreams()
                await runAutoDedupe()
                await runSessionReclassification()
                await refreshChatContextCaches()
                #if DEBUG
                await runPatternDebugReport()
                #endif
            }
        }
    }

    /// Epic 45 Story 45.3: fills both the 7-day pulse cache (Story 32.3c) and
    /// the 14-day rich per-workout block in one shared loop. Per workout
    /// `WorkoutPatternDetector.detectAll` is called exactly once — both caches
    /// eat from the same `[WorkoutEntry]` array. That halves the SwiftData fetch I/O
    /// and prevents duplicate detector calls compared to two separate refresh functions.
    /// Silent no-op if there are no workouts in the window — caches are then
    /// emptied so a stable week also cleans up the cache.
    private func refreshChatContextCaches() async {
        let store = WorkoutSampleStore(modelContainer: modelContext.container)
        let now = Date()
        let cutoff14 = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        let cutoff7  = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        // Epic #44 story 44.5: fetch the profile here once and pass it to
        // detectAll so the zone gates per workout consistently use the same thresholds.
        let profile = UserProfileService.cachedProfile()

        var entries: [WorkoutHistoryContextBuilder.WorkoutEntry] = []
        var patterns7d: [WorkoutPattern] = []

        for activity in activities where activity.startDate >= cutoff14 {
            let uuid = UUID.forActivityRecordID(activity.id)
            let samples = (try? await store.samples(forWorkoutUUID: uuid)) ?? []
            let detected: [WorkoutPattern] = samples.isEmpty
                ? []
                : WorkoutPatternDetector.detectAll(in: samples, profile: profile)

            entries.append(WorkoutHistoryContextBuilder.WorkoutEntry(
                startDate: activity.startDate,
                displayName: activity.name,
                sportCategory: activity.sportCategory,
                sessionType: activity.sessionType,
                movingTime: activity.movingTime,
                trimp: activity.trimp,
                averageHeartrate: activity.averageHeartrate,
                averagePower: nil,                  // Epic #40 hookup later
                patterns: detected
            ))

            if activity.startDate >= cutoff7 {
                patterns7d.append(contentsOf: detected)
            }
        }

        viewModel.workoutPatternsContext = WorkoutPatternFormatter.chatContextLine(for: patterns7d) ?? ""
        viewModel.workoutHistoryContext = WorkoutHistoryContextBuilder.build(entries: entries)
    }

    #if DEBUG
    /// Story 32.3a empirical validation: runs `WorkoutPatternDetector.detectAll`
    /// over all workouts with stored samples and prints the found patterns.
    /// Intended to check before 32.3b (UI pins) whether the thresholds trigger
    /// at all on real data — no UI effect, only console output.
    private func runPatternDebugReport() async {
        let store = WorkoutSampleStore(modelContainer: modelContext.container)
        let profile = UserProfileService.cachedProfile()
        var triggered = 0
        var scanned = 0
        var skippedNoSamples = 0
        for activity in activities {
            let uuid = UUID.forActivityRecordID(activity.id)
            let samples = (try? await store.samples(forWorkoutUUID: uuid)) ?? []
            let dateLabel = activity.startDate.formatted(date: .abbreviated, time: .shortened)
            guard !samples.isEmpty else {
                skippedNoSamples += 1
                print("📊 [Pattern-debug] '\(activity.displayName)' op \(dateLabel) — geen samples opgeslagen, overgeslagen")
                continue
            }
            scanned += 1
            let patterns = WorkoutPatternDetector.detectAll(in: samples, profile: profile)
            if patterns.isEmpty {
                print("📊 [Pattern-debug] '\(activity.displayName)' op \(dateLabel) — \(samples.count) samples · geen patronen (alle filters/zones-gates negatief)")
                continue
            }
            triggered += 1
            print("📊 [Pattern-debug] '\(activity.displayName)' op \(dateLabel) — \(samples.count) samples")
            for pattern in patterns {
                print("   • \(pattern.kind) [\(pattern.severity)]: \(pattern.detail)")
            }
        }
        print("📊 [Pattern-debug] Scan klaar — \(triggered)/\(scanned) workouts met samples hadden patronen, \(skippedNoSamples) overgeslagen wegens geen samples (\(activities.count) totaal in DB).")
    }
    #endif

    /// Epic 41: auto-dedupe via `ActivityDeduplicator`. Idempotent — a clean DB stays
    /// clean. Runs after the Strava backfill so sample counts are correct for the
    /// richness heuristic (Strava records with just-arrived power win).
    private func runAutoDedupe() async {
        let store = WorkoutSampleStore(modelContainer: modelContext.container)
        do {
            let removed = try await ActivityDeduplicator.runDedupe(in: modelContext, store: store)
            if removed > 0 {
                AppLoggers.dashboard.info("Auto-dedupe: removed \(removed, privacy: .public) duplicate ActivityRecord(s)")
            }
        } catch {
            AppLoggers.dashboard.error("Auto-dedupe failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Epic 40 Story 40.4: after the stream backfill (and the subsequent dedupe),
    /// records that previously only had avg-HR suddenly have fine-grained samples. We let
    /// `SessionReclassifier` rerun the zone-distribution strategy — manually
    /// chosen sessionTypes stay protected via `manualSessionTypeOverride`.
    private func runSessionReclassification() async {
        let store = WorkoutSampleStore(modelContainer: modelContext.container)
        let birthDate: Date? = {
            do {
                let dob = try HKHealthStore().dateOfBirthComponents()
                return Calendar.current.date(from: dob)
            } catch {
                return nil
            }
        }()
        let maxHR = HeartRateZones.estimatedMaxHeartRate(birthDate: birthDate)
        do {
            let updated = try await SessionReclassifier.rerun(
                in: modelContext,
                store: store,
                maxHeartRate: maxHR
            )
            if updated > 0 {
                AppLoggers.dashboard.info("Session-rerun: \(updated, privacy: .public) record(s) reclassified")
            }
        } catch {
            AppLoggers.dashboard.error("Session-rerun failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Epic 40: filter the last 10 Strava records (id not UUID-parseable) without
    /// 5s samples in DB and fetch their streams. Async, scenePhase-triggered.
    private func backfillStravaStreams() async {
        let store = WorkoutSampleStore(modelContainer: modelContext.container)
        let ingest = StravaStreamIngestService()
        let api = FitnessDataService()

        let candidates = activities
            .filter { UUID(uuidString: $0.id) == nil }       // Strava only
            .sorted { $0.startDate > $1.startDate }
            .prefix(10)

        for activity in candidates {
            let workoutUUID = UUID.deterministic(fromStravaID: activity.id)
            let existingCount = (try? await store.sampleCount(forWorkoutUUID: workoutUUID)) ?? 0
            guard existingCount == 0 else { continue }

            guard let stravaID = Int64(activity.id) else { continue }
            do {
                let streams = try await api.fetchActivityStreams(for: stravaID)
                try await ingest.ingestStreams(
                    streams,
                    activityID: activity.id,
                    startDate: activity.startDate,
                    durationSeconds: activity.movingTime,
                    into: store
                )
            } catch {
                // One error (404, 429 rate-limit, decode failure) does not block the batch.
                AppLoggers.dashboard.warning("Strava-stream backfill failed for activity \(activity.id, privacy: .private): \(error.localizedDescription, privacy: .public)")
            }
            // 100ms throttle — Strava's rate limit is 100 req/15min; for 10 calls
            // we have ample time, the throttle is deliberately cautious + cooperative cancel.
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Epic 18: Save a symptom score for today (upsert per body area per day).
    private func saveOrUpdateSymptom(area: BodyArea, severity: Int) {
        let todayStart = Calendar.current.startOfDay(for: Date())
        // Find existing record for today and this body area
        if let existing = symptoms.first(where: { $0.bodyArea == area && $0.date >= todayStart }) {
            existing.severity = severity
        } else {
            modelContext.insert(Symptom(bodyArea: area, severity: severity))
        }
        try? modelContext.save()
        // Update the AI cache immediately with the latest scores and active preferences
        viewModel.cacheSymptomContext(Array(symptoms), preferences: Array(activePreferences))
        // Mark the CoachInsight as stale — the scores changed after the last analysis
        symptomChangedSinceAnalysis = true
    }

    /// Fetches HealthKit data and saves a DailyReadiness record for today.
    /// Uses a 5 second time-out; if there is no data the card is set to 'unavailable'.
    @MainActor
    private func calculateAndSaveVibeScore() async {
        isVibeScoreLoading = true
        isVibeScoreUnavailable = false
        defer { isVibeScoreLoading = false }

        AppLoggers.dashboard.debug("Vibe Score auto-calculation started")

        let hkManager = HealthKitManager()

        // Step 1 (parallel + 5s timeout): fetch sleep, stages and HRV baseline simultaneously.
        // HRV only runs in step 2 so the exact sleep window can be used as a filter.
        let step1 = await withTaskGroup(of: (Double?, Double?, SleepStages?)?.self) { group in
            group.addTask {
                async let sleepTask    = try? hkManager.fetchLastNightSleep()
                async let baselineTask = try? hkManager.fetchHRVBaseline(days: 7)
                async let stagesTask   = try? hkManager.fetchSleepStages()
                return await (sleepTask, baselineTask, stagesTask)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                AppLoggers.dashboard.notice("Vibe Score step 1 timed out after 5 seconds")
                return nil
            }
            for await result in group { group.cancelAll(); return result }
            return nil
        }

        guard let (sleep, baseline, stages) = step1,
              let sleepHours  = sleep,
              let hrvBaseline = baseline else {
            AppLoggers.dashboard.notice("Insufficient sleep/baseline data — Vibe Score set to unavailable")
            isVibeScoreUnavailable = true
            viewModel.cacheVibeScoreUnavailable()
            return
        }

        // Step 2: fetch HRV and resting heart rate in parallel.
        async let hrvTask = hkManager.fetchRecentHRV(sleepStart: stages?.sessionStart, sleepEnd: stages?.sessionEnd)
        async let restingHRTask = hkManager.fetchRestingHeartRate()
        let currentHRV: Double? = try? await hrvTask
        let restingHR: Double?  = await restingHRTask

        guard let currentHRV else {
            AppLoggers.dashboard.notice("No HRV data — Vibe Score set to unavailable")
            isVibeScoreUnavailable = true
            viewModel.cacheVibeScoreUnavailable()
            return
        }

        let score = ReadinessCalculator.calculate(
            sleepHours: sleepHours,
            hrv: currentHRV,
            hrvBaseline: hrvBaseline,
            deepSleepRatio: stages?.deepRatio
        )

        let stagesLog = stages.map { "diep: \($0.deepMinutes)m, REM: \($0.remMinutes)m, kern: \($0.coreMinutes)m, ratio: \(String(format: "%.0f%%", $0.deepRatio * 100))" } ?? "geen stage-data"
        // HRV/sleep are §11 .private PHI; the score itself is non-identifying.
        AppLoggers.dashboard.debug("Vibe Score \(score, privacy: .public)/100 (sleep: \(sleepHours, privacy: .private)h, HRV: \(currentHRV, privacy: .private)ms, \(stagesLog, privacy: .private))")

        // Upsert: overwrite an existing record for today or create a new one
        let todayStart   = Calendar.current.startOfDay(for: Date())
        let tomorrowStart = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!
        let descriptor   = FetchDescriptor<DailyReadiness>(
            predicate: #Predicate { $0.date >= todayStart && $0.date < tomorrowStart }
        )
        if let existing = try? modelContext.fetch(descriptor), let record = existing.first {
            record.sleepHours       = sleepHours
            record.hrv              = currentHRV
            record.readinessScore   = score
            record.deepSleepMinutes = stages?.deepMinutes  ?? 0
            record.remSleepMinutes  = stages?.remMinutes   ?? 0
            record.coreSleepMinutes = stages?.coreMinutes  ?? 0
            record.restingHeartRate = restingHR
        } else {
            modelContext.insert(DailyReadiness(
                date: Date(),
                sleepHours: sleepHours,
                hrv: currentHRV,
                readinessScore: score,
                deepSleepMinutes: stages?.deepMinutes  ?? 0,
                remSleepMinutes: stages?.remMinutes   ?? 0,
                coreSleepMinutes: stages?.coreMinutes  ?? 0,
                restingHeartRate: restingHR
            ))
        }
        try? modelContext.save()

        // Update the AI cache with the newly calculated score
        viewModel.cacheVibeScore(todayReadiness)
    }
}

// MARK: - Epic 38 Story 38.2: HealthKitPermissionWarningBanner

/// "Silent sync" banner: appears when the last HK sync yielded 0 workouts
/// and the workout permission is not explicitly `.sharingAuthorized`.
/// Prevents the user from walking around for days with an empty dashboard without
/// knowing it is due to HealthKit permissions. A pure-Swift logic call
/// to `HealthKitSyncStatusEvaluator` keeps the decision testable without an
/// `HKHealthStore` mock.
struct HealthKitPermissionWarningBanner: View {
    /// Cache from `AppTabHostView.runHealthKitAutoSync` / `SettingsView` historical sync.
    /// `-1` = sentinel "never synced yet" → no banner (avoids a false positive on the
    /// very first app launch before the first auto-sync cycle).
    @AppStorage("vibecoach_lastHKWorkoutsCount") private var lastHKWorkoutsCount: Int = -1
    @State private var workoutAuthStatus: HKAuthorizationStatus = .notDetermined

    private var shouldShow: Bool {
        lastHKWorkoutsCount >= 0 &&
            HealthKitSyncStatusEvaluator.shouldWarn(
                workoutCount: lastHKWorkoutsCount,
                workoutAuthStatus: workoutAuthStatus)
    }

    var body: some View {
        Group {
            if shouldShow {
                DashboardBannerView(icon: "exclamationmark.icloud", color: .red) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Geen HealthKit-data gevonden")
                            .font(.subheadline.bold())
                        Text("Controleer of de app toestemming heeft voor Workouts en Hartslag — anders blijft het Dashboard leeg.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Open Instellingen")
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .onAppear {
            workoutAuthStatus = HealthKitManager.shared.healthStore.authorizationStatus(for: .workoutType())
        }
    }
}

// MARK: - V2.0: DashboardBannerView

/// Reusable card banner for ACWR warnings and informational messages.
struct DashboardBannerView<Content: View>: View {
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .padding(.top, 1)
            content()
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - Sprint 17.3: Milestone Progress Card

/// Card that visually displays the success criteria of the PeriodizationEngine
/// with progress bars per goal. Makes the 'why' behind the schedule clear.
struct MilestoneProgressCard: View {
    let results: [PeriodizationResult]

    var body: some View {
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "checklist")
                        .foregroundColor(.primary)
                    Text("Fase-Mijlpalen")
                        .font(.headline)
                }

                ForEach(results, id: \.goal.id) { result in
                    GoalMilestonesSection(result: result)
                    if result.goal.id != results.last?.goal.id {
                        Divider()
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

private struct GoalMilestonesSection: View {
    let result: PeriodizationResult
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.goal.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer()
                Text(result.phase.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(themeManager.primaryAccentColor.opacity(0.15))
                    .foregroundStyle(themeManager.primaryAccentColor)
                    .cornerRadius(4)
            }

            ForEach(result.milestoneItems, id: \.label) { item in
                MilestoneProgressRow(item: item)
            }
        }
    }
}

private struct MilestoneProgressRow: View {
    let item: PeriodizationResult.MilestoneItem

    private var accentColor: Color { item.isMet ? .green : .orange }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: item.isMet ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(accentColor)
                    .font(.caption)
                Text(item.label)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(progressText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemFill))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(accentColor)
                        .frame(width: geo.size.width * item.progress, height: 6)
                        .animation(.easeInOut(duration: 0.4), value: item.progress)
                }
            }
            .frame(height: 6)
            Text(item.detail)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var progressText: String {
        if item.label.contains("belasting") {
            return String(format: "%.0f / %.0f TRIMP", item.current, item.required)
        }
        return String(format: "%.1f / %.1f km", item.current, item.required)
    }
}

// MARK: - Epic 18: Symptom Check-in Card

/// Daily pain score card. Only appears if the user has active injuries
/// (detected via UserPreference texts). Manages one score (0-10) per body area.
struct SymptomCheckinCard: View {
    let areas: [BodyArea]
    let todaySymptoms: [Symptom]
    let onSave: (BodyArea, Int) -> Void
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "stethoscope")
                    .foregroundStyle(themeManager.primaryAccentColor)
                Text("Hoe voelen je klachten vandaag?")
                    .font(.headline)
            }

            ForEach(areas, id: \.rawValue) { area in
                SymptomAreaRow(
                    area: area,
                    currentSeverity: todaySymptoms.first(where: { $0.bodyArea == area })?.severity ?? 0,
                    onSave: { severity in onSave(area, severity) }
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

private struct SymptomAreaRow: View {
    let area: BodyArea
    let currentSeverity: Int
    let onSave: (Int) -> Void

    @State private var severity: Int
    @EnvironmentObject var themeManager: ThemeManager

    init(area: BodyArea, currentSeverity: Int, onSave: @escaping (Int) -> Void) {
        self.area = area
        self.currentSeverity = currentSeverity
        self.onSave = onSave
        self._severity = State(initialValue: currentSeverity)
    }

    private var severityColor: Color {
        switch severity {
        case 0:     return themeManager.primaryAccentColor
        case 1...3: return themeManager.primaryAccentColor
        case 4...6: return Color(red: 0.88, green: 0.58, blue: 0.32)
        default:    return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: area.icon)
                    .foregroundColor(severityColor)
                    .frame(width: 20)
                // Epic #37 story 37.4: BodyArea.rawValue / severityLabel stay Dutch (rawValue is
                // the SwiftData storage value; severityLabel feeds the coach prompt). The UI
                // resolves both via the catalog.
                Text(LocalizedStringKey(area.rawValue))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(severity)/10 — \(String(localized: String.LocalizationValue(BodyArea.severityLabel(severity))))")
                    .font(.caption)
                    .foregroundColor(severityColor)
                    .monospacedDigit()
            }
            // Compact +/- buttons (0-10, step 1)
            HStack(spacing: 8) {
                Button {
                    if severity > 0 {
                        severity -= 1
                        onSave(severity)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(severity > 0 ? .primary : .secondary)
                }
                .disabled(severity == 0)

                // Visual pain bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemFill))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(severityColor)
                            .frame(width: severity == 0 ? 0 : geo.size.width * CGFloat(severity) / 10.0, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: severity)
                    }
                }
                .frame(height: 8)

                Button {
                    if severity < 10 {
                        severity += 1
                        onSave(severity)
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(severity < 10 ? .primary : .secondary)
                }
                .disabled(severity == 10)
            }
        }
        .onChange(of: currentSeverity) { _, newValue in
            // Synchronize if the value changes externally (e.g. SwiftData refresh)
            if severity != newValue { severity = newValue }
        }
    }
}
