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

    @Query var samples: [WorkoutSample]
    /// Epic #48: active goals + all activities + readiness for the blueprint and
    /// periodization context that the Coach analysis receives.
    @Query(sort: \FitnessGoal.targetDate, order: .forward) var goals: [FitnessGoal]
    // Epic #65 story 65.2: bounded to the rolling `QueryWindows.activityHistory` window
    // (26 weeks). Consumers are `BlueprintChecker` + `PeriodizationEngine`, which scan
    // the current training block (≤ 26 weeks). Cutoff set in `init(activity:)`.
    @Query var allActivitiesForContext: [ActivityRecord]
    @Query(sort: \DailyReadiness.date, order: .reverse) var readinessRecords: [DailyReadiness]

    @State var scrubbedDate: Date?

    // MARK: - Story 32.3b: pattern-detectie + AI-narrative

    @State var patterns: [WorkoutPattern] = []
    @State var insightState: InsightState = .idle
    @State var selectedPatternKind: WorkoutPatternKind?
    /// Independent task for the detect/AI flow. Deliberately unstructured so that
    /// a pull-to-refresh gesture that cancels SwiftUI's `refreshable` task
    /// prematurely (known UX glitch when the gesture ends before the Gemini call
    /// is done) does not take the worker down with it — otherwise the coach text
    /// disappears without replacement into `.idle`.
    @State private var insightTask: Task<Void, Never>?

    enum InsightState: Equatable {
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
        // Epic #65 story 65.2: bound the blueprint/periodization context scan to the
        // rolling 26-week window (Calendar-based cutoff captured as a `let` for the predicate).
        let activityCutoff = QueryWindows.activityHistoryCutoff()
        _allActivitiesForContext = Query(
            filter: #Predicate<ActivityRecord> { $0.startDate >= activityCutoff },
            sort: \ActivityRecord.startDate,
            order: .forward
        )
    }

    /// Epic #52 cross-source fix: HK-`stepCount`-derived cadence, fetched separately
    /// when the stored samples contain no cadence. This happens when the displayed
    /// `ActivityRecord` is a Strava record that "won" over an HK counterpart during
    /// dedup — the Watch steps then live under a different UUID than the view
    /// requests. See `loadCadenceFallbackIfNeeded()`.
    @State var hkCadenceSeries: [TimedValue] = []

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
                // Epic #70: per-workout chat with local memory ("Discuss this workout").
                WorkoutChatSection(activity: activity)
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
                    // Epic #37 story 37.4: SessionType.displayName stays Dutch for prompts; the
                    // UI menu resolves it via the catalog.
                    Label(LocalizedStringKey(type.displayName), systemImage: type.icon)
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
                    Text(LocalizedStringKey(type.displayName))
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

    func formatElapsed(_ seconds: TimeInterval?) -> String {
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
