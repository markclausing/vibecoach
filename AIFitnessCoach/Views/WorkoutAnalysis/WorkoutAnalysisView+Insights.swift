import SwiftUI

// Epic #65 story 65.5: split out of WorkoutAnalysisView.swift (§5 file-split).
// Pure move — no semantic changes; shared members relaxed to internal where the
// cross-file split requires it (listed in the PR body).

extension WorkoutAnalysisView {

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
            AppLoggers.weather.error("Hourly weer-range fetch faalde voor activity \(activity.id, privacy: .private): \(error.localizedDescription, privacy: .public)")
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

    /// Hard-invalidate path: throws away the cache entry for this one record and repeats
    /// `computePatternsAndLoadInsight()`. Under the hood it calls the same detect
    /// + AI flow as the initial `.task`, so the loading state flickers correctly.
    func refreshAnalysis() async {
        WorkoutInsightCache().invalidate(activityID: activity.id)
        await computePatternsAndLoadInsight()
    }

    // MARK: - Story 32.3b: pattern detection + cache + AI narrative

    /// Runs as soon as the samples for this workout have arrived. Detects patterns,
    /// looks in the cache, and otherwise kicks off a Gemini call. Uses
    /// `WorkoutPatternFormatter.fingerprint` for the cache key so that re-classification
    /// (story 40.4 / 32.1 follow-ups) automatically triggers a new analysis.
    func computePatternsAndLoadInsight() async {
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

    var patternChipsRow: some View {
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
    func patternMidpoint(of pattern: WorkoutPattern) -> Date {
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

    func severityColor(_ severity: WorkoutPattern.Severity) -> Color {
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
    var insightCard: some View {
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
}
