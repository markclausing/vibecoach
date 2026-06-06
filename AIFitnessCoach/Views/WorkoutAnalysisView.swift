import SwiftUI
import SwiftData
import Charts

// MARK: - Epic 32 Story 32.2: Annotated Charts UI
//
// Detail view for one historical workout: stacked Swift Charts with a shared scrubber.
// Top: heart rate (LineMark, BPM on y). Bottom: speed or power (AreaMark).
// A floating header shows the exact values under the scrubber position.
//
// Philosophy: 'Serene' — soft colours via ThemeManager, subtle shadows, one primary
// interaction (scrubbing). No tooltips, no popovers — all info lives in the header.

struct WorkoutAnalysisView: View {

    let activity: ActivityRecord

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var planManager: TrainingPlanManager

    @Query private var samples: [WorkoutSample]
    /// Epic #48: active goals + all activities + readiness for the blueprint and
    /// periodization context that the Coach analysis receives.
    @Query(sort: \FitnessGoal.targetDate, order: .forward) private var goals: [FitnessGoal]
    @Query(sort: \ActivityRecord.startDate, order: .forward) private var allActivitiesForContext: [ActivityRecord]
    @Query(sort: \DailyReadiness.date, order: .reverse) private var readinessRecords: [DailyReadiness]

    @State private var scrubbedDate: Date?

    // MARK: - Story 32.3b: pattern-detectie + AI-narrative

    @State private var patterns: [WorkoutPattern] = []
    @State private var insightState: InsightState = .idle
    @State private var selectedPatternKind: WorkoutPatternKind?
    /// Independent task for the detect/AI flow. Deliberately unstructured so that
    /// a pull-to-refresh gesture that cancels SwiftUI's `refreshable` task
    /// prematurely (known UX glitch when the gesture ends before the Gemini call
    /// is done) does not take the worker down with it — otherwise the coach text
    /// disappears without replacement into `.idle`.
    @State private var insightTask: Task<Void, Never>?

    private enum InsightState: Equatable {
        case idle                 // No patterns yet or no API key
        case loading              // AI call in flight
        case loaded(String)       // Coach narrative ready
        case unavailable(String)  // Patterns present, but no AI call possible (key/error)
    }

    init(activity: ActivityRecord) {
        self.activity = activity
        // Story 32.1 (HK) + Epic 40 (Strava): unified UUID mapping.
        // - HealthKit records: id is a UUID string → gets parsed.
        // - Strava records: id is a numeric string → deterministic UUID via SHA-256.
        // This keeps @Query type-safe and avoids a schema change on WorkoutSample.
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

    /// Epic #52 cross-source fix: HK-`stepCount`-derived cadence, fetched separately
    /// when the stored samples contain no cadence. This happens when the displayed
    /// `ActivityRecord` is a Strava record that "won" over an HK counterpart during
    /// dedup — the Watch steps then live under a different UUID than the view
    /// requests. See `loadCadenceFallbackIfNeeded()`.
    @State private var hkCadenceSeries: [TimedValue] = []

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
    private var showCadenceChart: Bool { activity.sportCategory == .running && hasCadence }

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
    private var averageCadence: Double? {
        Self.cadenceStats(from: cadencePoints).avg
    }

    /// Epic #52: peak cadence (95th percentile) — not the highest outlier but the
    /// "typical top" to flatten out sprint spikes.
    private var peakCadence: Double? {
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

    /// Epic #48: latest readiness record (from today or more recent), used
    /// as input for `PeriodizationEngine.evaluateAllGoals` so the
    /// IntentModifier evaluates the VibeScore threshold correctly.
    private var latestReadinessForContext: DailyReadiness? {
        readinessRecords.first
    }

    /// Epic #48: stable fingerprint for the blueprint + periodization state.
    /// Changes as soon as a goal is added/removed, a milestone
    /// is achieved, or a phase transition occurs. Collision-free enough for
    /// cache invalidation of the Coach analysis — no cryptographic hash needed.
    private func goalsFingerprint(blueprints: [BlueprintCheckResult],
                                   periodization: [PeriodizationResult]) -> String {
        if blueprints.isEmpty && periodization.isEmpty { return "g_empty" }
        let bpParts = blueprints.map { result in
            "\(result.goal.id):\(result.satisfiedCount)/\(result.totalCount)"
        }
        let phaseParts = periodization.map { result in
            "\(result.goal.id):\(result.phase.rawValue)"
        }
        return (bpParts + phaseParts).joined(separator: "|")
    }

    /// Epic #49: cache key for the weather context. Changes as soon as HK metadata is
    /// updated (e.g. after DeepSync or a later ingest), so that a previously
    /// generated Coach analysis without heat context is replaced by
    /// a new one with the heat weighting in it. "w_empty" when no weather data —
    /// a stable key when absent so we do not keep regenerating.
    /// Epic #52: adds the range peak so that a later hourly-range fetch
    /// (which can override the snapshot) also triggers a fresh cache entry.
    private func weatherFingerprint(_ activity: ActivityRecord,
                                    range: HistoricalWeatherService.WeatherRange?) -> String {
        var parts: [String] = []
        if let t = activity.temperatureCelsius { parts.append("t\(Int(t.rounded()))") }
        if let h = activity.humidityPercent { parts.append("h\(Int(h.rounded()))") }
        if let peak = range?.peakTempCelsius { parts.append("pt\(Int(peak.rounded()))") }
        if let avg = range?.avgTempCelsius { parts.append("at\(Int(avg.rounded()))") }
        if let peak = range?.peakHumidityPercent { parts.append("ph\(Int(peak.rounded()))") }
        if let avg = range?.avgHumidityPercent { parts.append("ah\(Int(avg.rounded()))") }
        return parts.isEmpty ? "w_empty" : parts.joined(separator: "_")
    }

    /// Epic #52: cache fingerprint for running cadence. Changes as soon as new
    /// cadence samples come in (DeepSync or Strava stream ingest), so that a
    /// previously generated Coach analysis that had no cadence context yet,
    /// is replaced by a new one with the spm weighting in it. "c_empty"
    /// when there is no cadence data — a stable key, no unnecessary invalidations.
    private func cadenceFingerprint() -> String {
        guard activity.sportCategory == .running else { return "c_na" }
        var parts: [String] = []
        if let avg = averageCadence { parts.append("a\(Int(avg.rounded()))") }
        if let peak = peakCadence { parts.append("p\(Int(peak.rounded()))") }
        return parts.isEmpty ? "c_empty" : parts.joined(separator: "_")
    }

    /// Epic #52 cross-source fix: fills `hkCadenceSeries` with HK-`stepCount`-
    /// derived cadence if (a) it is a running workout and (b) the stored
    /// samples contain no cadence. The latter happens when the displayed
    /// record is a Strava record that won over the HK counterpart during dedup — the
    /// Watch steps then live under the HK workout UUID, not the Strava UUID that
    /// the `@Query` requests. The direct HK query on `[start, end]` bypasses that.
    /// Fail-tolerant: when there is no HK data or a query error, the series stays empty and
    /// the chart disappears silently (no cadence source available).
    private func loadCadenceFallbackIfNeeded() async {
        guard activity.sportCategory == .running else { return }
        guard !samples.contains(where: { ($0.cadence ?? 0) > 0 }) else { return }

        let end = activity.startDate.addingTimeInterval(TimeInterval(max(60, activity.movingTime)))
        let series = (try? await WorkoutSampleIngestService().fetchStepCadence(
            start: activity.startDate, end: end
        )) ?? []
        hkCadenceSeries = series
    }

    /// Epic #52: helper to fetch the hourly weather range for this workout.
    /// Returns `nil` when there are no GPS coords on the record (HK-only rides)
    /// or when the API fails — the caller then falls back to the snapshot in
    /// `activity.temperatureCelsius`/`humidityPercent`. Fail-tolerant so that
    /// an offline user or API timeout does not block the Coach analysis.
    private func fetchWeatherRange() async -> HistoricalWeatherService.WeatherRange? {
        guard let lat = activity.startLatitude, let lon = activity.startLongitude else {
            return nil
        }
        let end = activity.startDate.addingTimeInterval(TimeInterval(max(60, activity.movingTime)))
        do {
            return try await HistoricalWeatherService().fetchWeatherRange(
                latitude: lat, longitude: lon,
                startDate: activity.startDate, endDate: end
            )
        } catch {
            AppLoggers.weather.error("Hourly weer-range fetch faalde voor activity \(activity.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Combines the set thresholds into a short key. Empty thresholds are
    /// ignored; the result is empty-string-like ("p_empty") when the user has set
    /// no thresholds. Not cryptographic — just collision-free enough
    /// for cache invalidation of the Coach analysis.
    private func profileFingerprint(_ profile: UserPhysicalProfile) -> String {
        let parts: [String?] = [
            profile.maxHeartRate.map { "m\(Int($0.value))" },
            profile.restingHeartRate.map { "r\(Int($0.value))" },
            profile.lactateThresholdHR.map { "l\(Int($0.value))" },
            profile.ftp.map { "f\(Int($0.value))" }
        ]
        let nonNil = parts.compactMap { $0 }
        return nonNil.isEmpty ? "p_empty" : nonNil.joined(separator: "_")
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let comparison = comparisonContent {
                    coachComparisonCard(comparison)
                }
                summaryCard
                if !patterns.isEmpty {
                    patternChipsRow
                }
                insightCard
                if hasSamples {
                    scrubberHeader
                        .animation(.easeOut(duration: 0.15), value: scrubbedSample?.timestamp)
                    heartRateChart
                    if secondarySeries != .none {
                        secondaryChart
                    }
                    if showCadenceChart {
                        cadenceChart
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
        .task(id: samples.count) {
            await computePatternsAndLoadInsight()
        }
        .onDisappear {
            insightTask?.cancel()
            insightTask = nil
        }
        .refreshable {
            // Epic #44 story 44.5 + 44.6 testflow: pull-to-refresh empties the
            // `WorkoutInsightCache` entry for this workout and repeats the detect/
            // generate flow with the current profile values. Useful to see calibration
            // changes (new LTHR/max in Settings) reflected on an
            // existing workout without having to wait for a natural
            // pattern-fingerprint shift.
            //
            // The Gemini call can take 1-3s — longer than SwiftUI's refreshable task
            // sometimes waits before it cancels. That is why the worker runs as an unstructured
            // `Task` (survives refreshable cancellation), and we only await here
            // on a short gating so the pull spinner does not flash instantly. The
            // in-card "Coach analyseert…" spinner shows the real progress.
            insightTask?.cancel()
            insightTask = Task { await refreshAnalysis() }
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
    }

    /// Hard-invalidate path: throws away the cache entry for this one record and repeats
    /// `computePatternsAndLoadInsight()`. Under the hood it calls the same detect
    /// + AI flow as the initial `.task`, so the loading state flickers correctly.
    private func refreshAnalysis() async {
        WorkoutInsightCache().invalidate(activityID: activity.id)
        await computePatternsAndLoadInsight()
    }

    // MARK: - Story 32.3b: pattern detection + cache + AI narrative

    /// Runs as soon as the samples for this workout have arrived. Detects patterns,
    /// looks in the cache, and otherwise kicks off a Gemini call. Uses
    /// `WorkoutPatternFormatter.fingerprint` for the cache key so that re-classification
    /// (story 40.4 / 32.1 follow-ups) automatically triggers a new analysis.
    private func computePatternsAndLoadInsight() async {
        // Epic #44 story 44.5: turn on the zone gates as soon as the user has set LTHR or
        // max+rest. Without profile values the detector falls back
        // to the population-global behaviour from before 44.5.
        // Epic #49: with empty samples (typically Strava-only walks — Strava
        // provides no 5s buckets for walking, only for cycling/running) the
        // detector output stays empty, but we do generate a coach frame based
        // on activity fields + weather context. No samples ≠ no analysis.
        let detected: [WorkoutPattern] = samples.isEmpty
            ? []
            : WorkoutPatternDetector.detectAll(
                in: samples,
                profile: UserProfileService.cachedProfile()
              )
        patterns = detected
        // Epic #47 follow-up: generate a Coach analysis even with empty patterns
        // (positive execution confirmation). The system instruction then says
        // "write a short positive frame".

        // Epic #48: blueprint and periodization context per active goal. Reuses
        // the same formatters the chat coach already uses so the format
        // stays identical. `BlueprintChecker.checkAllGoals` filters itself on goals
        // with a blueprint type; `PeriodizationEngine.evaluateAllGoals` works on all
        // uncompleted goals.
        let activeGoals = goals.filter { !$0.isCompleted && Date() < $0.targetDate }
        let blueprintResults = BlueprintChecker.checkAllGoals(activeGoals, activities: allActivitiesForContext)
        let periodizationResults = PeriodizationEngine.evaluateAllGoals(
            activeGoals,
            activities: allActivitiesForContext,
            latestReadinessScore: latestReadinessForContext?.readinessScore
        )
        let goalsContext = BlueprintContextFormatter.format(results: blueprintResults)
        let periodizationContext = periodizationResults
            .map { $0.coachingContext }
            .joined(separator: "\n\n")

        // Epic #52: fetch the hourly weather range before the cache check — the range
        // goes into the fingerprint, so without a fetch a new range would not
        // trigger cache invalidation. For records without GPS coords this
        // call falls back quickly to nil and the fingerprint contribution is stable.
        let weatherRange = await fetchWeatherRange()

        // Epic #52 cross-source fix: if the stored samples have no cadence
        // but it is a running workout, fetch the cadence directly from
        // HealthKit (stepCount over [start, end]). This covers the case where a
        // Strava record won during dedup and the Watch steps live under the HK UUID.
        await loadCadenceFallbackIfNeeded()

        let cache = WorkoutInsightCache()
        // Epic #44 + #48 update: the cache key combines the pattern fingerprint with
        // the profile fingerprint and a goals fingerprint. A change in
        // LTHR/max/FTP, milestone status or phase transition invalidates the cache
        // automatically — otherwise a stale framing would stay hanging in the UI.
        let fingerprint = WorkoutPatternFormatter.fingerprint(for: detected)
            + "|" + profileFingerprint(UserProfileService.cachedProfile())
            + "|" + goalsFingerprint(blueprints: blueprintResults, periodization: periodizationResults)
            + "|" + weatherFingerprint(activity, range: weatherRange)
            + "|" + cadenceFingerprint()
        if let cached = cache.cached(for: activity.id, fingerprint: fingerprint) {
            insightState = .loaded(cached)
            return
        }

        insightState = .loading
        let service = WorkoutInsightService()
        // Epic #44 update: pass rich context so the coach can weigh the session type
        // (threshold work vs. recovery) and the personal zones — no more
        // population assumptions about what "high" or "easy" means for you.
        // Epic #47: pause-recovery events as a separate layer in the prompt so the
        // coach can positively frame excellent recovery even when there is no pin.
        let profile = UserProfileService.cachedProfile()
        let referenceHR = WorkoutPatternDetector.referenceHeartRate(from: profile)
            ?? WorkoutPatternDetector.referenceHRFallback
        let recoveryEvents = PauseDetector.detect(in: samples).map { event in
            WorkoutInsightService.RecoveryEventSummary(
                durationSeconds: event.durationSeconds,
                drop: event.drop,
                qualityLabel: recoveryQualityLabel(drop: event.drop, referenceHR: referenceHR)
            )
        }
        // Epic #52: cadence stats for running. For cycling we leave these nil so
        // the Coach does not try to make a cadence connection where the prompt rules
        // explicitly say "running only".
        let runningAvgCadence = activity.sportCategory == .running ? averageCadence : nil
        let runningPeakCadence = activity.sportCategory == .running ? peakCadence : nil

        let context = WorkoutInsightService.InsightContext(
            sportLabel: activity.sportCategory.displayName,
            durationMinutes: max(1, activity.movingTime / 60),
            sessionTypeLabel: activity.sessionType?.displayName,
            title: activity.displayName,
            zones: WorkoutPatternDetector.heartRateZones(from: profile),
            maxHeartRate: profile.maxHeartRate?.value,
            lactateThresholdHR: profile.lactateThresholdHR?.value,
            ftp: profile.ftp?.value,
            recoveryEvents: recoveryEvents,
            goalsContext: goalsContext.isEmpty ? nil : goalsContext,
            periodizationContext: periodizationContext.isEmpty ? nil : periodizationContext,
            temperatureCelsius: activity.temperatureCelsius,
            humidityPercent: activity.humidityPercent,
            peakTempCelsius: weatherRange?.peakTempCelsius,
            avgTempCelsius: weatherRange?.avgTempCelsius,
            peakHumidityPercent: weatherRange?.peakHumidityPercent,
            avgHumidityPercent: weatherRange?.avgHumidityPercent,
            averageCadenceSPM: runningAvgCadence,
            peakCadenceSPM: runningPeakCadence
        )
        do {
            let text = try await service.generateInsight(
                patterns: detected,
                context: context
            )
            cache.store(text, for: activity.id, fingerprint: fingerprint)
            insightState = .loaded(text)
        } catch is CancellationError {
            // Task cancellation = a new call underway or the view navigated away. Do not
            // complain in the UI; the next `.task`/refresh handles it. Set the
            // state back to .idle so we do not stay hanging on the spinner
            // forever if no new call comes.
            insightState = .idle
        } catch {
            insightState = .unavailable(error.localizedDescription)
        }
    }

    // MARK: Pattern chips

    private var patternChipsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(patterns.enumerated()), id: \.element.kind) { index, pattern in
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) {
                                selectedPatternKind = (selectedPatternKind == pattern.kind) ? nil : pattern.kind
                            }
                        } label: {
                            patternChip(pattern, index: index, selected: selectedPatternKind == pattern.kind)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let kind = selectedPatternKind,
               let pattern = patterns.first(where: { $0.kind == kind }) {
                patternDetailCard(pattern)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func patternChip(_ pattern: WorkoutPattern, index: Int, selected: Bool) -> some View {
        let color = severityColor(pattern.severity)
        return HStack(spacing: 6) {
            // Numbered badge (1-9 via SF Symbol). Maps 1-to-1 onto the HR chart as a
            // PointMark annotation so the user sees directly which pin belongs to which pattern.
            Image(systemName: "\(index + 1).circle.fill")
                .font(.subheadline)
                .foregroundStyle(color)
            Text(patternShortLabel(pattern.kind))
                .font(.caption.weight(.semibold))
            Text(patternValueLabel(pattern))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(selected ? 0.22 : 0.10)))
        .overlay(Capsule().strokeBorder(color.opacity(selected ? 0.60 : 0.30), lineWidth: selected ? 1.5 : 1))
    }

    /// Inline detail card that opens as soon as a pattern chip is tapped. Three
    /// sections: **Wat het meet** (general physiological explanation per kind), **Drempels**
    /// (the severity thresholds the detector applies) and **Op deze rit** (the actual
    /// `pattern.detail` with measurement). Deliberately no popover/sheet — extra context next to
    /// what the user already sees, not a secondary flow.
    private func patternDetailCard(_ pattern: WorkoutPattern) -> some View {
        let color = severityColor(pattern.severity)
        let info = patternExplanation(pattern.kind)
        return VStack(alignment: .leading, spacing: 10) {
            detailSection(title: "Wat het meet", body: info.description)
            detailSection(title: "Drempels", body: info.thresholds)
            detailSection(title: "Op deze rit", body: pattern.detail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func detailSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // Epic #37 story 37.1c: localize the title (passed as a Dutch literal) before
            // uppercasing. `body` is already localized by the caller.
            Text(String(localized: String.LocalizationValue(title)).uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
            Text(body)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Human-readable explanation per pattern kind for the detail card. Short sentence about
    /// physiological meaning + threshold context, separate from the actual measurement of
    /// this ride. Source thresholds match the constants in `WorkoutPatternDetector`.
    private func patternExplanation(_ kind: WorkoutPatternKind) -> (description: String, thresholds: String) {
        switch kind {
        case .aerobicDecoupling:
            return (
                description: String(localized: "Vergelijkt de hartslag/intensiteit-ratio in helft 1 versus helft 2 van je rit. Als de ratio stijgt, deed je hart in de tweede helft meer werk per watt of m/s — een teken dat je aerobic ceiling onder druk stond."),
                thresholds: String(localized: "<3% stabiel · 3–5% mild · 5–8% moderate · >8% significant. Wordt niet gemeten bij stop-and-go-ritten (te variabele intensiteit).")
            )
        case .cardiacDrift:
            return (
                description: String(localized: "HR-stijging tussen helft 1 en helft 2, los van intensiteit. Bij gelijkmatige inspanning duidt drift op vermoeidheid, hitte of dehydratie. Wordt alleen gemeten in Z1–Z3; drift in Z4–Z5 is verwacht gedrag bij drempel-/VO2max-werk."),
                thresholds: String(localized: "<3% stabiel · 3–5% mild · 5–8% moderate · >8% significant.")
            )
        case .cadenceFade:
            return (
                description: String(localized: "Daling van je gemiddelde cadans tussen het eerste en laatste kwart. Zero-cadence-momenten (verkeerslicht, koffiestop) worden uit de meting gefilterd. Een fors verschil duidt op spiervermoeidheid of bewust temperen aan het einde."),
                thresholds: String(localized: "3 mild · 5 moderate · 10 significant — eenheden zijn RPM bij cycling, SPM bij lopen.")
            )
        case .heartRateRecovery:
            return (
                description: String(localized: "Hoeveel zakte je hartslag tijdens een rust-pauze (≥45s, power+cadence beide ≈ 0) ten opzichte van de piek-binnen-pauze. Snelle daling = sterk parasympatisch herstel; trage daling kan vermoeidheid, hitte of cumulatieve belasting indiceren. Alleen pauzes ≥90s zijn pin-waardig."),
                thresholds: String(localized: "Drop als percentage van LTHR: ≥15% uitstekend (geen pin) · 12–15% mild · 9–12% moderate · <9% significant.")
            )
        }
    }

    /// Middle of the pattern range — pin position on the HR chart. Decoupling/drift
    /// use the whole workout duration, so midpoint = middle of the ride. Cadence
    /// fade and HR-recovery have narrower ranges (last quarter, pause duration),
    /// so the midpoint falls deliberately within the measurement range there.
    private func patternMidpoint(of pattern: WorkoutPattern) -> Date {
        let mid = (pattern.range.lowerBound.timeIntervalSince1970
                   + pattern.range.upperBound.timeIntervalSince1970) / 2
        return Date(timeIntervalSince1970: mid)
    }

    private func patternShortLabel(_ kind: WorkoutPatternKind) -> String {
        switch kind {
        case .aerobicDecoupling: return "Decoupling"
        case .cardiacDrift:      return "Cardiac drift"
        case .cadenceFade:       return "Cadence fade"
        case .heartRateRecovery: return "HR-recovery"
        }
    }

    private func patternValueLabel(_ pattern: WorkoutPattern) -> String {
        switch pattern.kind {
        case .aerobicDecoupling, .cardiacDrift:
            return String(format: "%.1f%%", pattern.value)
        case .cadenceFade:
            return String(format: "−%.0f", pattern.value)
        case .heartRateRecovery:
            return String(format: "%.0f BPM", pattern.value)
        }
    }

    private func severityColor(_ severity: WorkoutPattern.Severity) -> Color {
        switch severity {
        case .mild:        return .green
        case .moderate:    return .orange
        case .significant: return .red
        }
    }

    /// Epic #47: translates a pause-recovery drop into a label for the coach prompt.
    /// Thresholds match the pin boundaries in `WorkoutPatternDetector` so the label and
    /// the possible pin are consistent — a "matig" event belongs to a moderate pin.
    /// Epic #37 story 37.1c: NOT localized — this label feeds the coach prompt
    /// (WorkoutInsightService), not the UI. Prompt-coupled strings stay Dutch until 37.4.
    private func recoveryQualityLabel(drop: Double, referenceHR: Double) -> String {
        guard referenceHR > 0 else { return "onbekend" }
        let ratio = drop / referenceHR
        if ratio >= WorkoutPatternDetector.hrRecoveryGoodRatio { return "uitstekend" }
        if ratio >= WorkoutPatternDetector.hrRecoveryMildRatio { return "goed" }
        if ratio >= WorkoutPatternDetector.hrRecoveryModerateRatio { return "matig" }
        return "slecht"
    }

    // MARK: Weather context chip (Epic #49)

    /// Compact pill on the right of the Coach-analysis header that shows which weather data
    /// the coach received. Transparency layer: even if the coach does not mention the weather
    /// explicitly in its analysis, the user sees that the information was indeed
    /// passed in (and apparently was not found relevant). Appears only
    /// when HK metadata is present — with missing weather there is nothing to show and
    /// the header stays clean.
    @ViewBuilder
    private var weatherContextChip: some View {
        if activity.temperatureCelsius != nil || activity.humidityPercent != nil {
            HStack(spacing: 8) {
                if let temp = activity.temperatureCelsius {
                    HStack(spacing: 3) {
                        Image(systemName: "thermometer.medium")
                            .font(.caption2)
                        Text("\(Int(temp.rounded()))°C")
                            .font(.caption.monospacedDigit())
                    }
                }
                if let humidity = activity.humidityPercent {
                    HStack(spacing: 3) {
                        Image(systemName: "humidity.fill")
                            .font(.caption2)
                        Text("\(Int(humidity.rounded()))%")
                            .font(.caption.monospacedDigit())
                    }
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.tertiary.opacity(0.25)))
        }
    }

    // MARK: Insight card

    @ViewBuilder
    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(themeManager.primaryAccentColor)
                Text("Coach-analyse")
                    .font(.headline)
                Spacer()
                weatherContextChip
            }
            switch insightState {
            case .idle:
                EmptyView()
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Coach analyseert de patronen…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .loaded(let text):
                Text(text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            case .unavailable(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.primaryAccentColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(themeManager.primaryAccentColor.opacity(0.20), lineWidth: 1)
        )
    }

    // MARK: Coach Comparison (Story 33.4)

    /// Result of the intent-vs-execution analysis when there is a matching plan.
    /// `nil` when there is no plan, no match on the calendar day, or `.insufficientData` —
    /// in those cases we do not show the card (no noise).
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
        // Epic #37 story 37.1c: headline rendered verbatim -> resolve via the catalog. The
        // percentage (incl. its % sign) is pre-formatted and interpolated as %@ to keep a
        // literal % out of the generated format key.
        case .match:
            return ComparisonStyle(color: .green,
                                   icon: "checkmark.circle.fill",
                                   headline: String(localized: "Plan behaald"))
        case .typeMismatch:
            return ComparisonStyle(color: .orange,
                                   icon: "exclamationmark.triangle.fill",
                                   headline: String(localized: "Type wijkt af"))
        case .overload(let pct):
            let pctStr = String(format: "%+.0f%%", pct)
            return ComparisonStyle(color: Color(red: 0.93, green: 0.42, blue: 0.21),
                                   icon: "flame.fill",
                                   headline: String(localized: "Boven plan (\(pctStr) TRIMP)"))
        case .underload(let pct):
            let pctStr = String(format: "%+.0f%%", pct)
            return ComparisonStyle(color: .blue,
                                   icon: "drop.fill",
                                   headline: String(localized: "Onder plan (\(pctStr) TRIMP)"))
        case .insufficientData:
            // Already filtered out in `comparisonContent`, but we keep a
            // sane fallback so the switch is exhaustive.
            return ComparisonStyle(color: .secondary,
                                   icon: "questionmark.circle",
                                   headline: String(localized: "Geen vergelijking"))
        }
    }

    private func comparisonSubtitle(for verdict: IntentExecutionVerdict, planned plannedActivity: String) -> String {
        switch verdict {
        // Epic #37 story 37.1c: rendered verbatim -> resolve via the catalog. Activity names
        // interpolate as %@ (data).
        case .match:
            return String(localized: "Gepland: \(plannedActivity) → Uitgevoerd: \(activity.displayName). Type én belasting binnen marge.")
        case .typeMismatch(let plannedType, let actualType):
            let actualLabel = actualType?.displayName ?? String(localized: "onbepaald")
            return String(localized: "Gepland: \(plannedActivity) (\(plannedType.displayName)) → Uitgevoerd: \(activity.displayName) (\(actualLabel)).")
        case .overload, .underload:
            return String(localized: "Gepland: \(plannedActivity) → Uitgevoerd: \(activity.displayName).")
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

    // MARK: Session-type override (Epic 33 Story 33.1b)

    /// Menu that lets the user override the auto-classification. Changes
    /// are saved directly in SwiftData and propagate via observation to the
    /// ChatViewModel cache (see `cacheLastWorkoutFeedback`).
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
        // Epic 40 Story 40.4: on a manual choice (incl. clearing) we mark the
        // record as an override. `SessionReclassifier` skips such records so a
        // later stream backfill does not overwrite the user's choice.
        activity.manualSessionTypeOverride = true
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

    private var heartRateChart: some View {
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
    private var secondaryChart: some View {
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
    private var cadenceChart: some View {
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

    // MARK: Stats grid (from ActivityRecord — always available, also for Strava)

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
            // Epic #49: weather tiles from HK metadata, only when the iPhone was present
            // during the workout. Both optional — sometimes HK has temp but
            // no humidity (or vice versa), in which case we show only what we have.
            if let temp = activity.temperatureCelsius {
                statTile(label: "Temperatuur",
                         value: "\(Int(temp.rounded())) °C",
                         icon: "thermometer.medium")
            }
            if let humidity = activity.humidityPercent {
                statTile(label: "Luchtvochtigheid",
                         value: "\(Int(humidity.rounded())) %",
                         icon: "humidity.fill")
            }
        }
    }

    private func statTile(label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Epic #37 story 37.1c: label passed as a Dutch literal -> resolve via the catalog.
            Label(LocalizedStringKey(label), systemImage: icon)
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

// MARK: - Recent Workouts section (Dashboard)

/// Section below the TrendWidget on the Dashboard with the most recent HealthKit workouts.
/// Strava records are also shown (as context) but are not clickable — they have no
/// `WorkoutSample` data because Deep Sync only links the HealthKit source.
struct RecentWorkoutsSection: View {

    @Query(sort: \ActivityRecord.startDate, order: .reverse) private var allActivities: [ActivityRecord]
    @EnvironmentObject var themeManager: ThemeManager

    /// Number of rows we show. Default 7 — fits on one screen without dominating the scroll.
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

/// One row in the "Recente Workouts" section. Clickable when `id` is parseable as a UUID
/// (= HealthKit). Strava records are shown as a static row without a chevron.
struct RecentWorkoutRow: View {
    let activity: ActivityRecord
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        // Epic 40: both HealthKit records (UUID uuidString) and Strava records
        // (numeric ID) are now clickable. WorkoutAnalysisView distinguishes them itself
        // via `UUID.forActivityRecordID(_:)` and shows samples when present — for
        // Strava records without ingested streams the existing
        // 'Nog geen samples beschikbaar' empty state appears. That is more correct than a row
        // without navigation where the user gets no feedback about why they
        // cannot tap anything.
        NavigationLink {
            WorkoutAnalysisView(activity: activity)
        } label: {
            rowContent(showChevron: true)
        }
        .buttonStyle(.plain)
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
        // Match TrendWidgetView styling — `Color(.systemBackground)` is white in light mode
        // and dark in dark mode (auto-adjusting), with the same subtle shadow.
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
