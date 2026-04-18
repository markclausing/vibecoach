import SwiftUI
import SwiftData

// MARK: - GoalsListView

/// De 'Doelen' tab — goal-centric layout.
/// Elk actief doel met een blueprint krijgt een eigen `GoalDetailContainer`
/// die alle analyse in logische volgorde groepeert.
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
            List {

                // MARK: Goal-Centric containers — één per actief doel met blueprint
                ForEach(uncompletedGoals) { goal in
                    let gap          = gapAnalysis.first { $0.goal.id == goal.id }
                    let projection   = projections.first { $0.goal.id == goal.id }
                    let periResult   = periodizationResults.first { $0.goal.id == goal.id }
                    let riskStatus   = atRiskGoals.first { $0.goal.id == goal.id }

                    Section {
                        GoalDetailContainer(
                            goal: goal,
                            activities: Array(activities),
                            gap: gap,
                            projection: projection,
                            periodizationResult: periResult,
                            riskStatus: riskStatus,
                            hasActiveRecoveryPlan: hasActiveRecoveryPlan,
                            onRecoveryPlanTapped: {
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
                            },
                            onCoachTapped: {
                                appState.selectedTab = .coach
                            }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                // MARK: Doelen lijst — navigatie naar EditGoalView
                Section(header:
                    Text("Mijn Doelen")
                        .font(themeManager.scaledHeadingFont())
                        .scaleEffect(themeManager.headingSizeMultiplier, anchor: .leading)
                ) {
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
                            // Sprint 26.1: unieke identifier per rij zodat XCUITest
                            // de NavigationLink cel vindt, niet de GoalDetailContainer-tekst.
                            .accessibilityIdentifier("GoalRow_\(goal.title)")
                        }
                        .onDelete(perform: deleteGoals)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(themeManager.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Doelen")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddSheet = true } label: {
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
            for index in offsets { modelContext.delete(goals[index]) }
            try? modelContext.save()
        }
    }
}

// MARK: - GoalDetailContainer

/// Overkoepelende container die het complete verhaal van één doel vertelt.
/// Groepeert alle analyses in een vaste logische volgorde:
///   1. Header  — naam, fase, countdown
///   2. Huidige Fase & Mijlpalen
///   3. Blueprint Voortgang (Gap Analysis)
///   4. Prognose & Tijdlijn
///   5. Herstelplan (optioneel — alleen als dit doel at-risk is)
struct GoalDetailContainer: View {
    let goal: FitnessGoal
    let activities: [ActivityRecord]

    // Optionele analyseclusters — nil als er geen blueprint-match is
    let gap:                 BlueprintGap?
    let projection:          GoalProjection?
    let periodizationResult: PeriodizationResult?
    let riskStatus:          DashboardView.GoalRiskStatus?
    let hasActiveRecoveryPlan: Bool

    var onRecoveryPlanTapped: () -> Void
    var onCoachTapped: () -> Void

    private var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: goal.targetDate).day ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── 1. GOAL HEADER ────────────────────────────────────────────
            goalHeader
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider().padding(.horizontal)

            // ── 2. HUIDIGE FASE & MIJLPALEN ───────────────────────────────
            if let result = periodizationResult {
                sectionBlock(
                    icon: "checklist",
                    title: "Huidige Fase & Mijlpalen",
                    subtitle: "Wat je deze fase moet bereiken.",
                    iconColor: .accentColor
                ) {
                    GoalMilestonesSectionEmbed(result: result)
                }
            }

            // ── 3. BLUEPRINT VOORTGANG ────────────────────────────────────
            if let gap {
                sectionBlock(
                    icon: "chart.bar.xaxis",
                    title: "Blueprint Voortgang",
                    subtitle: "Loop je achter op je schema?",
                    iconColor: .blue
                ) {
                    // Hergebruik de bestaande GapAnalysisCardView in embedded-modus:
                    // geen eigen header/achtergrond, geen prognose-sectie (staat hieronder).
                    GapAnalysisCardView(gap: gap, projection: nil, isEmbedded: true)
                }
            }

            // ── 4. PROGNOSE & TIJDLIJN ────────────────────────────────────
            sectionBlock(
                icon: "crystal.ball.fill",
                title: "Prognose & Tijdlijn",
                subtitle: "Wanneer bereik je de piekbelasting?",
                iconColor: .purple
            ) {
                VStack(spacing: 12) {
                    // Datum-badge (uit Sprint 23.2) bovenaan het blok
                    if let proj = projection {
                        projectionSummaryBadge(proj)
                    }
                    // Tijdlijn-grafiek (Sprint 23.3)
                    BlueprintTimelineView(
                        goal: goal,
                        activities: activities,
                        projection: projection
                    )
                }
            }

            // ── 5. HERSTELPLAN (optioneel) ────────────────────────────────
            if let riskStatus {
                sectionBlock(
                    icon: "cross.circle.fill",
                    title: "Herstelplan",
                    subtitle: nil,
                    iconColor: .red
                ) {
                    if hasActiveRecoveryPlan {
                        RecoveryPlanActiveBannerView(onCoachTapped: onCoachTapped)
                    } else {
                        inlineRiskBanner(riskStatus)
                    }
                }
            }

            Spacer(minLength: 16)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Sub-views

    private var goalHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)

                if let phase = goal.currentPhase {
                    phaseBadge(phase)
                }
            }
            Spacer()
            // Countdown-badge
            VStack(alignment: .center, spacing: 1) {
                Text("\(daysRemaining)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text("dagen")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func phaseBadge(_ phase: TrainingPhase) -> some View {
        let color: Color = {
            switch phase {
            case .baseBuilding: return .blue
            case .buildPhase:   return .orange
            case .peakPhase:    return .red
            case .tapering:     return .purple
            }
        }()
        return Text(phase.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    /// Generiek sectieblok met kopje, ondertitel en vrije content.
    @ViewBuilder
    private func sectionBlock<Content: View>(
        icon: String,
        title: String,
        subtitle: String?,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Sectie-header
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(iconColor)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
                if let sub = subtitle {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(.horizontal)
        .padding(.vertical, 14)

        Divider().padding(.horizontal)
    }

    /// Compacte samenvatting van de projectiestatus — toont ook de bottleneck-metric.
    private func projectionSummaryBadge(_ proj: GoalProjection) -> some View {
        let df = DateFormatter()
        df.dateFormat = "d MMM yyyy"
        df.locale = Locale(identifier: "nl_NL")

        let plannedStr  = df.string(from: proj.plannedPeakDate)
        let color       = statusColor(proj.status)

        return VStack(alignment: .leading, spacing: 6) {
            // Statusrij
            HStack(spacing: 10) {
                Image(systemName: proj.status.icon)
                    .font(.title3)
                    .foregroundStyle(color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(proj.status.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                    HStack(spacing: 4) {
                        Text("Gepland:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(plannedStr)
                            .font(.caption2.weight(.medium))

                        if let projDate = proj.projectedPeakDate {
                            Text("· Verwacht:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(df.string(from: projDate))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(color)
                        }
                    }
                }
                Spacer()
            }

            // Bottleneck-label (alleen tonen als er een achterstand is)
            if proj.bottleneck == .km || proj.bottleneck == .both {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text(bottleneckLabel(proj))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func bottleneckLabel(_ proj: GoalProjection) -> String {
        let kmStr = String(format: "%.1f", proj.currentWeeklyKm)
        let reqStr = String(format: "%.1f", proj.requiredPeakKm)
        let sportLabel: String
        switch proj.blueprintType {
        case .marathon, .halfMarathon: sportLabel = "hardloop-km"
        case .cyclingTour:             sportLabel = "fiets-km"
        }
        if proj.hasCrossTrainingBonus {
            return "Bottleneck: \(sportLabel) \(kmStr)/\(reqStr) km/week. "
                + "Omdat je aerobe basis (TRIMP) sterk is, kunnen we dit gat sneller dichten zodra je hersteld bent."
        } else {
            return "Bottleneck: \(sportLabel) \(kmStr)/\(reqStr) km/week — TRIMP van andere sporten telt hier niet mee."
        }
    }

    private func statusColor(_ status: ProjectionStatus) -> Color {
        switch status {
        case .alreadyPeaking, .onTrack:    return .green
        case .atRisk, .catchUpNeeded:      return .orange
        case .unreachable:                 return .red
        }
    }

    /// Inline risicomelding als herstelplan nog niet aangevraagd is.
    private func inlineRiskBanner(_ risk: DashboardView.GoalRiskStatus) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 6) {
                Text(risk.isTaperingOverload
                     ? "Te intensief in taperingsfase"
                     : "Volume achter op schema")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(String(format: "Huidig: %.0f TRIMP/week · Nodig: %.0f TRIMP/week",
                            risk.currentWeeklyRate, risk.requiredWeeklyRate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    onRecoveryPlanTapped()
                } label: {
                    Label("Vraag herstelplan aan", systemImage: "wand.and.stars")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - GoalMilestonesSectionEmbed

/// Insluitbare versie van GoalMilestonesSection (zonder doeltitel — container heeft al header).
struct GoalMilestonesSectionEmbed: View {
    let result: PeriodizationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(result.milestoneItems, id: \.label) { item in
                MilestoneProgressRowEmbed(item: item)
            }
        }
    }
}

private struct MilestoneProgressRowEmbed: View {
    let item: PeriodizationResult.MilestoneItem
    private var accentColor: Color { item.isMet ? .green : .orange }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: item.isMet ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(accentColor)
                    .font(.caption)
                Text(item.label)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(progressText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
        }
    }

    private var progressText: String {
        if item.label.contains("belasting") {
            return String(format: "%.0f / %.0f TRIMP", item.current, item.required)
        }
        return String(format: "%.1f / %.1f km", item.current, item.required)
    }
}

// MARK: - GoalRowView

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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(themeManager.primaryAccentColor.opacity(0.1))
                        .foregroundStyle(themeManager.primaryAccentColor)
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
        // Sprint 26.1: contentShape zorgt dat XCUITest de volledige rij als hittable
        // beschouwt, ook transparante ruimtes tussen tekstvelden.
        .contentShape(Rectangle())
    }
}
