import SwiftUI
import SwiftData

// MARK: - GoalsListView

/// De 'Doelen' tab — het lange-termijn analysecentrum van de app.
/// Bevat: herstelplan-banners, Blueprint voortgang, Progressie & Prognoses grafiek,
/// Mijlpalen per fase en de doelen-lijst.
struct GoalsListView: View {
    @ObservedObject var viewModel: ChatViewModel

    @EnvironmentObject var appState: AppNavigationState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FitnessGoal.targetDate, order: .forward) private var goals: [FitnessGoal]
    @Query(sort: \ActivityRecord.startDate, order: .forward) private var activities: [ActivityRecord]
    @Query(filter: #Predicate<UserPreference> { $0.isActive == true }, sort: \UserPreference.createdAt) private var activePreferences: [UserPreference]

    @State private var showingAddSheet = false

    // Herstelplan tijdstip — gedeeld met DashboardView via AppStorage
    @AppStorage("vibecoach_recoveryPlanTimestamp") private var recoveryPlanTimestamp: Double = 0

    // MARK: - Computed properties

    private var uncompletedGoals: [FitnessGoal] {
        goals.filter { !$0.isCompleted }
    }

    private var gapAnalysis: [BlueprintGap] {
        ProgressService.analyzeGaps(for: Array(goals), activities: Array(activities))
    }

    private var projections: [GoalProjection] {
        FutureProjectionService.calculateProjections(for: Array(goals), activities: Array(activities))
    }

    private var periodizationResults: [PeriodizationResult] {
        PeriodizationEngine.evaluateAllGoals(Array(goals), activities: Array(activities))
    }

    /// True als er een actief herstelplan is dat minder dan 3 dagen geleden werd aangevraagd.
    private var hasActiveRecoveryPlan: Bool {
        guard recoveryPlanTimestamp > 0 else { return false }
        let planDate = Date(timeIntervalSince1970: recoveryPlanTimestamp)
        return Date().timeIntervalSince(planDate) < 3 * 24 * 3600
    }

    /// Doelen die achterlopen op de fase-gecorrigeerde burndown (zelfde logica als DashboardView).
    private var atRiskGoals: [DashboardView.GoalRiskStatus] {
        let now = Date()
        let calendar = Calendar.current
        let twoWeeksAgo   = calendar.date(byAdding: .day,      value: -14, to: now) ?? now
        let blockStart    = calendar.date(byAdding: .weekOfYear, value: -16, to: now) ?? now

        return goals.compactMap { goal in
            guard !goal.isCompleted, now < goal.targetDate else { return nil }

            let targetTRIMP    = goal.computedTargetTRIMP
            let weeksRemaining = max(0.1, goal.targetDate.timeIntervalSince(now) / (7 * 86400))
            let phase          = goal.currentPhase ?? .baseBuilding

            let relevantActivities = activities.filter { record in
                guard record.startDate >= blockStart && record.startDate <= now else { return false }
                guard let goalCategory = goal.sportCategory else { return true }
                if goalCategory == .triathlon {
                    return [.running, .cycling, .swimming, .triathlon].contains(record.sportCategory)
                }
                return record.sportCategory == goalCategory
            }

            let achievedTRIMP = relevantActivities.compactMap { $0.trimp }.reduce(0, +)
            let currentRemaining = max(0, targetTRIMP - achievedTRIMP)
            guard currentRemaining > 0 else { return nil }

            let recentTRIMP    = relevantActivities.filter { $0.startDate >= twoWeeksAgo }.compactMap { $0.trimp }.reduce(0, +)
            let currentBurnRate = recentTRIMP / 2.0
            let linearRate      = currentRemaining / weeksRemaining
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
            List {

                // MARK: Herstelplan banners (verplaatst van Dashboard)
                if !atRiskGoals.isEmpty {
                    Section {
                        if hasActiveRecoveryPlan {
                            RecoveryPlanActiveBannerView {
                                // "Bekijk herstelplan" → Coach tab
                                appState.selectedTab = .coach
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        } else {
                            ProactiveWarningBannerView(
                                atRiskGoals: atRiskGoals,
                                onCoachTapped: {
                                    appState.selectedTab = .coach
                                },
                                onRecoveryPlanTapped: {
                                    // Bouw recovery context en vraag AI om herstelplan
                                    let riskInfos = atRiskGoals.map { status in
                                        let weeksRemaining = max(0.1, status.goal.targetDate.timeIntervalSince(Date()) / (7 * 86400))
                                        return ChatViewModel.GoalRiskInfo(
                                            title: status.goal.title,
                                            currentWeeklyRate: status.currentWeeklyRate,
                                            requiredWeeklyRate: status.requiredWeeklyRate,
                                            weeksRemaining: weeksRemaining
                                        )
                                    }
                                    viewModel.requestRecoveryPlan(
                                        atRiskGoals: riskInfos,
                                        contextProfile: nil,
                                        activeGoals: Array(goals),
                                        activePreferences: Array(activePreferences)
                                    )
                                    recoveryPlanTimestamp = Date().timeIntervalSince1970
                                    appState.selectedTab = .coach
                                }
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }
                    }
                }

                // MARK: Sprint 23.3 — Visual Progress Hub (bovenaan, prominent)
                // De tijdlijn toont de volledige reis: Ideaal / Actueel / Prognose
                Section {
                    BlueprintTimelineSectionView(
                        goals: uncompletedGoals,
                        activities: Array(activities),
                        projections: projections
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                // MARK: Blueprint voortgang (Gap Analysis — fase-cumulatief)
                if !gapAnalysis.isEmpty {
                    Section {
                        GapAnalysisSectionView(gaps: gapAnalysis, projections: projections)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                // MARK: Mijlpalen per fase (verplaatst van Dashboard)
                if !periodizationResults.isEmpty {
                    Section {
                        MilestoneProgressCard(results: periodizationResults)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                // MARK: Progressie & Burndown (resterende TRIMP richting nul)
                if !uncompletedGoals.isEmpty {
                    Section {
                        BurndownChartView(goals: uncompletedGoals, activities: Array(activities))
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                // MARK: Doelen lijst
                Section("Mijn Doelen") {
                    if goals.isEmpty {
                        ContentUnavailableView(
                            "Geen doelen",
                            systemImage: "target",
                            description: Text("Voeg een nieuw fitnessdoel toe om je voortgang bij te houden.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(goals) { goal in
                            NavigationLink {
                                EditGoalView(goal: goal)
                            } label: {
                                GoalRowView(goal: goal)
                            }
                        }
                        .onDelete(perform: deleteGoals)
                    }
                }
            }
            .navigationTitle("Doelen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("AddGoalButton")
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddGoalView()
                    .environment(\.modelContext, modelContext)
            }
        }
    }

    private func deleteGoals(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(goals[index])
            }
            try? modelContext.save()
        }
    }
}

// MARK: - GoalRowView

struct GoalRowView: View {
    let goal: FitnessGoal

    var daysRemaining: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: goal.targetDate).day ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(goal.title)
                    .font(.headline)
                    .strikethrough(goal.isCompleted, color: .secondary)
                    .foregroundColor(goal.isCompleted ? .secondary : .primary)

                Spacer()

                if goal.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if daysRemaining >= 0 {
                    Text("\(daysRemaining) dagen")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                } else {
                    Text("Verlopen")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 6) {
                if let phase = goal.currentPhase {
                    let phaseColor: Color = {
                        switch phase {
                        case .baseBuilding: return .blue
                        case .buildPhase:   return .orange
                        case .peakPhase:    return .red
                        case .tapering:     return .purple
                        }
                    }()
                    Text(phase.displayName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(phaseColor.opacity(0.12))
                        .foregroundColor(phaseColor)
                        .clipShape(Capsule())
                }

                if let sport = goal.sportCategory?.displayName, !sport.isEmpty {
                    Text(sport)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }
            }

            Text(goal.targetDate, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
