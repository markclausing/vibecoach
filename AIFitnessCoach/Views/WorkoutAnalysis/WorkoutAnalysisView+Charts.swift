import SwiftUI
import Charts

// Epic #65 story 65.5: split out of WorkoutAnalysisView.swift (§5 file-split).
// Pure move — no semantic changes; shared members relaxed to internal where the
// cross-file split requires it (listed in the PR body).

extension WorkoutAnalysisView {

    // MARK: Computed

    var hasSamples: Bool { !samples.isEmpty }

    private var hasSpeed: Bool { samples.contains { $0.speed != nil } }
    private var hasPower: Bool { samples.contains { $0.power != nil } }

    /// Unified cadence data source for chart + stats. First the stored samples
    /// (Strava cadence stream or HK ingest); when absent the separately fetched
    /// HK stepCount series. Zero buckets (traffic light, coffee stop) stay in
    /// for the chart; stats filter them out themselves.
    private var cadencePoints: [(timestamp: Date, spm: Double)] {
        let fromSamples = samples.compactMap { sample -> (timestamp: Date, spm: Double)? in
            guard let cadence = sample.cadence else { return nil }
            return (sample.timestamp, cadence)
        }
        if !fromSamples.isEmpty { return fromSamples }
        return hkCadenceSeries.map { (timestamp: $0.timestamp, spm: $0.value) }
    }

    /// Epic #52: we only show the cadence chart for running (HK stepCount-derived
    /// or Strava stream — both provide spm). For cycling, cadence sits as a secondary
    /// signal in its own chart flow (would become a fourth chart); out of scope.
    private var hasCadence: Bool { cadencePoints.contains { $0.spm > 0 } }
    var showCadenceChart: Bool { activity.sportCategory == .running && hasCadence }

    var secondarySeries: SecondarySeries {
        WorkoutAnalysisHelpers.chooseSecondarySeries(
            sportCategory: activity.sportCategory.rawValue,
            hasSpeed: hasSpeed,
            hasPower: hasPower
        )
    }

    var scrubbedSample: WorkoutSample? {
        guard let scrubbedDate else { return nil }
        return WorkoutAnalysisHelpers.nearestSample(
            at: scrubbedDate,
            in: samples,
            timestamp: { $0.timestamp }
        )
    }

    /// Epic #52: cadence (spm) at the scrubber position. Reads from `cadencePoints`
    /// (samples or HK fallback) so the scrubber value is also correct when the
    /// cadence comes not from the stored samples but from the HK stepCount query.
    private var scrubbedCadence: Double? {
        guard let scrubbedDate else { return nil }
        return WorkoutAnalysisHelpers.nearestSample(
            at: scrubbedDate,
            in: cadencePoints,
            timestamp: { $0.timestamp }
        )?.spm
    }

    private var chartDomain: ClosedRange<Date> {
        guard let first = samples.first?.timestamp,
              let last  = samples.last?.timestamp,
              first < last else {
            return Date()...Date().addingTimeInterval(1)
        }
        return first...last
    }

    /// Epic #44 story 44.5: HR zones derived from the profile. Friel when LTHR
    /// is set (more precise for the athlete), otherwise Karvonen on max+rest. Empty
    /// array when the user has set no thresholds — chart stays clean.
    private var heartRateChartZones: [HeartRateZone] {
        WorkoutPatternDetector.heartRateZones(from: UserProfileService.cachedProfile()) ?? []
    }

    private var powerChartZones: [PowerZone] {
        guard let ftp = UserProfileService.cachedProfile().ftp?.value, ftp > 0 else { return [] }
        return PowerZoneCalculator.coggan(ftp: ftp)
    }

    /// Pastel gradient from Z1 → Z5/Z7. Deliberately low-saturation so the zone bands
    /// do not dominate the chart. Zone 1 = blue (recovery), Z5/6/7 = warm (max).
    private func zoneColor(forIndex index: Int) -> Color {
        switch index {
        case 1: return .blue
        case 2: return .green
        case 3: return .yellow
        case 4: return .orange
        case 5: return .red
        case 6: return .pink
        default: return .purple // Z7 neuromuscular for power
        }
    }

    /// Y-domain for the HR chart. Tight around the actual data (±10 BPM margin) so
    /// we do not show empty "0-80 BPM" and "200-300 BPM" zones where there is no data.
    /// Zone bands that fall outside this range are clipped by Charts — that
    /// is exactly what we want, only show zones the user actually
    /// touched.
    private var hrYDomain: ClosedRange<Double> {
        let hrValues = samples.compactMap(\.heartRate)
        guard let minHR = hrValues.min(), let maxHR = hrValues.max() else {
            return 60...190
        }
        let lower = max(40, minHR - 10).rounded(.down)
        let upper = min(220, maxHR + 10).rounded(.up)
        return lower...upper
    }

    /// Y-domain for the secondary chart. Power/speed starts at 0 (recovery / coasting
    /// is meaningful). Upper bound with a small margin above the peak value — zone
    /// Z6/Z7 (Coggan) is automatically clipped outside this range.
    private var secondaryYDomain: ClosedRange<Double> {
        let values: [Double] = samples.compactMap { secondaryValue(of: $0) }
        guard let maxValue = values.max(), maxValue > 0 else { return 0...100 }
        switch secondarySeries {
        case .power: return 0...(maxValue + 30).rounded(.up)
        case .speed: return 0...(maxValue + 0.5).rounded(.up)
        case .none:  return 0...maxValue
        }
    }

    /// Epic #52: Y-domain for the cadence chart. Tight around the actual data so
    /// the progression within one ride is easily readable. Default 140-200 spm (typical
    /// running range) when there is no data yet, prevents an empty axis.
    private var cadenceYDomain: ClosedRange<Double> {
        let values = cadencePoints.map(\.spm).filter { $0 > 0 }
        guard let minC = values.min(), let maxC = values.max() else {
            return 140...200
        }
        let lower = max(60, minC - 10).rounded(.down)
        let upper = min(240, maxC + 10).rounded(.up)
        return lower...upper
    }

    /// Epic #52: average cadence (spm) over the non-zero points — zero buckets
    /// (traffic light, coffee stop) do not count. Nil when there is no cadence.
    var averageCadence: Double? {
        Self.cadenceStats(from: cadencePoints).avg
    }

    /// Epic #52: peak cadence (95th percentile) — not the highest outlier but the
    /// "typical top" to flatten out sprint spikes.
    var peakCadence: Double? {
        Self.cadenceStats(from: cadencePoints).peak
    }

    /// Pure helper: avg + peak (95th percentile) over non-zero cadence points.
    /// Static so that both the computed properties (chart source) and the prompt
    /// context (locally fetched series) can use it without a @State race.
    private static func cadenceStats(from points: [(timestamp: Date, spm: Double)]) -> (avg: Double?, peak: Double?) {
        let values = points.map(\.spm).filter { $0 > 0 }.sorted()
        guard !values.isEmpty else { return (nil, nil) }
        let avg = values.reduce(0, +) / Double(values.count)
        let idx = min(values.count - 1, Int((Double(values.count) * 0.95).rounded(.down)))
        return (avg, values[idx])
    }

    // MARK: Scrubber header (floating)

    var scrubberHeader: some View {
        let sample = scrubbedSample
        let timestamp = sample?.timestamp
        let elapsed = timestamp.map { $0.timeIntervalSince(activity.startDate) }

        return VStack(alignment: .leading, spacing: 10) {
            Text("DETAILS BIJ TIJDSTIP")
                .font(.caption2).fontWeight(.semibold)
                .kerning(0.5)
                .foregroundStyle(.secondary)

            if scrubbedDate == nil {
                // Not scrubbed: hint makes clear this is an interactive overlay.
                // Prevents a confusing empty card with dashes as the only content.
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
                    if showCadenceChart {
                        metricLabel(title: "spm",
                                    value: scrubbedCadence.map { String(format: "%.0f", $0) } ?? "—")
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Match TrendWidgetView card-styling: light in light mode, darker in dark.
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

    var heartRateChart: some View {
        chartCard(title: "Hartslag", unit: "BPM") {
            Chart {
                // Epic #44 story 44.5+: zone bands as a soft background. Shown
                // only when the user has set thresholds (Friel or
                // Karvonen zones). Subtle colours — the line stays prominent.
                ForEach(heartRateChartZones, id: \.index) { zone in
                    RectangleMark(
                        xStart: .value("Begin", chartDomain.lowerBound),
                        xEnd: .value("Eind", chartDomain.upperBound),
                        yStart: .value("Onder", zone.lowerBPM),
                        yEnd: .value("Boven", zone.upperBPM)
                    )
                    .foregroundStyle(zoneColor(forIndex: zone.index).opacity(0.10))
                }
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
                // Story 32.3b + UX fix: pattern pins at the **middle** of the pattern
                // range (previously `lowerBound` — that put the decoupling/drift pin
                // at the start of the ride while the effect was measured over the whole ride).
                // Now: decoupling/drift = middle of the workout, cadence fade = middle of
                // the last quarter, HR-recovery = middle of the pause.
                ForEach(Array(patterns.enumerated()), id: \.element.kind) { index, pattern in
                    let pinDate = patternMidpoint(of: pattern)
                    if let hr = nearestHeartRate(at: pinDate) {
                        PointMark(
                            x: .value("Tijd", pinDate),
                            y: .value("BPM", hr)
                        )
                        .foregroundStyle(severityColor(pattern.severity))
                        .symbolSize(160)
                        .symbol(.circle)
                        .annotation(position: .overlay) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                if let scrubbedDate {
                    RuleMark(x: .value("Scrubber", scrubbedDate))
                        .foregroundStyle(themeManager.primaryAccentColor.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1.0))
                }
            }
            .chartXScale(domain: chartDomain)
            .chartYScale(domain: hrYDomain)
            .chartXAxis(.hidden) // Time progression is already in the scrubber header.
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                    AxisValueLabel {
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

    // MARK: Secondary chart (speed or power)

    @ViewBuilder
    var secondaryChart: some View {
        let title  = secondarySeries == .speed ? "Snelheid" : "Vermogen"
        let unit   = secondarySeries == .speed ? "m/s"      : "W"
        let accent = themeManager.primaryAccentColor

        chartCard(title: title, unit: unit) {
            Chart {
                // Epic #44: Coggan power zones as a soft background — only when
                // we show power and the user has an FTP. For speed charts
                // we have (yet) no pace zones, so those stay clean.
                if secondarySeries == .power {
                    ForEach(powerChartZones, id: \.index) { zone in
                        RectangleMark(
                            xStart: .value("Begin", chartDomain.lowerBound),
                            xEnd: .value("Eind", chartDomain.upperBound),
                            yStart: .value("Onder", zone.lowerWatts),
                            yEnd: .value("Boven", zone.upperWatts ?? (zone.lowerWatts + 200))
                        )
                        .foregroundStyle(zoneColor(forIndex: zone.index).opacity(0.10))
                    }
                }
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
            .chartYScale(domain: secondaryYDomain)
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

    // MARK: - Epic #52: cadence chart for running

    /// Steps-per-minute chart below the secondary chart. Follows the same
    /// pattern as the HR chart: LineMark with catmullRom interpolation, shared
    /// scrubber, tight Y-domain. No zone bands — for running cadence there is
    /// no broadly accepted zone classification yet that we can safely
    /// render here (180 spm is becoming popular as "ideal" but is physiologically not
    /// universal — avoided so as not to evoke a normative feeling).
    @ViewBuilder
    var cadenceChart: some View {
        let accent = themeManager.primaryAccentColor
        chartCard(title: "Cadens", unit: "spm") {
            Chart {
                ForEach(cadencePoints, id: \.timestamp) { point in
                    if point.spm > 0 {
                        LineMark(
                            x: .value("Tijd", point.timestamp),
                            y: .value("spm", point.spm)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.0, lineCap: .round))
                    }
                }
                if let scrubbedDate {
                    RuleMark(x: .value("Scrubber", scrubbedDate))
                        .foregroundStyle(accent.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1.0))
                }
            }
            .chartXScale(domain: chartDomain)
            .chartYScale(domain: cadenceYDomain)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                    AxisValueLabel {
                        if let spm = value.as(Double.self) {
                            Text("\(Int(spm))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 140)
            .chartOverlay { proxy in scrubGestureLayer(proxy: proxy) }
        }
    }

    /// Story 32.3b: lookup helper for the pin y-position on the HR chart.
    private func nearestHeartRate(at date: Date) -> Double? {
        WorkoutAnalysisHelpers.nearestSample(at: date, in: samples, timestamp: { $0.timestamp })?.heartRate
    }

    // MARK: Scrubber gesture layer (shared by both charts)

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
                                // Clamp to the workout domain so dragging past the edge
                                // does not lead to an 'empty' scrubber state.
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
                // Epic #37 story 37.1c: localize the chart title (Dutch literal) before uppercasing.
                Text(String(localized: String.LocalizationValue(title)).uppercased())
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
}
