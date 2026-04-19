import SwiftUI
import Charts

/// V2.0 Sprint 1: 14-daagse trend-widget met sparklines voor Vibe Score en TRIMP/dag.
struct TrendWidgetView: View {
    let readinessRecords: [DailyReadiness]
    let activities: [ActivityRecord]

    @EnvironmentObject var themeManager: ThemeManager

    // MARK: - Data

    private var vibeHistory: [Int] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let scores = readinessRecords
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
            .map { $0.readinessScore }
        return scores.count >= 3 ? scores : [65, 70, 68, 72, 74, 71, 76, 73, 75, 76, 74, 78, 76, 76]
    }

    private var trimpHistory: [Double] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let values = (0..<14).map { offset -> Double in
            let day = cal.date(byAdding: .day, value: -(13 - offset), to: today)!
            let nextDay = cal.date(byAdding: .day, value: 1, to: day)!
            return activities
                .filter { $0.startDate >= day && $0.startDate < nextDay }
                .compactMap { $0.trimp }
                .reduce(0, +)
        }
        let hasRealData = values.contains { $0 > 0 }
        return hasRealData ? values : [80, 95, 60, 110, 105, 70, 130, 85, 112, 100, 90, 120, 108, 112]
    }

    private var currentVibe: Int { vibeHistory.last ?? 0 }
    private var currentTrimp: Int { Int(trimpHistory.last ?? 0) }

    private var vibeDelta: Int {
        guard vibeHistory.count >= 2 else { return 0 }
        return currentVibe - vibeHistory.first!
    }

    private var trimpDelta: Int {
        guard trimpHistory.count >= 2 else { return 0 }
        return Int((trimpHistory.last ?? 0) - (trimpHistory.first ?? 0))
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("14-DAAGSE TREND")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.secondary).kerning(0.5)
                .padding(.horizontal)

            HStack(spacing: 0) {
                TrendColumn(
                    label: "VIBE SCORE",
                    value: "\(currentVibe)",
                    delta: vibeDelta,
                    dataPoints: vibeHistory.map { Double($0) },
                    accentColor: themeManager.primaryAccentColor
                )

                Divider()

                TrendColumn(
                    label: "TRIMP / DAG",
                    value: "\(currentTrimp)",
                    delta: trimpDelta,
                    dataPoints: trimpHistory,
                    accentColor: themeManager.primaryAccentColor
                )
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
            .padding(.horizontal)
        }
    }
}

// MARK: - TrendColumn

private struct TrendColumn: View {
    let label: String
    let value: String
    let delta: Int
    let dataPoints: [Double]
    let accentColor: Color

    private var deltaText: String {
        delta >= 0 ? "+\(delta) 14d" : "\(delta) 14d"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption2).fontWeight(.semibold)
                .foregroundColor(.secondary).kerning(0.5)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text(deltaText)
                    .font(.caption2).fontWeight(.medium)
                    .foregroundColor(delta >= 0 ? accentColor : .orange)
            }

            Sparkline(values: dataPoints, color: accentColor)
                .frame(height: 44)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sparkline

private struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("Dag", index),
                    y: .value("Waarde", value)
                )
                .foregroundStyle(color)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Dag", index),
                    y: .value("Waarde", value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.15), color.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (values.min() ?? 0) * 0.9 ... (values.max() ?? 1) * 1.1)
        .chartLegend(.hidden)
    }
}
