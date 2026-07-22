import SwiftUI
import SwiftData

// MARK: - GoalsListView

struct GoalsListView: View {
    @ObservedObject var viewModel: ChatViewModel

    @EnvironmentObject var appState: AppNavigationState
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FitnessGoal.targetDate, order: .forward) private var goals: [FitnessGoal]
    // Epic #65 story 65.2: bounded to the rolling `QueryWindows.activityHistory` window
    // (26 weeks). Widest consumer here is `atRiskGoals`'s 16-week burndown block; the
    // `ProgressService` / `PeriodizationEngine` helpers scan ≤ that. Cutoff set in init.
    @Query private var activities: [ActivityRecord]
    @Query(filter: #Predicate<UserPreference> { $0.isActive == true }, sort: \UserPreference.createdAt) private var activePreferences: [UserPreference]

    /// Epic #70: facts from the per-workout chats → the [WORKOUT NOTES] block in the
    /// recovery-plan invocation (window/cap policy lives in the formatter).
    @Query(sort: \WorkoutChatFact.createdAt, order: .reverse) private var workoutChatFacts: [WorkoutChatFact]

    /// Epic #65 story 65.2: Calendar-based (§3) cutoff captured as a `let` for the `#Predicate`.
    init(viewModel: ChatViewModel) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        let cutoff = QueryWindows.activityHistoryCutoff()
        _activities = Query(
            filter: #Predicate<ActivityRecord> { $0.startDate >= cutoff },
            sort: \ActivityRecord.startDate,
            order: .forward
        )
    }

    @State private var showingAddSheet = false
    @AppStorage("vibecoach_recoveryPlanTimestamp") private var recoveryPlanTimestamp: Double = 0

    // Epic 34.1: scroll state for the material overlay under the status bar.
    @State private var isGoalsScrolled: Bool = false

    // MARK: - Computed

    private var uncompletedGoals: [FitnessGoal] {
        goals.filter { !$0.isCompleted }
    }

    private var completedGoals: [FitnessGoal] {
        goals.filter { $0.isCompleted }
    }

    private var gapAnalysis: [BlueprintGap] {
        ProgressService.analyzeGaps(for: Array(goals), activities: Array(activities))
    }

    private var periodizationResults: [PeriodizationResult] {
        PeriodizationEngine.evaluateAllGoals(Array(goals), activities: Array(activities))
    }

    private var hasActiveRecoveryPlan: Bool {
        guard recoveryPlanTimestamp > 0 else { return false }
        let planDate = Date(timeIntervalSince1970: recoveryPlanTimestamp)
        // CLAUDE.md §3: calendar-based instead of `3 * 24 * 3600` so DST does not cause a 1h drift.
        return Calendar.current.fractionalDays(from: planDate, to: Date()) < 3.0
    }

    private var atRiskGoals: [DashboardView.GoalRiskStatus] {
        let now = Date()
        let calendar = Calendar.current
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let blockStart  = calendar.date(byAdding: .weekOfYear, value: -16, to: now) ?? now

        return goals.compactMap { goal in
            guard !goal.isCompleted, now < goal.targetDate else { return nil }

            let targetTRIMP    = goal.computedTargetTRIMP
            let weeksRemaining = max(0.1, goal.weeksRemaining(from: now))
            let phase          = goal.currentPhase ?? .baseBuilding

            let relevantActivities = activities.filter { record in
                guard record.startDate >= blockStart && record.startDate <= now else { return false }
                guard let goalCategory = goal.sportCategory else { return true }
                if goalCategory == .triathlon {
                    return [.running, .cycling, .swimming, .triathlon].contains(record.sportCategory)
                }
                return record.sportCategory == goalCategory
            }

            let achievedTRIMP    = relevantActivities.compactMap { $0.trimp }.reduce(0, +)
            let currentRemaining = max(0, targetTRIMP - achievedTRIMP)
            guard currentRemaining > 0 else { return nil }

            let recentTRIMP      = relevantActivities.filter { $0.startDate >= twoWeeksAgo }.compactMap { $0.trimp }.reduce(0, +)
            let currentBurnRate  = recentTRIMP / 2.0
            let linearRate       = currentRemaining / weeksRemaining
            let adjustedRequired = linearRate * phase.multiplier

            if phase == .tapering && currentBurnRate > adjustedRequired * 1.10 {
                return DashboardView.GoalRiskStatus(goal: goal, currentWeeklyRate: currentBurnRate, requiredWeeklyRate: adjustedRequired, isTaperingOverload: true)
            }
            guard currentBurnRate < adjustedRequired * 0.75 else { return nil }
            return DashboardView.GoalRiskStatus(goal: goal, currentWeeklyRate: currentBurnRate, requiredWeeklyRate: adjustedRequired, isTaperingOverload: false)
        }
        .sorted { ($0.requiredWeeklyRate - $0.currentWeeklyRate) > ($1.requiredWeeklyRate - $1.currentWeeklyRate) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    goalsHeader
                        .padding(.bottom, 20)

                    if uncompletedGoals.isEmpty {
                        emptyStateCard
                            .padding(.horizontal)
                    } else {
                        ForEach(uncompletedGoals) { goal in
                            NavigationLink(value: goal) {
                                activeGoalCard(goal)
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 24)
                        }
                        if !completedGoals.isEmpty {
                            alternativeGoalsSection
                        }
                    }

                    Spacer(minLength: 40)
                }
            }
            .accessibilityIdentifier("GoalsScrollView")
            .navigationDestination(for: FitnessGoal.self) { goal in
                // Epic #62 story 62.1: clear the goal-derived coach context on delete so the
                // coach stops referencing a goal that no longer exists.
                EditGoalView(goal: goal, onDeleted: { viewModel.context.clearGoalDerivedContext() })
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > 4
            } action: { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isGoalsScrolled = newValue
                }
            }
            .background(Color(.secondarySystemBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .scrollEdgeMaterial(isActive: isGoalsScrolled)
            .sheet(isPresented: $showingAddSheet) {
                AddGoalView()
                    .environment(\.modelContext, modelContext)
            }
        }
    }

    // MARK: - Header

    private var goalsHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                let activeCount = uncompletedGoals.count
                let cmpCount    = completedGoals.count
                // Epic #37: localized via the catalog. Counts pre-formatted as String (-> %@ key);
                // the Dutch singular/plural suffix logic is dropped — these uppercase counter
                // labels read fine in the plural form across languages.
                let activeStr = "\(activeCount)"
                let cmpStr    = "\(cmpCount)"
                Text(activeCount == 0
                     ? String(localized: "GEEN DOELEN")
                     : String(localized: "\(activeStr) ACTIEVE • \(cmpStr) VOLTOOIDE"))
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.secondary).kerning(0.5)
                Spacer()
                Button { showingAddSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color(.systemBackground))
                        .clipShape(Circle())
                }
                .accessibilityIdentifier("AddGoalButton")
            }
            Text("Doelen")
                .font(.largeTitle).fontWeight(.bold)
        }
        .padding(.horizontal)
        .padding(.top, 56)
    }

    // MARK: - Active Goal Card

    @ViewBuilder
    private func activeGoalCard(_ goal: FitnessGoal) -> some View {
        let gap        = gapAnalysis.first { $0.goal.id == goal.id }
        let periResult = periodizationResults.first { $0.goal.id == goal.id }
        let riskStatus = atRiskGoals.first { $0.goal.id == goal.id }
        let daysLeft   = max(0, Calendar.current.dateComponents([.day], from: Date(), to: goal.targetDate).day ?? 0)
        // Epic #60: single timeline instance, reused by the verdict mapping AND the milestones
        // list below (previously computed twice implicitly).
        let timeline   = ProgressService.phaseTimeline(for: goal, activities: Array(activities))

        VStack(spacing: 0) {
            GoalHeroCard(
                goal: goal,
                gap: gap,
                verdict: verdict(for: goal, gap: gap, timeline: timeline, risk: riskStatus),
                daysLeft: daysLeft
            )

            // ── Warning (at risk) — §1: a red status always ships with an action.
            if let risk = riskStatus {
                Divider()
                GoalWarningCard(
                    risk: risk,
                    onAdjustPlan: { requestRecoveryPlan() },
                    onDetails: { appState.selectedTab = .coach }
                )
            }

            // ── Progress this phase
            if let gap {
                Divider()
                GoalProgressSection(gap: gap, periResult: periResult)
            }

            // ── Milestones per phase (Epic #60: collapsible, all phases at once)
            Divider()
            PhaseMilestonesView(timeline: timeline)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.horizontal)
    }

    // MARK: - Verdict mapping (Epic #72 story 72.2)

    /// Maps this goal's gap analysis / phase timeline / risk status into the deterministic
    /// "will I make it?" verdict rendered by `GoalVerdictBanner`. Pure mapping — the actual
    /// pace logic lives in `GoalVerdictBuilder` (story 72.1).
    private func verdict(for goal: FitnessGoal, gap: BlueprintGap?, timeline: PhaseTimeline, risk: DashboardView.GoalRiskStatus?) -> GoalVerdict? {
        let achievedLabels = timeline.phases
            .first(where: { $0.status == .current })?
            .targets.filter(\.isMet).map(\.label) ?? []

        let input = GoalVerdictInput(
            phaseWeekNumber: gap?.phaseWeekNumber ?? 0,
            phaseTotalWeeks: gap?.phaseTotalWeeks ?? 0,
            trimpActual: gap?.actualTRIMPToDate ?? 0,
            trimpExpectedToDate: gap?.requiredTRIMPToDate ?? 0,
            trimpPhaseTarget: gap?.totalPhaseTRIMPTarget ?? 0,
            kmActual: gap?.actualKmToDate ?? 0,
            kmExpectedToDate: gap?.requiredKmToDate ?? 0,
            kmPhaseTarget: gap?.totalPhaseKmTarget ?? 0,
            achievedTargetLabels: achievedLabels,
            isAtRisk: risk != nil,
            isTaperingOverload: risk?.isTaperingOverload ?? false,
            riskCurrentWeeklyRate: risk?.currentWeeklyRate,
            riskRequiredWeeklyRate: risk?.requiredWeeklyRate
        )
        return GoalVerdictBuilder.build(input)
    }

    // MARK: - Alternative Goals Section

    private var alternativeGoalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VOLTOOIDE DOELEN")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.secondary).kerning(0.5)
                .padding(.horizontal)

            VStack(spacing: 8) {
                ForEach(completedGoals) { goal in
                    NavigationLink(value: goal) {
                        completedGoalRow(goal)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("GoalRow_\(goal.title)")
                }
            }
            .padding(.horizontal)
        }
    }

    private func completedGoalRow(_ goal: FitnessGoal) -> some View {
        let df = AppDateFormatters.displayStyle(.medium)

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.systemFill))
                    .frame(width: 40, height: 40)
                Image(systemName: GoalHeroCard.sportIcon(goal.sportCategory))
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(.subheadline).fontWeight(.semibold)
                    .strikethrough(true, color: .secondary)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(df.string(from: goal.targetDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color(.label).opacity(0.04), radius: 4, x: 0, y: 1)
    }

    // MARK: - Empty State

    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("Geen doelen", systemImage: "figure.outdoor.cycle")
                    .foregroundStyle(themeManager.primaryAccentColor)
            } description: {
                Text("Voeg een nieuw fitnessdoel toe om je voortgang bij te houden.")
            }
            Button { showingAddSheet = true } label: {
                Text("Doel toevoegen")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(themeManager.primaryAccentColor)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func requestRecoveryPlan() {
        let riskInfos = atRiskGoals.map { status in
            let w = max(0.1, status.goal.weeksRemaining)
            return ChatViewModel.GoalRiskInfo(
                title: status.goal.title,
                currentWeeklyRate: status.currentWeeklyRate,
                requiredWeeklyRate: status.requiredWeeklyRate,
                weeksRemaining: w
            )
        }
        viewModel.requestRecoveryPlan(
            atRiskGoals: riskInfos,
            invocation: CoachInvocationContext(
                activeGoals: Array(goals),
                activePreferences: Array(activePreferences),
                // Epic #70: subjective workout notes shape the recovery plan too.
                workoutNotesBlock: WorkoutFactsContextFormatter.format(facts: workoutChatFacts,
                                                                       activities: activities)
            )
        )
        recoveryPlanTimestamp = Date().timeIntervalSince1970
        appState.selectedTab = .coach
    }
}
