import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppNavigationState
    @EnvironmentObject var planManager: TrainingPlanManager

    // We maken de ViewModel hier aan zodat we hem kunnen delen met de DashboardView
    // voor pull-to-refresh en de ChatView als overlay.
    @StateObject private var sharedChatViewModel = ChatViewModel()

    var body: some View {
        // Intercept de tab-selectie om voor ".coach" alleen de sheet te openen
        let tabBinding = Binding<AppNavigationState.Tab>(
            get: { appState.selectedTab },
            set: { newTab in
                if newTab == .coach {
                    appState.showingChatSheet = true
                } else {
                    appState.selectedTab = newTab
                }
            }
        )

        TabView(selection: tabBinding) {
            // Tab 1: Overzicht (Dashboard & Kalender)
            DashboardView(viewModel: sharedChatViewModel)
                .tabItem {
                    Label("Overzicht", systemImage: "house.fill")
                }
                .tag(AppNavigationState.Tab.dashboard)

            // Tab 2: Doelen
            GoalsListView()
                .tabItem {
                    Label("Doelen", systemImage: "target")
                }
                .tag(AppNavigationState.Tab.goals)

            // Tab 3: Coach (Centraal, opent als sheet)
            Color.clear
                .tabItem {
                    Label("Coach", systemImage: "message.fill")
                }
                .tag(AppNavigationState.Tab.coach)

            // Tab 4: Geheugen
            NavigationStack {
                PreferencesListView()
            }
            .tabItem {
                Label("Geheugen", systemImage: "brain.head.profile")
            }
            .tag(AppNavigationState.Tab.memory)

            // Tab 5: Instellingen
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Instellingen", systemImage: "gearshape.fill")
            }
            .tag(AppNavigationState.Tab.settings)
        }
        .sheet(isPresented: $appState.showingChatSheet) {
            ChatView(viewModel: sharedChatViewModel)
        }
        .onAppear {
            sharedChatViewModel.setTrainingPlanManager(planManager)
        }
    }
}

// MARK: - SPRINT 12.2: TRIMP Explainer Card
struct TRIMPExplainerCard: View {
    @State private var durationMinutes: Double = 60
    @State private var intensityZone: Double = 2.0 // 1 tot 5

    // Simpele Banister mapping op basis van Zone (Zone 2 = lichte hartslag stijging, Zone 5 = max)
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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wat is TRIMP?")
                    .font(.headline)
                Text("TRIMP meet de échte fysiologische impact van je training.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Interactieve Sliders
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

            // Dynamische Score & Chart
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

            // Vaste uitleg tekst
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
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - SPRINT 12.1: Burndown Chart View
struct BurndownChartView: View {
    let goals: [FitnessGoal]
    let activities: [ActivityRecord]

    struct ChartDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let remainingTRIMP: Double
        let goalTitle: String
        let isIdeal: Bool
    }

    private var chartData: [ChartDataPoint] {
        var dataPoints: [ChartDataPoint] = []
        let now = Date()

        for goal in goals {
            let targetTRIMP = goal.computedTargetTRIMP
            let title = goal.title

            // 1. Ideale Lijn
            dataPoints.append(ChartDataPoint(date: goal.createdAt, remainingTRIMP: targetTRIMP, goalTitle: title, isIdeal: true))
            dataPoints.append(ChartDataPoint(date: goal.targetDate, remainingTRIMP: 0.0, goalTitle: title, isIdeal: true))

            // 2. Actuele Lijn
            var currentRemaining = targetTRIMP
            dataPoints.append(ChartDataPoint(date: goal.createdAt, remainingTRIMP: currentRemaining, goalTitle: title, isIdeal: false))

            // Filter activiteiten sinds aanmaakdatum tot max de doeldatum
            // en die (indien ingesteld) matchen met sportType
            let relevantActivities = activities.filter { record in
                record.startDate >= goal.createdAt &&
                record.startDate <= goal.targetDate &&
                (goal.sportType == nil || goal.sportType == "" || record.type.lowercased() == goal.sportType?.lowercased() || record.name.lowercased().contains((goal.sportType ?? "").lowercased()))
            }.sorted(by: { $0.startDate < $1.startDate })

            for record in relevantActivities {
                if let trimp = record.trimp {
                    currentRemaining -= trimp
                    dataPoints.append(ChartDataPoint(date: record.startDate, remainingTRIMP: max(0, currentRemaining), goalTitle: title, isIdeal: false))
                }
            }

            // Voeg vandaag toe als er vandaag geen activiteit was om de actuele stand mooi door te trekken (zolang vandaag <= targetDate)
            if now >= goal.createdAt && now <= goal.targetDate {
                if let last = dataPoints.last, last.date < now {
                    dataPoints.append(ChartDataPoint(date: now, remainingTRIMP: max(0, currentRemaining), goalTitle: title, isIdeal: false))
                }
            }
        }

        return dataPoints
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progressie (Burndown TRIMP)")
                .font(.headline)

            if chartData.isEmpty {
                Text("Nog onvoldoende data. Begin met trainen!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Chart {
                    ForEach(chartData) { point in
                        LineMark(
                            x: .value("Datum", point.date),
                            y: .value("TRIMP", point.remainingTRIMP)
                        )
                        .foregroundStyle(by: .value("Doel", point.goalTitle))
                        .lineStyle(StrokeStyle(lineWidth: point.isIdeal ? 1.5 : 3.0, dash: point.isIdeal ? [5, 5] : []))
                        .opacity(point.isIdeal ? 0.5 : 1.0)
                    }
                }
                .frame(height: 250)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.week(), centered: true)
                    }
                }

                HStack(spacing: 16) {
                    Label("Actueel", systemImage: "line.diagonal")
                        .font(.caption)
                    Label("Ideaal", systemImage: "line.diagonal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .opacity(0.7)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppNavigationState())
        .environmentObject(TrainingPlanManager())
}

import SwiftData
import Charts

struct DashboardView: View {
    @EnvironmentObject var appState: AppNavigationState
    @EnvironmentObject var planManager: TrainingPlanManager
    @ObservedObject var viewModel: ChatViewModel

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FitnessGoal.targetDate, order: .forward) private var goals: [FitnessGoal]
    @Query(filter: #Predicate<UserPreference> { $0.isActive == true }, sort: \UserPreference.createdAt, order: .forward) private var activePreferences: [UserPreference]

    @State private var currentProfile: AthleticProfile? = nil
    private let profileManager = AthleticProfileManager()

    @Query(sort: \ActivityRecord.startDate, order: .forward) private var activities: [ActivityRecord]

    @AppStorage("latestCoachInsight") private var latestCoachInsight: String = ""

    private func refreshProfileContext() {
        do {
            self.currentProfile = try profileManager.calculateProfile(context: modelContext)
        } catch {
            print("Kon profiel niet laden in DashboardView: \(error)")
        }
    }

    /// Controleert en vult ontbrekende `targetTRIMP` aan voor legacy doelen (Epic 12 Data Migratie)
    private func backfillLegacyGoals() {
        var hasChanges = false
        for goal in goals {
            if goal.targetTRIMP == nil || goal.targetTRIMP == 0 {
                let days = max(1.0, goal.targetDate.timeIntervalSince(goal.createdAt) / 86400)
                goal.targetTRIMP = (days / 7.0) * 350.0
                hasChanges = true
            }
        }

        if hasChanges {
            try? modelContext.save()
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // Pull-to-Refresh Hint
                        HStack {
                            Image(systemName: "arrow.down")
                            Text("Swipe omlaag om data te evalueren")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                        if currentProfile?.isRecoveryNeeded == true {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("Let op: Je trainingsvolume is erg hoog. Neem voldoende rust.")
                                    .font(.subheadline)
                                    .bold()
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.orange.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        if !latestCoachInsight.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundColor(.yellow)
                                    Text("Coach Insight")
                                        .font(.headline)
                                }
                                Text(latestCoachInsight)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        // Toon progressie-indicator bij asynchrone bewerkingen
                        if viewModel.isFetchingWorkout || viewModel.isTyping {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Coach analyseert schema...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        if let plan = planManager.activePlan {
                            // Hergebruik de TrainingCalendarView uit ChatView,
                            // we geven wel de viewModel callbacks door zodat de acties werken.
                            TrainingCalendarView(
                                plan: plan,
                                onSkipWorkout: { workout in
                                    refreshProfileContext()
                                    viewModel.skipWorkout(workout, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                                    // Chat niet direct openen indien gewenst om de UI rustig te houden, maar we openen hem hier wel als we
                                    // verwachten dat de gebruiker de chat loader wil zien
                                    appState.showingChatSheet = true
                                },
                                onAlternativeWorkout: { workout in
                                    refreshProfileContext()
                                    viewModel.requestAlternativeWorkout(workout, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                                    appState.showingChatSheet = true
                                }
                            )
                            .padding(.horizontal)
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                Text("Nog geen schema gepland.")
                                    .font(.headline)
                                Text("Vraag de coach om een nieuw schema te maken op basis van je doelen en data.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)

                                Button("Open Chat") {
                                    appState.showingChatSheet = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        }

                        // SPRINT 12.1: Multi-Goal Burndown Chart
                        let uncompletedGoals = goals.filter { !$0.isCompleted }
                        if !uncompletedGoals.isEmpty {
                            BurndownChartView(goals: uncompletedGoals, activities: activities)
                                .padding(.horizontal)
                        }

                        // SPRINT 12.2: Interactieve TRIMP Explainer
                        TRIMPExplainerCard()
                            .padding(.horizontal)
                    }
                    .padding(.bottom, 40) // Zorg voor wat extra scroll-ruimte
                }
                .refreshable {
                    refreshProfileContext()
                    viewModel.analyzeCurrentStatus(days: 7, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                    // Voeg een kleine vertraging toe zodat de pull-animatie niet direct wegschiet
                    // Terwijl het 'echte' wachten zichtbaar wordt via de ProgressView hierboven
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            .navigationTitle("Overzicht")
            .onChange(of: appState.targetActivityId) { oldValue, newValue in
                if let activityId = newValue {
                    refreshProfileContext()
                    viewModel.analyzeWorkout(withId: activityId, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                    appState.showingChatSheet = true
                    Task { @MainActor in
                        appState.targetActivityId = nil
                    }
                }
            }
            .onAppear {
                backfillLegacyGoals()
                refreshProfileContext()
            }
        }
    }
}
