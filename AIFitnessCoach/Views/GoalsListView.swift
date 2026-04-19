import SwiftUI
import SwiftData

// MARK: - GoalsListView V2.0

struct GoalsListView: View {
    @ObservedObject var viewModel: ChatViewModel

    @EnvironmentObject var appState: AppNavigationState
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FitnessGoal.targetDate, order: .forward) private var goals: [FitnessGoal]
    @Query(sort: \ActivityRecord.startDate, order: .forward) private var activities: [ActivityRecord]
    @Query(filter: #Predicate<UserPreference> { $0.isActive == true }, sort: \UserPreference.createdAt) private var activePreferences: [UserPreference]

    @State private var showingAddSheet = false
    @AppStorage("vibecoach_recoveryPlanTimestamp") private var recoveryPlanTimestamp: Double = 0

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
        return Date().timeIntervalSince(planDate) < 3 * 24 * 3600
    }

    private var atRiskGoals: [DashboardView.GoalRiskStatus] {
        let now = Date()
        let calendar = Calendar.current
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let blockStart  = calendar.date(byAdding: .weekOfYear, value: -16, to: now) ?? now

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
                            activeGoalCard(goal)
                                .padding(.bottom, 24)
                        }
                        if !completedGoals.isEmpty {
                            alternativeGoalsSection
                        }
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(Color(.secondarySystemBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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
                Text(activeCount == 0
                     ? "GEEN DOELEN"
                     : "\(activeCount) ACTIEF\(activeCount == 1 ? "" : "E") • \(cmpCount) VOLTOOID\(cmpCount == 1 ? "" : "E")")
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

        VStack(spacing: 0) {
            // ── Top: icon + pills + countdown
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(themeManager.primaryAccentColor.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: sportIcon(goal.sportCategory))
                        .font(.system(size: 20))
                        .foregroundColor(themeManager.primaryAccentColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Actief")
                            .font(.caption2).fontWeight(.semibold)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(themeManager.primaryAccentColor.opacity(0.15))
                            .foregroundColor(themeManager.primaryAccentColor)
                            .clipShape(Capsule())
                        if gap != nil {
                            Text("Blueprint")
                                .font(.caption2).fontWeight(.medium)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color(.systemFill))
                                .foregroundColor(.secondary)
                                .clipShape(Capsule())
                        }
                    }
                    Text(goal.title)
                        .font(.title3).fontWeight(.bold)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .center, spacing: 1) {
                    Text("\(daysLeft)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("DAGEN")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary).kerning(0.5)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(16)

            // ── Phase bar
            if let phase = goal.currentPhase {
                Divider()
                phaseBarSection(goal: goal, currentPhase: phase, gap: gap)
                    .padding(16)
            }

            // ── Warning (at risk)
            if let risk = riskStatus {
                Divider()
                warningCard(risk: risk, goal: goal)
            }

            // ── Progress this phase
            if let gap = gap {
                Divider()
                progressThisPhaseSection(gap: gap, periResult: periResult, goal: goal)
            }

            // ── Milestones & prognose
            Divider()
            milestonesSection(goal: goal, periResult: periResult)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.horizontal)
    }

    // MARK: - Phase Bar

    private func phaseBarSection(goal: FitnessGoal, currentPhase: TrainingPhase, gap: BlueprintGap?) -> some View {
        let segments = phaseSegments(for: goal)
        let totalW   = max(1, segments.reduce(0) { $0 + $1.weeks })

        let weekLabel: String = {
            if let g = gap {
                return "\(currentPhase.displayName) · week \(g.phaseWeekNumber) van \(g.phaseTotalWeeks)"
            }
            return currentPhase.displayName
        }()

        let nextLabel = nextPhaseStartLabel(for: goal)

        return VStack(alignment: .leading, spacing: 8) {
            // Segmented bar
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(segments, id: \.phase.rawValue) { seg in
                        let isActive = seg.phase == currentPhase
                        let width = geo.size.width * (Double(seg.weeks) / Double(totalW))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isActive ? themeManager.primaryAccentColor : Color(.systemFill))
                            .frame(width: max(0, width - 3), height: isActive ? 8 : 5)
                            .animation(.easeInOut(duration: 0.3), value: isActive)
                    }
                }
                .frame(height: 8, alignment: .center)
            }
            .frame(height: 8)

            // Phase labels row
            HStack(spacing: 0) {
                ForEach(segments, id: \.phase.rawValue) { seg in
                    let isActive = seg.phase == currentPhase
                    let totalWD = Double(totalW)
                    Text(phaseShortLabel(seg.phase) + " \(seg.weeks)w")
                        .font(.system(size: 9, weight: isActive ? .bold : .regular))
                        .foregroundColor(isActive ? themeManager.primaryAccentColor : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Week label + next phase date
            HStack {
                Text(weekLabel)
                    .font(.caption).fontWeight(.medium)
                    .foregroundColor(.primary)
                Spacer()
                if let next = nextLabel {
                    Text(next)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Warning Card

    private func warningCard(risk: DashboardView.GoalRiskStatus, goal: FitnessGoal) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text("Bijsturing nodig")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.orange)
                Text(risk.isTaperingOverload
                     ? "Je trainingsbelasting is te hoog voor de taperingsfase."
                     : String(format: "Je trainingsbelasting is %.0f TRIMP/week — het doel is %.0f.", risk.currentWeeklyRate, risk.requiredWeeklyRate))
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 12) {
                    Button {
                        requestRecoveryPlan()
                    } label: {
                        Text("Pas plan aan")
                            .font(.caption).fontWeight(.semibold)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                    }
                    Button {
                        appState.selectedTab = .coach
                    } label: {
                        Text("Details")
                            .font(.caption).fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color.orange.opacity(0.07))
    }

    // MARK: - Progress This Phase

    private func progressThisPhaseSection(gap: BlueprintGap, periResult: PeriodizationResult?, goal: FitnessGoal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VOORTGANG DEZE FASE")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.secondary).kerning(0.5)

            // Trainingsbelasting (TRIMP)
            PhaseProgressCard(
                label: "Trainingsbelasting",
                valueCurrent: String(format: "%.0f", gap.actualTRIMPToDate),
                valueTarget: String(format: "%.0f", gap.totalPhaseTRIMPTarget),
                unit: "TRIMP",
                progress: gap.trimpProgressPct,
                reference: gap.trimpReferencePct,
                accentColor: themeManager.primaryAccentColor
            )

            // Afstand
            if gap.totalPhaseKmTarget > 0 {
                let sportLabel = gap.blueprintType == .cyclingTour ? "Afstand (wielrennen)" : "Afstand (hardlopen)"
                PhaseProgressCard(
                    label: sportLabel,
                    valueCurrent: String(format: "%.0f", gap.actualKmToDate),
                    valueTarget: String(format: "%.0f", gap.totalPhaseKmTarget),
                    unit: "km",
                    progress: gap.kmProgressPct,
                    reference: gap.kmReferencePct,
                    accentColor: themeManager.primaryAccentColor
                )
            }

            // Langste sessie
            if let session = periResult?.milestoneItems.first(where: { $0.label == "Langste sessie" }) {
                PhaseProgressCard(
                    label: "Langste sessie",
                    valueCurrent: String(format: "%.0f", session.current),
                    valueTarget: String(format: "%.0f", session.required),
                    unit: "km",
                    progress: session.progress,
                    reference: nil,
                    accentColor: themeManager.primaryAccentColor
                )
            }
        }
        .padding(16)
    }

    // MARK: - Milestones & Prognose

    private func milestonesSection(goal: FitnessGoal, periResult: PeriodizationResult?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MIJLPALEN & PROGNOSE")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.secondary).kerning(0.5)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(milestonesForGoal(goal), id: \.label) { milestone in
                    MilestoneTimelineRow(
                        item: milestone,
                        accentColor: themeManager.primaryAccentColor,
                        isLast: milestone.label == milestonesForGoal(goal).last?.label
                    )
                }
            }
        }
        .padding(16)
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
                    completedGoalRow(goal)
                        .accessibilityIdentifier("GoalRow_\(goal.title)")
                }
            }
            .padding(.horizontal)
        }
    }

    private func completedGoalRow(_ goal: FitnessGoal) -> some View {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.locale = Locale(identifier: "nl_NL")

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.systemFill))
                    .frame(width: 40, height: 40)
                Image(systemName: sportIcon(goal.sportCategory))
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
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
    }

    // MARK: - Empty State

    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.fill")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("Geen doelen")
                .font(.headline)
            Text("Voeg een nieuw fitnessdoel toe om je voortgang bij te houden.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button { showingAddSheet = true } label: {
                Text("Doel toevoegen")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(themeManager.primaryAccentColor)
                    .clipShape(Capsule())
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Helpers

    private func sportIcon(_ category: SportCategory?) -> String {
        switch category {
        case .cycling:    return "bicycle"
        case .running:    return "figure.run"
        case .swimming:   return "figure.pool.swim"
        case .triathlon:  return "medal.fill"
        case .strength:   return "dumbbell.fill"
        case .walking:    return "figure.walk"
        default:          return "flag.fill"
        }
    }

    private func phaseShortLabel(_ phase: TrainingPhase) -> String {
        switch phase {
        case .baseBuilding: return "BASE"
        case .buildPhase:   return "BUILD"
        case .peakPhase:    return "PEAK"
        case .tapering:     return "TAPER"
        }
    }

    private func phaseSegments(for goal: FitnessGoal) -> [(phase: TrainingPhase, weeks: Int)] {
        let totalWeeks = max(6, Int(goal.targetDate.timeIntervalSince(goal.createdAt) / (7 * 86400)))
        let taperW = 2
        let peakW  = 2
        let buildW = min(8, max(0, totalWeeks - 4))
        let baseW  = max(0, totalWeeks - buildW - peakW - taperW)

        var segments: [(TrainingPhase, Int)] = []
        if baseW  > 0 { segments.append((.baseBuilding, baseW))  }
        if buildW > 0 { segments.append((.buildPhase,   buildW)) }
        segments.append((.peakPhase, peakW))
        segments.append((.tapering,  taperW))
        return segments
    }

    private func nextPhaseStartLabel(for goal: FitnessGoal) -> String? {
        let df  = DateFormatter()
        df.dateFormat = "d MMM"
        df.locale = Locale(identifier: "nl_NL")
        let cal = Calendar.current

        switch goal.currentPhase {
        case .baseBuilding:
            let d = cal.date(byAdding: .weekOfYear, value: -12, to: goal.targetDate)!
            return "Build start \(df.string(from: d))"
        case .buildPhase:
            let d = cal.date(byAdding: .weekOfYear, value: -4, to: goal.targetDate)!
            return "Peak start \(df.string(from: d))"
        case .peakPhase:
            let d = cal.date(byAdding: .weekOfYear, value: -2, to: goal.targetDate)!
            return "Taper start \(df.string(from: d))"
        case .tapering, nil:
            return nil
        }
    }

    private func milestonesForGoal(_ goal: FitnessGoal) -> [GoalMilestoneItem] {
        let cal = Calendar.current
        let df  = DateFormatter()
        df.dateFormat = "d MMM"
        df.locale = Locale(identifier: "nl_NL")
        let now = Date()

        var items: [GoalMilestoneItem] = []

        let baseEnd  = cal.date(byAdding: .weekOfYear, value: -12, to: goal.targetDate)!
        let peakStart = cal.date(byAdding: .weekOfYear, value: -4,  to: goal.targetDate)!
        let taperStart = cal.date(byAdding: .weekOfYear, value: -2,  to: goal.targetDate)!

        if baseEnd > goal.createdAt {
            items.append(GoalMilestoneItem(date: df.string(from: baseEnd), label: "Base Phase afgerond", isCompleted: now >= baseEnd))
        }
        items.append(GoalMilestoneItem(date: df.string(from: peakStart),  label: "Build Phase doelen",  isCompleted: now >= peakStart))
        items.append(GoalMilestoneItem(date: df.string(from: taperStart), label: "Peak Phase bereikt",  isCompleted: now >= taperStart))
        items.append(GoalMilestoneItem(date: df.string(from: goal.targetDate), label: "Race dag 🏁",    isCompleted: now >= goal.targetDate))
        return items
    }

    private func requestRecoveryPlan() {
        let riskInfos = atRiskGoals.map { status in
            let w = max(0.1, status.goal.targetDate.timeIntervalSince(Date()) / (7 * 86400))
            return ChatViewModel.GoalRiskInfo(
                title: status.goal.title,
                currentWeeklyRate: status.currentWeeklyRate,
                requiredWeeklyRate: status.requiredWeeklyRate,
                weeksRemaining: w
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
}

// MARK: - GoalMilestoneItem

private struct GoalMilestoneItem {
    let date: String
    let label: String
    let isCompleted: Bool
}

// MARK: - MilestoneTimelineRow

private struct MilestoneTimelineRow: View {
    let item: GoalMilestoneItem
    let accentColor: Color
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(item.isCompleted ? accentColor : Color(.systemFill))
                        .frame(width: 24, height: 24)
                    if item.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Circle()
                            .stroke(Color(.systemFill), lineWidth: 2)
                            .frame(width: 24, height: 24)
                    }
                }
                if !isLast {
                    Rectangle()
                        .fill(Color(.systemFill))
                        .frame(width: 2, height: 32)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.date)
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundColor(item.isCompleted ? accentColor : .secondary)
                Text(item.label)
                    .font(.caption)
                    .foregroundColor(item.isCompleted ? .primary : .secondary)
            }
            .padding(.top, 4)

            Spacer()
        }
    }
}

// MARK: - PhaseProgressCard

private struct PhaseProgressCard: View {
    let label: String
    let valueCurrent: String
    let valueTarget: String
    let unit: String
    let progress: Double
    let reference: Double?
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.caption).fontWeight(.medium)
                    .foregroundColor(.primary)
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(valueCurrent)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("/ \(valueTarget) \(unit)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progress >= (reference ?? 0) ? accentColor : Color.orange)
                        .frame(width: geo.size.width * min(1, progress), height: 8)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                    // Ghost reference marker
                    if let ref = reference, ref > 0 {
                        Rectangle()
                            .fill(Color(.secondaryLabel).opacity(0.5))
                            .frame(width: 2, height: 12)
                            .offset(x: geo.size.width * min(1, ref) - 1)
                    }
                }
            }
            .frame(height: 8)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - GoalRowView (preserved for EditGoal navigation)

struct GoalRowView: View {
    let goal: FitnessGoal
    @EnvironmentObject var themeManager: ThemeManager

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
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(themeManager.primaryAccentColor.opacity(0.1))
                        .foregroundStyle(themeManager.primaryAccentColor)
                        .clipShape(Capsule())
                } else {
                    Text("Verlopen")
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
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
                        .font(.caption2).fontWeight(.semibold)
                        .padding(.horizontal, 7).padding(.vertical, 3)
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
        .contentShape(Rectangle())
    }
}
