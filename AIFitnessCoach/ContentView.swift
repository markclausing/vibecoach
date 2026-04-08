import SwiftUI
import SwiftData
import Charts

struct ContentView: View {
    @EnvironmentObject var appState: AppNavigationState
    @EnvironmentObject var planManager: TrainingPlanManager

    // We maken de ViewModel hier aan zodat we hem kunnen delen met de DashboardView
    // voor pull-to-refresh en de ChatView als overlay.
    @StateObject private var sharedChatViewModel = ChatViewModel()

    // Auto-Sync Dependencies (Sprint 12.3)
    @AppStorage("selectedDataSource") private var selectedDataSource: DataSource = .healthKit
    @Environment(\.modelContext) private var modelContext
    private let fitnessDataService = FitnessDataService()

    /// Guard tegen gelijktijdige auto-sync runs (race condition fix voor duplicate records).
    @State private var isAutoSyncing = false

    /// Voert asynchroon de data-synchronisatie voor de afgelopen 14 dagen uit op de achtergrond.
    private func performAutoSync() {
        guard !isAutoSyncing else {
            print("⚠️ Auto-sync overgeslagen: vorige sync is nog actief")
            return
        }
        isAutoSyncing = true
        Task {
            defer { Task { @MainActor in isAutoSyncing = false } }
            do {
                if selectedDataSource == .healthKit {
                    let syncService = HealthKitSyncService()
                    try await syncService.syncHistoricalWorkouts(to: modelContext) // Note: HealthKitSyncService by default is fast if already authorized
                } else {
                    // Strava API (Alleen laatste 14 dagen ophalen om API limieten en laadtijden kort te houden voor de Burn Rate graph)
                    let activities = try await fitnessDataService.fetchRecentActivities(days: 14)

                    await MainActor.run {
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        let fallbackFormatter = ISO8601DateFormatter()

                        for activity in activities {
                            let currentId = String(activity.id)
                            let fetchDescriptor = FetchDescriptor<ActivityRecord>(predicate: #Predicate { $0.id == currentId })
                            let existing = try? modelContext.fetch(fetchDescriptor)

                            if existing?.isEmpty ?? true {
                                let date = formatter.date(from: activity.start_date) ?? fallbackFormatter.date(from: activity.start_date) ?? Date()

                                // SPRINT 12.4: Voeg basic TRIMP fallback toe bij sync
                                let basicTRIMPFallback: Double? = {
                                    if let hr = activity.average_heartrate, hr > 100 {
                                        let durationMins = Double(activity.moving_time) / 60.0
                                        let simulatedDeltaHR = (hr - 60.0) / (190.0 - 60.0)
                                        return durationMins * simulatedDeltaHR * 0.64 * exp(1.92 * simulatedDeltaHR)
                                    } else {
                                        return (Double(activity.moving_time) / 60.0) * 1.5
                                    }
                                }()

                                let record = ActivityRecord(
                                    id: currentId,
                                    name: activity.name,
                                    distance: activity.distance,
                                    movingTime: activity.moving_time,
                                    averageHeartrate: activity.average_heartrate,
                                    sportCategory: SportCategory.from(rawString: activity.type),
                                    startDate: date,
                                    trimp: basicTRIMPFallback // In a real app we could recalculate the local TRIMP hier via PhysiologicalCalculator if missing
                                )
                                modelContext.insert(record)
                            }
                        }
                        try? modelContext.save()
                    }
                }
            } catch {
                print("Auto-sync gefaald op de achtergrond: \(error)")
            }
        }
    }

    var body: some View {
        TabView(selection: $appState.selectedTab) {
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

            // Tab 3: Coach — echte tab zodat de TabBar altijd zichtbaar blijft (Sprint 13.4)
            ChatView(viewModel: sharedChatViewModel)
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
        // SPRINT 13.4: showingChatSheet = true redirecteert nu naar de Coach tab
        // zodat alle bestaande callsites (banners, notificaties, deep links) blijven werken
        // zonder aanpassingen, en de TabBar altijd zichtbaar blijft.
        .onChange(of: appState.showingChatSheet) { _, isShowing in
            if isShowing {
                appState.selectedTab = .coach
                // Reset zodat de trigger opnieuw gebruikt kan worden
                Task { @MainActor in appState.showingChatSheet = false }
            }
        }
        .onAppear {
            sharedChatViewModel.setTrainingPlanManager(planManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerAutoSync"))) { _ in
            performAutoSync()
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

// MARK: - EPIC 14.3: Vibe Score Kaart (Dashboard)

/// Compacte kaart die de dagelijkse Readiness Score toont met kleurcodering.
/// Wordt bovenaan het dashboard geplaatst zodat de gebruiker direct richting krijgt.
struct VibeScoreCardView: View {
    let readiness: DailyReadiness?

    // Kleur op basis van score (groen / oranje / rood)
    private var scoreColor: Color {
        guard let r = readiness else { return .gray }
        if r.readinessScore >= 80 { return .green }
        if r.readinessScore >= 50 { return .orange }
        return .red
    }

    // SF Symbol op basis van score (batterij-metafoor)
    private var scoreIcon: String {
        guard let r = readiness else { return "battery.0" }
        if r.readinessScore >= 80 { return "bolt.fill" }
        if r.readinessScore >= 50 { return "battery.50" }
        return "battery.0"
    }

    // Tekstlabel op basis van score
    private var scoreLabel: String {
        guard let r = readiness else { return "Vibe Score berekenen..." }
        if r.readinessScore >= 80 { return "Optimaal Hersteld" }
        if r.readinessScore >= 50 { return "Matig Hersteld" }
        return "Focus op Herstel"
    }

    // Slaap opmaken als "Xu Ym"
    private func formatSleep(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)u \(m)m"
    }

    var body: some View {
        HStack(spacing: 16) {
            // Score-getal + icoon
            VStack(spacing: 2) {
                Image(systemName: scoreIcon)
                    .font(.title2)
                    .foregroundColor(scoreColor)
                if let r = readiness {
                    Text("\(r.readinessScore)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor)
                    Text("/ 100")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 64)

            // Label + onderliggende data
            VStack(alignment: .leading, spacing: 4) {
                Text("Vibe Score")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(scoreLabel)
                    .font(.headline)
                    .foregroundColor(scoreColor)

                if let r = readiness {
                    HStack(spacing: 12) {
                        Label(formatSleep(r.sleepHours), systemImage: "moon.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Label(String(format: "%.0f ms", r.hrv), systemImage: "waveform.path.ecg")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Zorg dat je Apple Watch is gesynchroniseerd.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding()
        .background(readiness != nil ? scoreColor.opacity(0.08) : Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(scoreColor.opacity(readiness != nil ? 0.3 : 0.15), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

/// Educatieve infokaart die uitlegt wat de Vibe Score is en hoe hij berekend wordt.
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
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - SPRINT 12.1 & 12.3: Burndown Chart View met Paging & Predictive Analytics
struct BurndownChartView: View {
    let goals: [FitnessGoal]
    let activities: [ActivityRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progressie & Prognoses")
                .font(.headline)
                .padding(.horizontal)

            TabView {
                ForEach(goals) { goal in
                    SingleGoalBurndownView(goal: goal, activities: activities)
                        .padding(.horizontal)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(height: 420) // Ruimte voor chart + padding + text + pager
        }
        .padding(.vertical)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

/// De weergave voor één individueel Fitness Doel met Ideale, Actuele én Prognose lijn.
struct SingleGoalBurndownView: View {
    let goal: FitnessGoal
    let activities: [ActivityRecord]

    @EnvironmentObject var planManager: TrainingPlanManager

    enum LineType: String, Plottable {
        case ideal = "Ideaal"
        case actual = "Actueel"
        case forecast = "Prognose"
    }

    struct ChartDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let remainingTRIMP: Double
        let type: LineType
    }

    @State private var scrollPosition: Date = Date().addingTimeInterval(-86400 * 21)

    // Zuivere berekening voor de UI state status (zonder state mutation in body)
    struct BurnMetrics {
        var currentWeeklyBurnRate: Double = 0
        var requiredWeeklyBurnRate: Double = 0
        var currentRemainingTRIMP: Double = 0
        var rateSourceLabel: String = "Historisch"
    }

    private var chartAnalysis: (data: [ChartDataPoint], metrics: BurnMetrics) {
        var dataPoints: [ChartDataPoint] = []
        var metrics = BurnMetrics()
        let now = Date()
        let targetTRIMP = goal.computedTargetTRIMP

        // SPRINT 12.4 DEBUG: Print alle raw database records vóór we filteren
        print("🔍 RAW DB DUMP VOOR DOEL: \(goal.title)")
        for record in activities {
            print("   Raw DB Record: \(record.name) - Category: '\(record.sportCategory.rawValue)' - Date: \(record.startDate)")
        }

        // SPRINT 12.5 & 12.6 & 12.7: Waterdichte Training Block Constraint (16 weken macroyclus) met Calendar
        // Ankerpunt is *vandaag*, zodat we de actuele fysiologische basis (base-building) altijd meenemen
        // ook als het doel nog ver in de toekomst ligt.
        let calendar = Calendar.current
        let trainingBlockStartDate = calendar.date(byAdding: .weekOfYear, value: -16, to: Date()) ?? Date()

        let relevantActivities = activities.filter { record in
            // 1. Harde Datum Check
            guard record.startDate >= trainingBlockStartDate && record.startDate <= goal.targetDate else { return false }

            // 2. Sport Categorie Check
            guard let goalCategory = goal.sportCategory else { return true } // Geen categorie == alles telt mee

            if goalCategory == .triathlon {
                return (record.sportCategory == .running || record.sportCategory == .cycling || record.sportCategory == .swimming || record.sportCategory == .triathlon)
            }

            return record.sportCategory == goalCategory
        }.sorted(by: { $0.startDate < $1.startDate })

        print("🛡️ Goal: \(goal.title) | Block Start: \(trainingBlockStartDate) | Aantal activities in block: \(relevantActivities.count)")
        for record in relevantActivities.prefix(3) {
             print("   -> \(record.name) (\(record.sportCategory.displayName)) on \(record.startDate)")
        }

        // SPRINT 12.4: Bepaal het effectieve startpunt van de grafiek (mag in het verleden liggen)
        // Definieer effectiveStartDate opnieuw: Kijk naar de lijst met gefilterde relevantActivities.
        // Pak de datum van de alleroudste activiteit in die lijst.
        // De effectiveStartDate wordt de vroegste van de twee: óf de goal.createdAt, óf de datum van die oudste activiteit.
        let effectiveStartDate: Date
        if let firstRelevantDate = relevantActivities.first?.startDate {
            effectiveStartDate = min(firstRelevantDate, goal.createdAt)
        } else {
            effectiveStartDate = goal.createdAt
        }

        // 1. Ideale Lijn start vanaf het effectieve startpunt
        dataPoints.append(ChartDataPoint(date: effectiveStartDate, remainingTRIMP: targetTRIMP, type: .ideal))
        dataPoints.append(ChartDataPoint(date: goal.targetDate, remainingTRIMP: 0.0, type: .ideal))

        // 2. Actuele Lijn
        var currentRemaining = targetTRIMP
        dataPoints.append(ChartDataPoint(date: effectiveStartDate, remainingTRIMP: currentRemaining, type: .actual))

        // Houd ook TRIMP bij voor de afgelopen 14 dagen voor de Burn Rate
        var recent14DaysTRIMP = 0.0
        let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: now)!

        for record in relevantActivities {
            if let trimp = record.trimp {
                if record.startDate <= now {
                    currentRemaining = max(0, currentRemaining - trimp)
                    dataPoints.append(ChartDataPoint(date: record.startDate, remainingTRIMP: currentRemaining, type: .actual))

                    if record.startDate >= fourteenDaysAgo {
                        recent14DaysTRIMP += trimp
                    }
                }
            }
        }

        // Voeg vandaag toe aan de actuele lijn
        if now >= goal.createdAt && now <= goal.targetDate {
            if let last = dataPoints.filter({ $0.type == .actual }).last, last.date < now {
                dataPoints.append(ChartDataPoint(date: now, remainingTRIMP: currentRemaining, type: .actual))
            }
        } else if now > goal.targetDate {
            // Als doel verstreken is, teken tot doel datum
             dataPoints.append(ChartDataPoint(date: goal.targetDate, remainingTRIMP: currentRemaining, type: .actual))
        }

        // SPRINT 12.3: Bepaal Planned Burn Rate vs Historical Burn Rate
        let historicalBurnRate = recent14DaysTRIMP / 2.0
        var activeBurnRate = historicalBurnRate

        if let plannedWorkouts = planManager.activePlan?.workouts {
            // Bereken wat er in het huidige schema aan TRIMP gepland staat voor dit type
            var plannedWeeklyTRIMP = 0.0
            for workout in plannedWorkouts {
                var workoutSportMatch = true
                if let goalCat = goal.sportCategory {
                     let mappedWorkoutCat = SportCategory.from(rawString: workout.activityType)
                     if goalCat == .triathlon {
                         workoutSportMatch = (mappedWorkoutCat == .running || mappedWorkoutCat == .cycling || mappedWorkoutCat == .swimming || mappedWorkoutCat == .triathlon)
                     } else {
                         workoutSportMatch = mappedWorkoutCat == goalCat
                     }
                }

                if workoutSportMatch, let trimp = workout.targetTRIMP {
                    plannedWeeklyTRIMP += Double(trimp)
                }
            }
            if plannedWeeklyTRIMP > 0 && historicalBurnRate > 0 {
                activeBurnRate = (plannedWeeklyTRIMP + historicalBurnRate) / 2.0
                metrics.rateSourceLabel = "Gemiddeld"
            } else if plannedWeeklyTRIMP > 0 {
                activeBurnRate = plannedWeeklyTRIMP
                metrics.rateSourceLabel = "Gepland"
            } else if historicalBurnRate > 0 {
                activeBurnRate = historicalBurnRate
                metrics.rateSourceLabel = "Historisch"
            } else {
                activeBurnRate = 0.0
                metrics.rateSourceLabel = "Geen data"
            }
        } else {
            if historicalBurnRate > 0 {
                activeBurnRate = historicalBurnRate
                metrics.rateSourceLabel = "Historisch"
            } else {
                activeBurnRate = 0.0
                metrics.rateSourceLabel = "Geen data"
            }
        }

        // Zuivere toewijzing (geen state mutation in de View)
        metrics.currentRemainingTRIMP = currentRemaining
        metrics.currentWeeklyBurnRate = activeBurnRate

        let weeksToTarget = max(0.1, goal.targetDate.timeIntervalSince(now) / (86400 * 7))
        metrics.requiredWeeklyBurnRate = currentRemaining / weeksToTarget

        // 3. Prognose Lijn (Alleen zinvol als we in het heden of verleden van de doeldatum zitten)
        if now < goal.targetDate {
            let startForecast = ChartDataPoint(date: now, remainingTRIMP: currentRemaining, type: .forecast)
            dataPoints.append(startForecast)

            if activeBurnRate > 0 && currentRemaining > 0 {
                // Hoeveel weken duurt het om op 0 te komen met dit geplande/historische tempo?
                let weeksToZero = currentRemaining / activeBurnRate
                let zeroDate = calendar.date(byAdding: .day, value: Int(weeksToZero * 7), to: now)!

                // Teken de lijn
                dataPoints.append(ChartDataPoint(date: zeroDate, remainingTRIMP: 0.0, type: .forecast))
            } else {
                // Geen progressie (0 burn rate) of doel al behaald, teken een platte lijn naar (en voorbij) targetDate
                let futureDate = calendar.date(byAdding: .day, value: 14, to: goal.targetDate)!
                dataPoints.append(ChartDataPoint(date: futureDate, remainingTRIMP: currentRemaining, type: .forecast))
            }
        }

        return (dataPoints, metrics)
    }

    private let calendar = Calendar.current

    var body: some View {
        let analysis = chartAnalysis
        let currentWeeklyBurnRate = analysis.metrics.currentWeeklyBurnRate
        let requiredWeeklyBurnRate = analysis.metrics.requiredWeeklyBurnRate

        VStack(alignment: .leading, spacing: 8) {
            // Status Indicator UI
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.title)
                    .font(.subheadline)
                    .fontWeight(.bold)

                if Date() < goal.targetDate {
                    if analysis.metrics.currentRemainingTRIMP <= 0 {
                        HStack {
                            Text("🏆")
                            Text("Doel TRIMP behaald!")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        }
                        Text("Je bent fysiologisch klaar voor dit doel!")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        let isGreen = currentWeeklyBurnRate >= requiredWeeklyBurnRate * 0.95
                        let isOrange = currentWeeklyBurnRate >= requiredWeeklyBurnRate * 0.75 && !isGreen

                        HStack {
                            Text(isGreen ? "🟢" : (isOrange ? "🟠" : "🔴"))
                            let rateTypeLabel = analysis.metrics.rateSourceLabel
                            Text("\(rateTypeLabel): \(Int(currentWeeklyBurnRate)) /wk | Nodig: \(Int(requiredWeeklyBurnRate)) /wk")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(isGreen ? "Je ligt perfect op schema!" : (isOrange ? "Je ligt iets achter op schema." : "Actie vereist! Je haalt het doel niet met dit (geplande) tempo."))
                            .font(.caption2)
                            .foregroundColor(isGreen ? .green : (isOrange ? .orange : .red))
                    }
                } else {
                    Text("Doeldatum is verstreken.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 8)

            // De Grafiek
            Chart {
                ForEach(analysis.data) { point in
                    LineMark(
                        x: .value("Datum", point.date),
                        y: .value("TRIMP", point.remainingTRIMP)
                    )
                    .foregroundStyle(by: .value("Type", point.type))
                    .lineStyle(StrokeStyle(
                        lineWidth: point.type == .actual ? 4.0 : 2.0,
                        dash: point.type == .actual ? [] : (point.type == .ideal ? [5, 5] : [2, 2])
                    ))
                    .opacity(point.type == .actual ? 1.0 : (point.type == .ideal ? 0.4 : 0.8))
                }

                // Verticale referentielijn voor "Vandaag"
                RuleMark(x: .value("Vandaag", Date()))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .annotation(position: .top) {
                        Text("Vandaag")
                            .font(.caption2)
                            .foregroundColor(.red)
                            .padding(2)
                            .background(Color(.systemBackground).opacity(0.8))
                            .cornerRadius(4)
                    }
            }
            // Handmatige kleurtoewijzing
            .chartForegroundStyleScale([
                LineType.actual.rawValue: .blue,
                LineType.ideal.rawValue: .gray,
                LineType.forecast.rawValue: .orange
            ])
            .frame(height: 250)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 3600 * 24 * 42) // 42 dagen zichtbaar
            .chartScrollPosition(x: $scrollPosition)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.day().month(), centered: true)
                }
            }

            // Legenda
            HStack(spacing: 16) {
                Label("Actueel", systemImage: "line.diagonal")
                    .font(.caption)
                    .foregroundColor(.blue)
                Label("Ideaal", systemImage: "line.diagonal")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .opacity(0.7)
                Label("Prognose", systemImage: "line.diagonal")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            .padding(.top, 4)
            .padding(.bottom, 24) // Extra ruimte voor de page indicator
        }
        .onAppear {
            scrollPosition = Date().addingTimeInterval(-86400 * 21)
        }
    }
}

// MARK: - SPRINT 13.1 & 13.3: Proactieve Waarschuwingsbanner

/// Toont een prominente rode banner op het Dashboard als een of meerdere doelen
/// significant achterlopen op de ideale burndown-lijn (< 75% van de benodigde burn rate).
/// Sprint 13.3: bevat een 'Los dit op'-knop die direct een AI-herstelplan aanvraagt.
struct ProactiveWarningBannerView: View {
    let atRiskGoals: [DashboardView.GoalRiskStatus]
    let onCoachTapped: () -> Void
    /// Sprint 13.3: callback voor het aanvragen van een concreet herstelplan.
    let onRecoveryPlanTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Kop
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(atRiskGoals.count == 1
                     ? "Doel loopt achter"
                     : "\(atRiskGoals.count) doelen lopen achter")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }

            // Lijst van doelen in gevaar (max 2 tonen)
            ForEach(atRiskGoals.prefix(2), id: \.goal.id) { status in
                HStack {
                    Text("• \(status.goal.title)")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(status.currentWeeklyRate))/\(Int(status.requiredWeeklyRate)) /wk")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }
            }

            // SPRINT 13.3: Twee knoppen naast elkaar
            HStack(spacing: 10) {
                // 'Los dit op' — stuurt recovery context naar de AI en opent de chat
                Button(action: onRecoveryPlanTapped) {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                        Text("Los dit op")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(10)
                    .foregroundColor(.orange)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.4), lineWidth: 1))
                }

                // 'Vraag Coach' — opent de chat zonder specifieke context
                Button(action: onCoachTapped) {
                    HStack(spacing: 6) {
                        Image(systemName: "message")
                        Text("Open Chat")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    .foregroundColor(.secondary)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.08))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - SPRINT 13.3: Herstelplan Actief Banner

/// Toont een blauwe/groene bevestigingsbanner als de gebruiker recent 'Los dit op'
/// heeft gedrukt en de AI een herstelplan heeft gegenereerd.
/// Verdwijnt automatisch na 3 dagen.
struct RecoveryPlanActiveBannerView: View {
    let onCoachTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                Text("Herstelplan Actief")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Text("3 dagen")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Je bent weer op de goede weg. Volg het schema van de coach om je doel te halen.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: onCoachTapped) {
                HStack(spacing: 6) {
                    Image(systemName: "message")
                    Text("Bekijk het herstelplan")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.12))
                .cornerRadius(10)
                .foregroundColor(.blue)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.3), lineWidth: 1))
            }
        }
        .padding()
        .background(Color.blue.opacity(0.07))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.blue.opacity(0.2), lineWidth: 1))
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
    @ObservedObject var viewModel: ChatViewModel

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FitnessGoal.targetDate, order: .forward) private var goals: [FitnessGoal]
    @Query(filter: #Predicate<UserPreference> { $0.isActive == true }, sort: \UserPreference.createdAt, order: .forward) private var activePreferences: [UserPreference]

    @State private var currentProfile: AthleticProfile? = nil
    private let profileManager = AthleticProfileManager()

    @Query(sort: \ActivityRecord.startDate, order: .forward) private var activities: [ActivityRecord]

    @AppStorage("latestCoachInsight") private var latestCoachInsight: String = ""

    // Epic 14.3: Haal alle DailyReadiness records op (weinig records — max 1 per dag)
    @Query(sort: \DailyReadiness.date, order: .reverse) private var readinessRecords: [DailyReadiness]

    /// Geeft het DailyReadiness record van vandaag terug, of nil als er nog geen is.
    private var todayReadiness: DailyReadiness? {
        let todayStart = Calendar.current.startOfDay(for: Date())
        return readinessRecords.first { $0.date >= todayStart }
    }

    /// SPRINT 13.3: Tijdstip waarop de gebruiker voor het laatst 'Los dit op' heeft gedrukt.
    /// Opgeslagen als Unix timestamp (Double) zodat AppStorage er mee werkt.
    @AppStorage("vibecoach_recoveryPlanTimestamp") private var recoveryPlanTimestamp: Double = 0

    /// True als er een actief herstelplan is dat minder dan 3 dagen geleden is aangevraagd.
    private var hasActiveRecoveryPlan: Bool {
        guard recoveryPlanTimestamp > 0 else { return false }
        let planDate = Date(timeIntervalSince1970: recoveryPlanTimestamp)
        let threeDays: TimeInterval = 3 * 24 * 3600
        return Date().timeIntervalSince(planDate) < threeDays
    }

    private func refreshProfileContext() {
        do {
            self.currentProfile = try profileManager.calculateProfile(context: modelContext)
        } catch {
            print("Kon profiel niet laden in DashboardView: \(error)")
        }
    }

    // MARK: - Sprint 13.1: Risicobeoordeling per doel

    /// Lichtgewicht status-struct per doel dat achteroploopt op de burndown.
    struct GoalRiskStatus {
        let goal: FitnessGoal
        let currentWeeklyRate: Double  // Actuele burn rate (TRIMP/week)
        let requiredWeeklyRate: Double // Benodigde burn rate om doel te halen
    }

    /// Retourneert actieve doelen die significant achterlopen (< 75% van benodigde burn rate),
    /// gesorteerd op grootste tekort eerst.
    private var atRiskGoals: [GoalRiskStatus] {
        let now = Date()
        let calendar = Calendar.current
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let trainingBlockStart = calendar.date(byAdding: .weekOfYear, value: -16, to: now) ?? now

        return goals.compactMap { goal in
            guard !goal.isCompleted, now < goal.targetDate else { return nil }

            let targetTRIMP = goal.computedTargetTRIMP
            let weeksRemaining = max(0.1, goal.targetDate.timeIntervalSince(now) / (7 * 86400))

            // Filter relevante activiteiten (zelfde logica als SingleGoalBurndownView)
            let relevantActivities = activities.filter { record in
                guard record.startDate >= trainingBlockStart && record.startDate <= now else { return false }
                guard let goalCategory = goal.sportCategory else { return true }
                if goalCategory == .triathlon {
                    return [.running, .cycling, .swimming, .triathlon].contains(record.sportCategory)
                }
                return record.sportCategory == goalCategory
            }

            // Bereken hoeveel TRIMP er nog overblijft
            let achievedTRIMP = relevantActivities.compactMap { $0.trimp }.reduce(0, +)
            let currentRemaining = max(0, targetTRIMP - achievedTRIMP)
            guard currentRemaining > 0 else { return nil } // Doel al behaald

            // Burn rate op basis van de laatste 2 weken
            let recentTRIMP = relevantActivities
                .filter { $0.startDate >= twoWeeksAgo }
                .compactMap { $0.trimp }
                .reduce(0, +)
            let currentBurnRate = recentTRIMP / 2.0

            let requiredRate = currentRemaining / weeksRemaining

            // Alleen tonen bij rood (< 75% van benodigde burn rate)
            guard currentBurnRate < requiredRate * 0.75 else { return nil }
            return GoalRiskStatus(goal: goal, currentWeeklyRate: currentBurnRate, requiredWeeklyRate: requiredRate)
        }
        .sorted { ($0.requiredWeeklyRate - $0.currentWeeklyRate) > ($1.requiredWeeklyRate - $1.currentWeeklyRate) }
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

                        // Pull-to-refresh hint: als eerste VStack-item zodat hij meescrollt
                        // en niet over andere UI-elementen heen komt
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.caption2)
                            Text("Swipe omlaag om te verversen")
                                .font(.caption2)
                        }
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)

                        // SPRINT 13.1 & 13.3: Banner logica op basis van recovery plan status
                        if !atRiskGoals.isEmpty {
                            if hasActiveRecoveryPlan {
                                // Herstelplan is actief (< 3 dagen geleden aangevraagd): toon blauwe banner
                                RecoveryPlanActiveBannerView {
                                    appState.showingChatSheet = true
                                }
                                .padding(.horizontal)
                            } else {
                                // Geen actief herstelplan: toon rode waarschuwingsbanner
                                ProactiveWarningBannerView(
                                    atRiskGoals: atRiskGoals,
                                    onCoachTapped: {
                                        appState.showingChatSheet = true
                                    },
                                    onRecoveryPlanTapped: {
                                        // SPRINT 13.3: Bouw recovery context en stuur naar AI
                                        refreshProfileContext()
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
                                            contextProfile: currentProfile,
                                            activeGoals: goals,
                                            activePreferences: activePreferences
                                        )
                                        // Sla het tijdstip op zodat de banner 3 dagen blauw blijft
                                        recoveryPlanTimestamp = Date().timeIntervalSince1970
                                        appState.showingChatSheet = true
                                    }
                                )
                                .padding(.horizontal)
                            }
                        }

                        // EPIC 14.3: Vibe Score Kaart — bovenaan voor directe richting
                        VibeScoreCardView(readiness: todayReadiness)
                            .padding(.horizontal)

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
                                Text(viewModel.retryStatusMessage.isEmpty
                                     ? "Coach analyseert schema..."
                                     : viewModel.retryStatusMessage)
                                    .font(.subheadline)
                                    .foregroundColor(viewModel.retryStatusMessage.isEmpty ? .secondary : .orange)
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

                        // EPIC 14.3: Educatieve Vibe Score uitlegkaart
                        VibeScoreExplainerCard()
                            .padding(.horizontal)
                    }
                    .padding(.bottom, 40) // Zorg voor wat extra scroll-ruimte
                }
                .refreshable {
                    NotificationCenter.default.post(name: NSNotification.Name("TriggerAutoSync"), object: nil)
                    refreshProfileContext()
                    viewModel.analyzeCurrentStatus(days: 7, contextProfile: currentProfile, activeGoals: goals, activePreferences: activePreferences)
                    // SPRINT 13.2: Werk de risicocache bij voor de achtergrond-engines na refresh
                    ProactiveNotificationService.shared.updateRiskCache(
                        atRiskGoalTitles: atRiskGoals.map { $0.goal.title }
                    )
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
                // SPRINT 13.2: Werk de risicocache bij bij elk app-open zodat
                // de achtergrond-engines altijd actuele data hebben
                ProactiveNotificationService.shared.updateRiskCache(
                    atRiskGoalTitles: atRiskGoals.map { $0.goal.title }
                )
                // EPIC 14: Vraag altijd opnieuw toestemming aan bij app-launch.
                // HealthKit toont alleen een popup voor types die nog niet zijn goedgekeurd
                // (bijv. heartRateVariabilitySDNN en sleepAnalysis zijn nieuw in Epic 14).
                // Voor al-goedgekeurde types gebeurt er niets — dit is de standaard iOS-aanpak.
                HealthKitManager().requestAuthorization { _, _ in }
                // EPIC 14.4: Schrijf de Vibe Score van vandaag naar de AI-prompt cache
                // zodat elke coach-interactie de actuele herstelstatus kent.
                viewModel.cacheVibeScore(todayReadiness)
            }
        }
    }
}
