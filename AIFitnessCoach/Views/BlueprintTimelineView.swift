import SwiftUI
import Charts

// MARK: - Epic 23 Sprint 3: Visual Progress Hub — Blueprint Timeline

/// Metric the user can display in the timeline.
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

/// One data point in the timeline — represents the weekly volume at a given moment.
struct TimelinePoint: Identifiable {
    let id = UUID()
    let weekStart: Date
    let volume: Double       // TRIMP or km, depending on the selected metric
    let series: SeriesType

    enum SeriesType: String, Plottable {
        case ideal      = "Ideaal"
        case actual     = "Actueel"
        case projection = "Prognose"
    }
}

/// Marks a phase transition (Base → Build → Peak → Taper) in the timeline.
struct PhaseMarker: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
    let color: Color
}

// MARK: - BlueprintTimelineView

/// The "Crystal Ball" timeline — shows the full preparation from start to race day
/// in one clear combined line chart.
///
/// **Three lines:**
/// - 🩶 Ideal (dotted): Phase-corrected blueprint per week
/// - 🔵 Actual (solid): Actually achieved weekly volume up to today
/// - 🟠 Projection (dashed): Extrapolation from FutureProjectionService
///
/// **Interactivity:**
/// - Toggle TRIMP / km at the top of the chart
/// - Scrollable via `chartScrollableAxes` — suitable for goals far in the future
/// - RuleMark 'Today' and phase-boundary annotations
struct BlueprintTimelineView: View {

    let goal: FitnessGoal
    let activities: [ActivityRecord]
    let projection: GoalProjection?

    @State private var metric: TimelineMetric = .trimp
    @State private var scrollPosition: Date = Date()

    private let calendar = Calendar.current

    // MARK: - Data computation

    /// Generates all weekly data points for the three lines.
    private var timelineData: [TimelinePoint] {
        guard let blueprintType = BlueprintChecker.detectBlueprintType(for: goal) else { return [] }
        let blueprint = BlueprintChecker.blueprint(for: blueprintType)

        let now        = Date()
        let startDate  = min(goal.createdAt, now)
        let endDate    = goal.targetDate

        // Determine the sport category for km filtering
        let targetSport: SportCategory
        switch blueprintType {
        case .marathon, .halfMarathon: targetSport = .running
        case .cyclingTour:             targetSport = .cycling
        }

        var points: [TimelinePoint] = []

        // MARK: Generate weekly start array (all weeks from start to targetDate)
        var weekStarts: [Date] = []
        var cursor = calendar.startOfWeek(for: startDate)
        while cursor <= endDate {
            weekStarts.append(cursor)
            cursor = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) ?? endDate.addingTimeInterval(1)
        }

        // MARK: 1. Ideal Line — phase-corrected blueprint per week
        for weekStart in weekStarts {
            let weekMid       = calendar.date(byAdding: .day, value: 3, to: weekStart) ?? weekStart
            let weeksLeft     = calendar.fractionalWeeks(from: weekMid, to: endDate)
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

        // MARK: 2. Actual Line — actual weekly volume up to today
        // Group activities per Monday-start ISO week
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

        // MARK: 3. Projection Line — extrapolation from FutureProjectionService (bottleneck-aware)
        // TRIMP mode: use effectiveGrowthRate on currentWeeklyTRIMP
        // KM mode:    use effectiveKmGrowthRate on currentWeeklyKm (sport-filtered)
        // This prevents cycling-TRIMP from masking a running-km shortfall in the chart.
        if let proj = projection, proj.status != .alreadyPeaking {
            let todayWeekStart = calendar.startOfWeek(for: now)
            let futureWeeks    = weekStarts.filter { $0 >= todayWeekStart && $0 <= endDate }

            // Starting volume and growth rate depend on the selected metric
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

    /// Phase boundaries as annotation markers in the chart.
    private var phaseMarkers: [PhaseMarker] {
        let target = goal.targetDate
        return [
            PhaseMarker(
                date: calendar.date(byAdding: .weekOfYear, value: -12, to: target) ?? target,
                label: "Build",
                color: .orange
            ),
            PhaseMarker(
                date: calendar.date(byAdding: .weekOfYear, value: -4, to: target) ?? target,
                label: "Peak",
                color: .red
            ),
            PhaseMarker(
                date: calendar.date(byAdding: .weekOfYear, value: -2, to: target) ?? target,
                label: "Taper",
                color: .purple
            )
        ]
    }

    /// Gradient color for the shadow under the actual line.
    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue.opacity(0.20), Color.blue.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Maximum Y value for scaling the chart.
    private var yMax: Double {
        let maxData = timelineData.map { $0.volume }.max() ?? 100
        return maxData * 1.15   // 15% margin above the highest value
    }

    // MARK: - Visible domain

    /// Initial visible X domain: 8 weeks before today to 8 weeks after (16-week window).
    private var initialVisibleStart: Date {
        calendar.date(byAdding: .weekOfYear, value: -8, to: Date()) ?? Date()
    }

    private let visibleWeeks: Int = 16  // Visible window in weeks

    /// Visible X domain in seconds (for chartXVisibleDomain).
    private var visibleDomainLength: TimeInterval {
        TimeInterval(visibleWeeks) * 7.0 * 24.0 * 3600.0
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Header + Toggle
            headerRow

            // The chart
            chart
                .frame(height: 220)
                .padding(.horizontal, 4)

            // Legend
            legendRow

            // Phase-labels footer
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
            // MARK: Phase boundaries (subtle vertical lines)
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

            // MARK: Race day marker
            RuleMark(x: .value("Race", goal.targetDate))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                .foregroundStyle(Color.gray.opacity(0.5))
                .annotation(position: .top, alignment: .trailing) {
                    Text("🏁")
                        .font(.system(size: 10))
                }

            // MARK: Today marker
            RuleMark(x: .value("Vandaag", Date()))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .foregroundStyle(Color.white.opacity(0.6))
                .annotation(position: .bottom, alignment: .leading) {
                    Text("Nu")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }

            // MARK: Ideal Line (gray, dotted)
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

            // MARK: Actual Line (blue, solid)
            ForEach(data.filter { $0.series == .actual }) { point in
                LineMark(
                    x: .value("Week", point.weekStart),
                    y: .value(metric.label, point.volume),
                    series: .value("Type", point.series.rawValue)
                )
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.monotone)

                // Area shadow under the actual line for a sense of depth
                AreaMark(
                    x: .value("Week", point.weekStart),
                    yStart: .value("Min", 0),
                    yEnd: .value(metric.label, point.volume)
                )
                .foregroundStyle(areaGradient)
                .interpolationMethod(.monotone)
            }

            // MARK: Projection Line (orange, dashed)
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
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                    .font(.system(size: 9))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
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
            // Initialize scroll position so 'today' sits just to the right of center
            scrollPosition = initialVisibleStart
        }
    }

    private var legendRow: some View {
        HStack(spacing: 16) {
            legendItem(color: .gray, dash: [5, 4], label: "Ideaal schema")
            legendItem(color: .blue, dash: [], label: "Jouw voortgang")
            legendItem(color: .orange, dash: [6, 4], label: "Prognose")
        }
        .font(.caption2)
    }

    private func legendItem(color: Color, dash: [CGFloat], label: String) -> some View {
        HStack(spacing: 5) {
            // Small line as legend icon
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
            // Epic #37 story 37.1c: legend label is a Dutch literal -> resolve via the catalog.
            Text(LocalizedStringKey(label))
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
        let daysLeft = max(0, Calendar.current.wholeDays(from: Date(), to: goal.targetDate))
        return Text("🏁 \(daysLeft)d")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Calendar extension: start of the ISO week (Monday)

private extension Calendar {
    /// Returns the Monday of the week that contains `date`.
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? date
    }
}
