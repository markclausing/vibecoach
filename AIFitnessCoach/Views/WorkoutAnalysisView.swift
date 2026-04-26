import SwiftUI
import SwiftData
import Charts

// MARK: - Epic 32 Story 32.2: Annotated Charts UI
//
// Detail-view voor één historische workout: gestapelde Swift Charts met gedeelde scrubber.
// Boven: hartslag (LineMark, BPM op y). Onder: snelheid of vermogen (AreaMark).
// Een floating header toont de exacte waardes onder de scrubber-positie.
//
// Filosofie: 'Serene' — zachte kleuren via ThemeManager, subtiele schaduwen, één primaire
// interactie (scrubben). Geen tooltips, geen popovers — alle info zit in de header.

struct WorkoutAnalysisView: View {

    let activity: ActivityRecord

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var planManager: TrainingPlanManager

    @Query private var samples: [WorkoutSample]

    @State private var scrubbedDate: Date? = nil

    init(activity: ActivityRecord) {
        self.activity = activity
        // Story 32.1 (HK) + Epic 40 (Strava): unified UUID-mapping.
        // - HealthKit-records: id is een UUID-string → wordt geparsed.
        // - Strava-records: id is numerieke string → deterministische UUID via SHA-256.
        // Dit houdt @Query type-veilig en vermijdt schema-wijziging op WorkoutSample.
        let uuid = UUID.forActivityRecordID(activity.id)
        _samples = Query(
            filter: #Predicate<WorkoutSample> { $0.workoutUUID == uuid },
            sort: \WorkoutSample.timestamp,
            order: .forward
        )
    }

    // MARK: Computed

    private var hasSamples: Bool { !samples.isEmpty }

    private var hasSpeed: Bool { samples.contains { $0.speed != nil } }
    private var hasPower: Bool { samples.contains { $0.power != nil } }

    private var secondarySeries: SecondarySeries {
        WorkoutAnalysisHelpers.chooseSecondarySeries(
            sportCategory: activity.sportCategory.rawValue,
            hasSpeed: hasSpeed,
            hasPower: hasPower
        )
    }

    private var scrubbedSample: WorkoutSample? {
        guard let scrubbedDate else { return nil }
        return WorkoutAnalysisHelpers.nearestSample(
            at: scrubbedDate,
            in: samples,
            timestamp: { $0.timestamp }
        )
    }

    private var chartDomain: ClosedRange<Date> {
        guard let first = samples.first?.timestamp,
              let last  = samples.last?.timestamp,
              first < last else {
            return Date()...Date().addingTimeInterval(1)
        }
        return first...last
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let comparison = comparisonContent {
                    coachComparisonCard(comparison)
                }
                summaryCard
                if hasSamples {
                    scrubberHeader
                        .animation(.easeOut(duration: 0.15), value: scrubbedSample?.timestamp)
                    heartRateChart
                    if secondarySeries != .none {
                        secondaryChart
                    }
                } else {
                    emptyStateCard
                }
                statsGrid
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(themeManager.backgroundGradient.ignoresSafeArea())
        .navigationTitle(activity.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Coach Comparison (Story 33.4)

    /// Resultaat van de intent-vs-execution-analyse als er een match-plan is.
    /// `nil` als geen plan, geen match op kalenderdag of `.insufficientData` —
    /// in die gevallen tonen we de kaart niet (geen ruis).
    private var comparisonContent: (verdict: IntentExecutionVerdict, plannedActivity: String)? {
        guard let plan = planManager.activePlan,
              let plannedMatch = plan.workouts.first(matching: activity) else {
            return nil
        }
        let verdict = IntentExecutionAnalyzer.analyze(
            planned: plannedMatch,
            actual: activity,
            maxHeartRate: HeartRateZones.defaultMaxHeartRate
        )
        if case .insufficientData = verdict { return nil }
        return (verdict, plannedMatch.activityType)
    }

    private func coachComparisonCard(_ content: (verdict: IntentExecutionVerdict, plannedActivity: String)) -> some View {
        let style = comparisonStyle(for: content.verdict)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: style.icon)
                    .font(.title3)
                    .foregroundStyle(style.color)
                Text(style.headline)
                    .font(.headline)
                Spacer()
            }
            Text(comparisonSubtitle(for: content.verdict, planned: content.plannedActivity))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style.color.opacity(0.35), lineWidth: 1)
        )
    }

    private struct ComparisonStyle {
        let color: Color
        let icon: String
        let headline: String
    }

    private func comparisonStyle(for verdict: IntentExecutionVerdict) -> ComparisonStyle {
        switch verdict {
        case .match:
            return ComparisonStyle(color: .green,
                                   icon: "checkmark.circle.fill",
                                   headline: "Plan behaald")
        case .typeMismatch:
            return ComparisonStyle(color: .orange,
                                   icon: "exclamationmark.triangle.fill",
                                   headline: "Type wijkt af")
        case .overload(let pct):
            return ComparisonStyle(color: Color(red: 0.93, green: 0.42, blue: 0.21),
                                   icon: "flame.fill",
                                   headline: "Boven plan (\(String(format: "%+.0f", pct))% TRIMP)")
        case .underload(let pct):
            return ComparisonStyle(color: .blue,
                                   icon: "drop.fill",
                                   headline: "Onder plan (\(String(format: "%+.0f", pct))% TRIMP)")
        case .insufficientData:
            // Wordt al uitgefilterd in `comparisonContent`, maar we behouden een
            // sane fallback zodat de switch totaal is.
            return ComparisonStyle(color: .secondary,
                                   icon: "questionmark.circle",
                                   headline: "Geen vergelijking")
        }
    }

    private func comparisonSubtitle(for verdict: IntentExecutionVerdict, planned plannedActivity: String) -> String {
        switch verdict {
        case .match:
            return "Gepland: \(plannedActivity) → Uitgevoerd: \(activity.displayName). Type én belasting binnen marge."
        case .typeMismatch(let plannedType, let actualType):
            let actualLabel = actualType?.displayName ?? "onbepaald"
            return "Gepland: \(plannedActivity) (\(plannedType.displayName)) → Uitgevoerd: \(activity.displayName) (\(actualLabel))."
        case .overload, .underload:
            return "Gepland: \(plannedActivity) → Uitgevoerd: \(activity.displayName)."
        case .insufficientData:
            return ""
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        HStack(spacing: 16) {
            Image(systemName: sportIcon)
                .font(.title2)
                .foregroundStyle(themeManager.primaryAccentColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.displayName)
                    .font(.headline)
                Text(activity.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            sessionTypeMenu
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: Sessie-type override (Epic 33 Story 33.1b)

    /// Menu waarmee de gebruiker de auto-classificatie kan overrulen. Wijzigingen
    /// worden direct in SwiftData bewaard en propageren via observation naar de
    /// ChatViewModel-cache (zie `cacheLastWorkoutFeedback`).
    private var sessionTypeMenu: some View {
        Menu {
            ForEach(SessionType.allCases) { type in
                Button {
                    setSessionType(type)
                } label: {
                    Label(type.displayName, systemImage: type.icon)
                }
            }
            Divider()
            Button(role: .destructive) {
                setSessionType(nil)
            } label: {
                Label("Type wissen", systemImage: "xmark.circle")
            }
            .disabled(activity.sessionType == nil)
        } label: {
            HStack(spacing: 6) {
                if let type = activity.sessionType {
                    Image(systemName: type.icon)
                        .font(.caption)
                    Text(type.displayName)
                        .font(.caption).fontWeight(.medium)
                } else {
                    Image(systemName: "questionmark.circle")
                        .font(.caption)
                    Text("Type")
                        .font(.caption).fontWeight(.medium)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(themeManager.primaryAccentColor)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(themeManager.primaryAccentColor.opacity(0.12))
            .clipShape(Capsule())
        }
    }

    private func setSessionType(_ type: SessionType?) {
        activity.sessionType = type
        try? modelContext.save()
    }

    private var sportIcon: String {
        switch activity.sportCategory {
        case .running:   return "figure.run"
        case .cycling:   return "figure.outdoor.cycle"
        case .swimming:  return "figure.pool.swim"
        case .strength:  return "figure.strengthtraining.traditional"
        case .walking:   return "figure.walk"
        case .triathlon: return "figure.mixed.cardio"
        case .other:     return "heart.fill"
        }
    }

    // MARK: Scrubber header (floating)

    private var scrubberHeader: some View {
        let sample = scrubbedSample
        let timestamp = sample?.timestamp
        let elapsed = timestamp.map { $0.timeIntervalSince(activity.startDate) }

        return VStack(alignment: .leading, spacing: 10) {
            Text("DETAILS BIJ TIJDSTIP")
                .font(.caption2).fontWeight(.semibold)
                .kerning(0.5)
                .foregroundStyle(.secondary)

            if scrubbedDate == nil {
                // Niet-gescrubd: hint maakt duidelijk dat dit een interactief overlay is.
                // Voorkomt verwarrende lege kaart met streepjes als enige inhoud.
                HStack(spacing: 10) {
                    Image(systemName: "hand.draw.fill")
                        .font(.body)
                        .foregroundStyle(themeManager.primaryAccentColor.opacity(0.6))
                    Text("Sleep over de grafiek voor details op een specifiek moment")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tijd")
                            .font(.caption2).foregroundStyle(.secondary).kerning(0.3)
                        Text(formatElapsed(elapsed))
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    metricLabel(title: "BPM",
                                value: sample?.heartRate.map { String(format: "%.0f", $0) } ?? "—")
                    secondaryMetricLabel(for: sample)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Match TrendWidgetView card-styling: licht in light mode, donkerder in dark.
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private func metricLabel(title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption2).foregroundStyle(.secondary).kerning(0.3)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func secondaryMetricLabel(for sample: WorkoutSample?) -> some View {
        switch secondarySeries {
        case .speed:
            metricLabel(title: "m/s",
                        value: sample?.speed.map { String(format: "%.1f", $0) } ?? "—")
        case .power:
            metricLabel(title: "W",
                        value: sample?.power.map { String(format: "%.0f", $0) } ?? "—")
        case .none:
            EmptyView()
        }
    }

    // MARK: Heart rate chart

    private var heartRateChart: some View {
        chartCard(title: "Hartslag", unit: "BPM") {
            Chart {
                ForEach(samples) { sample in
                    if let hr = sample.heartRate {
                        LineMark(
                            x: .value("Tijd", sample.timestamp),
                            y: .value("BPM", hr)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(themeManager.primaryAccentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.0, lineCap: .round))
                    }
                }
                if let scrubbedDate {
                    RuleMark(x: .value("Scrubber", scrubbedDate))
                        .foregroundStyle(themeManager.primaryAccentColor.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1.0))
                }
            }
            .chartXScale(domain: chartDomain)
            .chartXAxis(.hidden) // Tijdsverloop staat al in de scrubber-header.
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                    AxisValueLabel() {
                        if let bpm = value.as(Double.self) {
                            Text("\(Int(bpm))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 160)
            .chartOverlay { proxy in scrubGestureLayer(proxy: proxy) }
        }
    }

    // MARK: Secondary chart (speed of power)

    @ViewBuilder
    private var secondaryChart: some View {
        let title  = secondarySeries == .speed ? "Snelheid" : "Vermogen"
        let unit   = secondarySeries == .speed ? "m/s"      : "W"
        let accent = themeManager.primaryAccentColor

        chartCard(title: title, unit: unit) {
            Chart {
                ForEach(samples) { sample in
                    if let value = secondaryValue(of: sample) {
                        AreaMark(
                            x: .value("Tijd", sample.timestamp),
                            y: .value(unit, value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(colors: [accent.opacity(0.55), accent.opacity(0.05)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                    }
                }
                if let scrubbedDate {
                    RuleMark(x: .value("Scrubber", scrubbedDate))
                        .foregroundStyle(accent.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1.0))
                }
            }
            .chartXScale(domain: chartDomain)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                    AxisValueLabel().font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(height: 140)
            .chartOverlay { proxy in scrubGestureLayer(proxy: proxy) }
        }
    }

    private func secondaryValue(of sample: WorkoutSample) -> Double? {
        switch secondarySeries {
        case .speed: return sample.speed
        case .power: return sample.power
        case .none:  return nil
        }
    }

    // MARK: Scrubber gesture layer (gedeeld door beide charts)

    private func scrubGestureLayer(proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let origin = geo[plotFrame].origin
                            let xInPlot = max(0, value.location.x - origin.x)
                            if let date: Date = proxy.value(atX: xInPlot) {
                                // Klem op het workout-domein zodat slepen voorbij de rand
                                // niet leidt tot een 'lege' scrubber-staat.
                                scrubbedDate = min(max(date, chartDomain.lowerBound), chartDomain.upperBound)
                            }
                        }
                )
        }
    }

    // MARK: Chart card frame

    private func chartCard<Content: View>(title: String, unit: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.caption2).fontWeight(.semibold)
                    .kerning(0.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            content()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: Empty state

    private var emptyStateCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.title)
                .foregroundStyle(themeManager.primaryAccentColor.opacity(0.6))
            Text("Nog geen samples beschikbaar")
                .font(.headline)
            Text("Deep Sync loopt op de achtergrond — kom over een paar minuten terug om de fysiologische details te zien.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: Stats grid (uit ActivityRecord — altijd beschikbaar, ook voor Strava)

    private var statsGrid: some View {
        let avgHR = activity.averageHeartrate.map { String(format: "%.0f bpm", $0) } ?? "—"
        let trimp = activity.trimp.map { String(format: "%.0f", $0) } ?? "—"
        let distanceKm = activity.distance > 0 ? String(format: "%.2f km", activity.distance / 1000) : "—"
        let movingMin = String(format: "%d min", max(1, activity.movingTime / 60))

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statTile(label: "Duur", value: movingMin, icon: "clock")
            statTile(label: "Afstand", value: distanceKm, icon: "ruler")
            statTile(label: "Gem. hartslag", value: avgHR, icon: "heart")
            statTile(label: "TRIMP", value: trimp, icon: "flame")
        }
    }

    private func statTile(label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: Helpers

    private func formatElapsed(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Recente Workouts sectie (Dashboard)

/// Sectie onder de TrendWidget op het Dashboard met de meest recente HealthKit-workouts.
/// Strava-records worden ook getoond (als context) maar zijn niet klikbaar — zij hebben geen
/// `WorkoutSample`-data omdat de Deep Sync alleen HealthKit-bron koppelt.
struct RecentWorkoutsSection: View {

    @Query(sort: \ActivityRecord.startDate, order: .reverse) private var allActivities: [ActivityRecord]
    @EnvironmentObject var themeManager: ThemeManager

    /// Aantal rijen dat we tonen. Default 7 — past op één scherm zonder de scroll te dominate.
    let limit: Int

    init(limit: Int = 7) {
        self.limit = limit
    }

    private var recent: [ActivityRecord] {
        Array(allActivities.prefix(limit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RECENTE WORKOUTS")
                    .font(.caption).fontWeight(.semibold)
                    .kerning(0.5)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)

            if recent.isEmpty {
                Text("Nog geen workouts gevonden — synchroniseer met HealthKit of Strava.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    ForEach(recent) { activity in
                        RecentWorkoutRow(activity: activity)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// Eén rij in de "Recente Workouts" sectie. Klikbaar als `id` parseerbaar is als UUID
/// (= HealthKit). Strava-records tonen we als statische rij zonder chevron.
struct RecentWorkoutRow: View {
    let activity: ActivityRecord
    @EnvironmentObject var themeManager: ThemeManager

    private var isHealthKit: Bool { UUID(uuidString: activity.id) != nil }

    var body: some View {
        Group {
            if isHealthKit {
                NavigationLink {
                    WorkoutAnalysisView(activity: activity)
                } label: {
                    rowContent(showChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                rowContent(showChevron: false)
            }
        }
    }

    private func rowContent(showChevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: sportIcon)
                .font(.body)
                .foregroundStyle(themeManager.primaryAccentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.displayName)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                Text(activity.startDate.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if activity.distance > 0 {
                Text(String(format: "%.1f km", activity.distance / 1000))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        // Match TrendWidgetView-styling — `Color(.systemBackground)` is wit in light mode
        // en donker in dark mode (auto-aanpassend), met dezelfde subtiele schaduw.
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private var sportIcon: String {
        switch activity.sportCategory {
        case .running:   return "figure.run"
        case .cycling:   return "figure.outdoor.cycle"
        case .swimming:  return "figure.pool.swim"
        case .strength:  return "figure.strengthtraining.traditional"
        case .walking:   return "figure.walk"
        case .triathlon: return "figure.mixed.cardio"
        case .other:     return "heart.fill"
        }
    }
}
