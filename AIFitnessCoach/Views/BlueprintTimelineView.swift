import SwiftUI
import Charts

// MARK: - Epic 23 Sprint 3: Visual Progress Hub — Blueprint Tijdlijn

/// Metriek die de gebruiker kan weergeven in de tijdlijn.
enum TimelineMetric: String, CaseIterable {
    case trimp  = "TRIMP"
    case km     = "km"

    var label: String { rawValue }
    var icon: String {
        switch self {
        case .trimp: return "bolt.fill"
        case .km:    return "figure.run"
        }
    }
}

/// Eén datapunt in de tijdlijn — stelt het wekelijkse volume voor op een bepaald moment.
struct TimelinePoint: Identifiable {
    let id = UUID()
    let weekStart: Date
    let volume: Double       // TRIMP of km, afhankelijk van de geselecteerde metriek
    let series: SeriesType

    enum SeriesType: String, Plottable {
        case ideal      = "Ideaal"
        case actual     = "Actueel"
        case projection = "Prognose"
    }
}

/// Markeert een fase-overgang (Base → Build → Peak → Taper) in de tijdlijn.
struct PhaseMarker: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
    let color: Color
}

// MARK: - BlueprintTimelineView

/// De "Glazen Bol" tijdlijn — toont de volledige voorbereiding van start tot racedag
/// in één overzichtelijke gecombineerde lijngrafiek.
///
/// **Drie lijnen:**
/// - 🩶 Ideaal (gestippeld): Fase-gecorrigeerde blauwdruk per week
/// - 🔵 Actueel (vol): Werkelijk behaald wekelijks volume tot vandaag
/// - 🟠 Prognose (gestreept): Extrapolatie vanuit FutureProjectionService
///
/// **Interactiviteit:**
/// - Toggle TRIMP / km bovenaan de grafiek
/// - Scrollbaar via `chartScrollableAxes` — geschikt voor doelen ver in de toekomst
/// - RuleMark 'Vandaag' en fase-grens annotaties
struct BlueprintTimelineView: View {

    let goal: FitnessGoal
    let activities: [ActivityRecord]
    let projection: GoalProjection?

    @State private var metric: TimelineMetric = .trimp
    @State private var scrollPosition: Date = Date()

    private let calendar = Calendar.current

    // MARK: - Data berekening

    /// Genereert alle weekelijkse datapunten voor de drie lijnen.
    private var timelineData: [TimelinePoint] {
        guard let blueprintType = BlueprintChecker.detectBlueprintType(for: goal) else { return [] }
        let blueprint = BlueprintChecker.blueprint(for: blueprintType)

        let now        = Date()
        let startDate  = min(goal.createdAt, now)
        let endDate    = goal.targetDate

        // Bepaal de sport-categorie voor km-filtering
        let targetSport: SportCategory
        switch blueprintType {
        case .marathon, .halfMarathon: targetSport = .running
        case .cyclingTour:             targetSport = .cycling
        }

        var points: [TimelinePoint] = []

        // MARK: Wekelijks begin-array genereren (alle weken van start tot targetDate)
        var weekStarts: [Date] = []
        var cursor = calendar.startOfWeek(for: startDate)
        while cursor <= endDate {
            weekStarts.append(cursor)
            cursor = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) ?? endDate.addingTimeInterval(1)
        }

        // MARK: 1. Ideale Lijn — fase-gecorrigeerde blauwdruk per week
        for weekStart in weekStarts {
            let weekMid       = calendar.date(byAdding: .day, value: 3, to: weekStart) ?? weekStart
            let weeksLeft     = endDate.timeIntervalSince(weekMid) / (7 * 86400)
            let phase         = TrainingPhase.calculate(weeksRemaining: weeksLeft)
            let idealVolume: Double
            switch metric {
            case .trimp:
                idealVolume = blueprint.weeklyTrimpTarget * phase.multiplier
            case .km:
                idealVolume = blueprint.weeklyKmTarget   * phase.multiplier
            }
            points.append(TimelinePoint(weekStart: weekStart, volume: idealVolume, series: .ideal))
        }

        // MARK: 2. Actuele Lijn — werkelijk wekelijks volume t/m vandaag
        // Groepeer activiteiten per maandag-start ISO-week
        let pastWeeks = weekStarts.filter { $0 <= now }
        for weekStart in pastWeeks {
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
            let weekActivities = activities.filter {
                $0.startDate >= weekStart && $0.startDate < weekEnd
            }
            let actualVolume: Double
            switch metric {
            case .trimp:
                actualVolume = weekActivities.compactMap { $0.trimp }.reduce(0, +)
            case .km:
                let sportActivities = weekActivities.filter { $0.sportCategory == targetSport }
                let kmValues = sportActivities.map { $0.distance / 1000.0 }
                actualVolume = kmValues.reduce(0, +)
            }
            points.append(TimelinePoint(weekStart: weekStart, volume: actualVolume, series: .actual))
        }

        // MARK: 3. Prognose Lijn — extrapolatie vanuit FutureProjectionService (bottleneck-bewust)
        // TRIMP-modus: gebruik effectiveGrowthRate op currentWeeklyTRIMP
        // KM-modus:    gebruik effectiveKmGrowthRate op currentWeeklyKm (sport-gefilterd)
        // Dit voorkomt dat fietsen-TRIMP een hardloop-km-achterstand maskeert in de grafiek.
        if let proj = projection, proj.status != .alreadyPeaking {
            let todayWeekStart = calendar.startOfWeek(for: now)
            let futureWeeks    = weekStarts.filter { $0 >= todayWeekStart && $0 <= endDate }

            // Startvolume en groeisnelheid hangen af van de geselecteerde metriek
            var projectedVolume: Double
            let growthRate: Double
            let peakStopDate: Date?

            switch metric {
            case .trimp:
                projectedVolume = proj.currentWeeklyTRIMP
                growthRate      = proj.effectiveGrowthRate
                peakStopDate    = proj.projectedPeakDateTRIMP ?? proj.projectedPeakDate
            case .km:
                projectedVolume = proj.currentWeeklyKm
                growthRate      = proj.effectiveKmGrowthRate
                peakStopDate    = proj.projectedPeakDateKm ?? proj.projectedPeakDate
            }

            for (index, weekStart) in futureWeeks.enumerated() {
                if index > 0 {
                    projectedVolume *= (1.0 + growthRate)
                }
                points.append(TimelinePoint(weekStart: weekStart, volume: projectedVolume, series: .projection))
                if let stop = peakStopDate, weekStart > stop { break }
            }
        }

        return points
    }

    /// Fase-grenzen als annotatie-markeringen in de grafiek.
    private var phaseMarkers: [PhaseMarker] {
        let target = goal.targetDate
        return [
            PhaseMarker(
                date: calendar.date(byAdding: .weekOfYear, value: -12, to: target) ?? target,
                label: "Build",
                color: .orange
            ),
            PhaseMarker(
                date: calendar.date(byAdding: .weekOfYear, value: -4,  to: target) ?? target,
                label: "Peak",
                color: .red
            ),
            PhaseMarker(
                date: calendar.date(byAdding: .weekOfYear, value: -2,  to: target) ?? target,
                label: "Taper",
                color: .purple
            )
        ]
    }

    /// Gradiëntkleur voor de schaduw onder de actuele lijn.
    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue.opacity(0.20), Color.blue.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Maximale Y-waarde voor het schalen van de grafiek.
    private var yMax: Double {
        let maxData = timelineData.map { $0.volume }.max() ?? 100
        return maxData * 1.15   // 15% marge boven de hoogste waarde
    }

    // MARK: - Zichtbaar domein

    /// Initieel zichtbaar X-domein: 8 weken voor vandaag tot 8 weken erna (16 weken venster).
    private var initialVisibleStart: Date {
        calendar.date(byAdding: .weekOfYear, value: -8, to: Date()) ?? Date()
    }

    private let visibleWeeks: Int = 16  // Zichtbaar venster in weken

    /// Zichtbaar X-domein in seconden (voor chartXVisibleDomain).
    private var visibleDomainLength: TimeInterval {
        TimeInterval(visibleWeeks) * 7.0 * 24.0 * 3600.0
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Header + Toggle
            headerRow

            // De grafiek
            chart
                .frame(height: 220)
                .padding(.horizontal, 4)

            // Legenda
            legendRow

            // Fase-labels footer
            phaseFooter
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Sub-views

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tijdlijn")
                    .font(.headline)
                Text(goal.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            // TRIMP / km toggle
            Picker("Metriek", selection: $metric) {
                ForEach(TimelineMetric.allCases, id: \.self) { m in
                    Label(m.label, systemImage: m.icon).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
    }

    @ViewBuilder
    private var chart: some View {
        let data = timelineData
        Chart {
            // MARK: Fase-grenzen (subtiele verticale lijnen)
            ForEach(phaseMarkers) { marker in
                RuleMark(x: .value("Fase", marker.date))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(marker.color.opacity(0.4))
                    .annotation(position: .top, alignment: .center) {
                        Text(marker.label)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(marker.color.opacity(0.7))
                    }
            }

            // MARK: Race dag marker
            RuleMark(x: .value("Race", goal.targetDate))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                .foregroundStyle(Color.gray.opacity(0.5))
                .annotation(position: .top, alignment: .trailing) {
                    Text("🏁")
                        .font(.system(size: 10))
                }

            // MARK: Vandaag marker
            RuleMark(x: .value("Vandaag", Date()))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .foregroundStyle(Color.white.opacity(0.6))
                .annotation(position: .bottom, alignment: .leading) {
                    Text("Nu")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }

            // MARK: Ideale Lijn (grijs, gestippeld)
            ForEach(data.filter { $0.series == .ideal }) { point in
                LineMark(
                    x: .value("Week", point.weekStart),
                    y: .value(metric.label, point.volume),
                    series: .value("Type", point.series.rawValue)
                )
                .foregroundStyle(.gray.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .interpolationMethod(.monotone)
            }

            // MARK: Actuele Lijn (blauw, vol)
            ForEach(data.filter { $0.series == .actual }) { point in
                LineMark(
                    x: .value("Week", point.weekStart),
                    y: .value(metric.label, point.volume),
                    series: .value("Type", point.series.rawValue)
                )
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.monotone)

                // Gebiedsschaduw onder de actuele lijn voor dieptegevoel
                AreaMark(
                    x: .value("Week", point.weekStart),
                    yStart: .value("Min", 0),
                    yEnd:   .value(metric.label, point.volume)
                )
                .foregroundStyle(areaGradient)
                .interpolationMethod(.monotone)
            }

            // MARK: Prognose Lijn (oranje, gestreept)
            ForEach(data.filter { $0.series == .projection }) { point in
                LineMark(
                    x: .value("Week", point.weekStart),
                    y: .value(metric.label, point.volume),
                    series: .value("Type", point.series.rawValue)
                )
                .foregroundStyle(Color.orange)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .interpolationMethod(.monotone)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                    .font(.system(size: 9))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel()
                    .font(.system(size: 9))
            }
        }
        .chartYScale(domain: 0...yMax)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleDomainLength)
        .chartScrollPosition(x: $scrollPosition)
        .onAppear {
            // Initialiseer scroll-positie zodat 'vandaag' net rechts van het midden staat
            scrollPosition = initialVisibleStart
        }
    }

    private var legendRow: some View {
        HStack(spacing: 16) {
            legendItem(color: .gray,   dash: [5, 4], label: "Ideaal schema")
            legendItem(color: .blue,   dash: [],     label: "Jouw voortgang")
            legendItem(color: .orange, dash: [6, 4], label: "Prognose")
        }
        .font(.caption2)
    }

    private func legendItem(color: Color, dash: [CGFloat], label: String) -> some View {
        HStack(spacing: 5) {
            // Kleine lijntje als legenda-icoon
            Canvas { context, size in
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 2, dash: dash)
                )
            }
            .frame(width: 20, height: 10)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    private var phaseFooter: some View {
        HStack(spacing: 0) {
            phaseChip(label: "Base", color: .blue)
            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            phaseChip(label: "Build", color: .orange)
            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            phaseChip(label: "Peak", color: .red)
            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            phaseChip(label: "Taper", color: .purple)
            Spacer()
            raceCountdown
        }
    }

    private func phaseChip(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var raceCountdown: some View {
        let daysLeft = max(0, Int(goal.targetDate.timeIntervalSince(Date()) / 86400))
        return Text("🏁 \(daysLeft)d")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Sectieweergave voor de Doelen-tab

/// Toont BlueprintTimelineView voor elk actief doel met een blueprint — als carrousel.
struct BlueprintTimelineSectionView: View {
    let goals: [FitnessGoal]
    let activities: [ActivityRecord]
    let projections: [GoalProjection]

    /// Alleen doelen mét een herkende blueprint
    private var eligibleGoals: [FitnessGoal] {
        goals.filter { BlueprintChecker.detectBlueprintType(for: $0) != nil && !$0.isCompleted && Date() < $0.targetDate }
    }

    var body: some View {
        if !eligibleGoals.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                        .foregroundStyle(.purple)
                    Text("Jouw Trainingstraject")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)

                if eligibleGoals.count == 1, let goal = eligibleGoals.first {
                    let proj = projections.first { $0.goal.id == goal.id }
                    BlueprintTimelineView(goal: goal, activities: activities, projection: proj)
                        .padding(.horizontal)
                } else {
                    // Meerdere doelen: carrousel met pager
                    TabView {
                        ForEach(eligibleGoals) { goal in
                            let proj = projections.first { $0.goal.id == goal.id }
                            BlueprintTimelineView(goal: goal, activities: activities, projection: proj)
                                .padding(.horizontal)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                    .frame(height: 360)
                }
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Calendar extensie: begin van de ISO-week (maandag)

private extension Calendar {
    /// Geeft de maandag van de week terug die `date` bevat.
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? date
    }
}
