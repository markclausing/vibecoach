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
    /// Epic #48: actieve doelen + alle activities + readiness voor blueprint- en
    /// periodisatie-context die de Coach-analyse meekrijgt.
    @Query(sort: \FitnessGoal.targetDate, order: .forward) private var goals: [FitnessGoal]
    @Query(sort: \ActivityRecord.startDate, order: .forward) private var allActivitiesForContext: [ActivityRecord]
    @Query(sort: \DailyReadiness.date, order: .reverse) private var readinessRecords: [DailyReadiness]

    @State private var scrubbedDate: Date?

    // MARK: - Story 32.3b: pattern-detectie + AI-narrative

    @State private var patterns: [WorkoutPattern] = []
    @State private var insightState: InsightState = .idle
    @State private var selectedPatternKind: WorkoutPatternKind?
    /// Onafhankelijke task voor de detect-/AI-flow. Bewust unstructured zodat
    /// een pull-to-refresh-gesture die SwiftUI's `refreshable`-task vroegtijdig
    /// cancelt (bekende UX-glitch wanneer de gesture eindigt vóór de Gemini-call
    /// klaar is) niet de werker meeneemt — anders verdwijnt de coach-tekst zonder
    /// vervanging in `.idle`.
    @State private var insightTask: Task<Void, Never>?

    private enum InsightState: Equatable {
        case idle                 // Nog geen patronen of geen API-key
        case loading              // AI-call in flight
        case loaded(String)       // Coach-narrative klaar
        case unavailable(String)  // Patronen aanwezig, maar geen AI-call mogelijk (key/fout)
    }

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
    /// Epic #52: cadens-grafiek tonen we alleen voor hardlopen (HK stepCount-afgeleide
    /// of Strava-stream — beide leveren spm). Voor cycling zit cadens als secundair
    /// signaal in een eigen chart-flow (zou een vierde grafiek worden); buiten scope.
    private var hasCadence: Bool { samples.contains { $0.cadence != nil } }
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

    private var chartDomain: ClosedRange<Date> {
        guard let first = samples.first?.timestamp,
              let last  = samples.last?.timestamp,
              first < last else {
            return Date()...Date().addingTimeInterval(1)
        }
        return first...last
    }

    /// Epic #44 story 44.5: HR-zones afgeleid uit het profiel. Friel als LTHR
    /// gezet is (preciezer voor atleet), anders Karvonen op max+rest. Lege array
    /// als de gebruiker geen drempels heeft ingesteld — chart blijft schoon.
    private var heartRateChartZones: [HeartRateZone] {
        WorkoutPatternDetector.heartRateZones(from: UserProfileService.cachedProfile()) ?? []
    }

    private var powerChartZones: [PowerZone] {
        guard let ftp = UserProfileService.cachedProfile().ftp?.value, ftp > 0 else { return [] }
        return PowerZoneCalculator.coggan(ftp: ftp)
    }

    /// Pastel-gradient van Z1 → Z5/Z7. Bewust laag-saturatie zodat zone-bands de
    /// chart niet overheersen. Zone 1 = blauw (recovery), Z5/6/7 = warm (max).
    private func zoneColor(forIndex index: Int) -> Color {
        switch index {
        case 1: return .blue
        case 2: return .green
        case 3: return .yellow
        case 4: return .orange
        case 5: return .red
        case 6: return .pink
        default: return .purple // Z7 neuromuscular voor power
        }
    }

    /// Y-domain voor de HR-chart. Tight rond actuele data (±10 BPM marge) zodat
    /// we geen lege "0-80 BPM" en "200-300 BPM" zones tonen waar geen data zit.
    /// Zone-bands die buiten deze range vallen worden door Charts geclipped — dat
    /// is precies wat we willen, alleen zones tonen die de gebruiker écht heeft
    /// aangeraakt.
    private var hrYDomain: ClosedRange<Double> {
        let hrValues = samples.compactMap(\.heartRate)
        guard let minHR = hrValues.min(), let maxHR = hrValues.max() else {
            return 60...190
        }
        let lower = max(40, minHR - 10).rounded(.down)
        let upper = min(220, maxHR + 10).rounded(.up)
        return lower...upper
    }

    /// Y-domain voor de secondary chart. Power/speed start op 0 (recovery / coasten
    /// is betekenisvol). Bovengrens met kleine marge boven de piekwaarde — zone
    /// Z6/Z7 (Coggan) wordt buiten deze range automatisch geclipped.
    private var secondaryYDomain: ClosedRange<Double> {
        let values: [Double] = samples.compactMap { secondaryValue(of: $0) }
        guard let maxValue = values.max(), maxValue > 0 else { return 0...100 }
        switch secondarySeries {
        case .power: return 0...(maxValue + 30).rounded(.up)
        case .speed: return 0...(maxValue + 0.5).rounded(.up)
        case .none:  return 0...maxValue
        }
    }

    /// Epic #52: Y-domain voor de cadens-grafiek. Tight rond actuele data zodat
    /// het verloop binnen één rit goed leesbaar is. Default 140-200 spm (typische
    /// hardloop-range) wanneer er nog geen data is, voorkomt een lege as.
    private var cadenceYDomain: ClosedRange<Double> {
        let values = samples.compactMap(\.cadence)
        guard let minC = values.min(), let maxC = values.max() else {
            return 140...200
        }
        let lower = max(60, minC - 10).rounded(.down)
        let upper = min(240, maxC + 10).rounded(.up)
        return lower...upper
    }

    /// Epic #52: gemiddelde cadens (spm) over de niet-nul samples — nul-buckets
    /// (verkeerslicht, koffiestop) tellen niet mee. Dezelfde filter-logica als
    /// `WorkoutPatternDetector.cadenceFade` voor consistentie tussen UI en
    /// pattern-detectie. Nil als er geen cadens-samples zijn.
    private var averageCadence: Double? {
        let values = samples.compactMap(\.cadence).filter { $0 > 0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Epic #52: piek-cadens (95e percentiel) — niet de hoogste outlier maar de
    /// "typische top" om sprintje-spikes af te vlakken.
    private var peakCadence: Double? {
        let values = samples.compactMap(\.cadence).filter { $0 > 0 }.sorted()
        guard !values.isEmpty else { return nil }
        let idx = min(values.count - 1, Int((Double(values.count) * 0.95).rounded(.down)))
        return values[idx]
    }

    /// Epic #48: laatste readiness-record (van vandaag of recenter), gebruikt
    /// als input voor `PeriodizationEngine.evaluateAllGoals` zodat de
    /// IntentModifier de VibeScore-drempel correct evalueert.
    private var latestReadinessForContext: DailyReadiness? {
        readinessRecords.first
    }

    /// Epic #48: stabiele fingerprint voor de blueprint- + periodisatie-state.
    /// Verandert zodra een doel toegevoegd/verwijderd wordt, een milestone
    /// behaald is, of een fase-overgang plaatsvindt. Botsings-vrij genoeg voor
    /// cache-invalidatie van de Coach-analyse — geen cryptografische hash nodig.
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

    /// Epic #49: cache-key voor weer-context. Verandert zodra HK-metadata wordt
    /// bijgewerkt (bv. na DeepSync of een latere ingest), zodat een eerder
    /// gegenereerde Coach-analyse zonder hitte-context vervangen wordt door
    /// een nieuwe met de hitte-weging erin. "w_empty" als geen weerdata —
    /// stabiele key bij niet-aanwezig zodat we niet steeds opnieuw genereren.
    /// Epic #52: voegt range-piek toe zodat een latere hourly-range-fetch
    /// (die de snapshot kan overrulen) ook een fresh-cache-entry triggert.
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

    /// Epic #52: cache-fingerprint voor running-cadens. Verandert zodra nieuwe
    /// cadens-samples binnenkomen (DeepSync of Strava-stream-ingest), zodat een
    /// eerder gegenereerde Coach-analyse die nog géén cadens-context had,
    /// vervangen wordt door een nieuwe met de spm-weging erin. "c_empty"
    /// wanneer geen cadens-data — stabiele key, geen onnodige invalidaties.
    private func cadenceFingerprint() -> String {
        guard activity.sportCategory == .running else { return "c_na" }
        var parts: [String] = []
        if let avg = averageCadence { parts.append("a\(Int(avg.rounded()))") }
        if let peak = peakCadence { parts.append("p\(Int(peak.rounded()))") }
        return parts.isEmpty ? "c_empty" : parts.joined(separator: "_")
    }

    /// Epic #52: helper om de hourly weer-range op te halen voor deze workout.
    /// Returnt `nil` als er geen GPS-coords op het record staan (HK-only ritten)
    /// of als de API faalt — caller valt dan terug op de snapshot in
    /// `activity.temperatureCelsius`/`humidityPercent`. Faal-tolerant zodat
    /// een offline gebruiker of API-timeout de Coach-analyse niet blokkeert.
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

    /// Combineert de gestelde drempels tot een korte sleutel. Lege drempels worden
    /// genegeerd; resultaat is leeg-string-achtig ("p_empty") als de gebruiker geen
    /// drempels heeft ingesteld. Niet cryptografisch — alleen botsings-vrij genoeg
    /// voor cache-invalidatie van de Coach-analyse.
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
            // Epic #44 story 44.5 + 44.6 testflow: pull-to-refresh leegt de
            // `WorkoutInsightCache`-entry voor deze workout en herhaalt de detect-/
            // generate-flow met de actuele profielwaarden. Handig om kalibratie-
            // wijzigingen (nieuwe LTHR/max in Settings) terug te zien op een
            // bestaande workout zonder dat je hoeft te wachten op een natuurlijke
            // pattern-fingerprint-shift.
            //
            // De Gemini-call kan 1-3s duren — langer dan SwiftUI's refreshable-task
            // soms wacht voor 'ie cancelt. Daarom draait de werker als unstructured
            // `Task` (overleeft refreshable-cancellation), en awaiten we hier alleen
            // op een korte gating zodat de pull-spinner niet instant flasht. De
            // in-card "Coach analyseert…"-spinner toont de echte voortgang.
            insightTask?.cancel()
            insightTask = Task { await refreshAnalysis() }
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
    }

    /// Hard-invalidate-pad: gooit de cache-entry voor dit ene record weg en herhaalt
    /// `computePatternsAndLoadInsight()`. Roept onder de motorkap dezelfde detect-
    /// + AI-flow aan als de initiële `.task`, dus de loading-state knippert correct.
    private func refreshAnalysis() async {
        WorkoutInsightCache().invalidate(activityID: activity.id)
        await computePatternsAndLoadInsight()
    }

    // MARK: - Story 32.3b: patroon-detectie + cache + AI-narrative

    /// Loopt zodra de samples voor deze workout binnen zijn. Detecteert patronen,
    /// kijkt in de cache, en kickt anders een Gemini-call af. Gebruikt
    /// `WorkoutPatternFormatter.fingerprint` voor de cache-key zodat re-classificatie
    /// (story 40.4 / 32.1 follow-ups) automatisch een nieuwe analyse triggert.
    private func computePatternsAndLoadInsight() async {
        // Epic #44 story 44.5: zone-gates aanzetten zodra de gebruiker LTHR of
        // max+rest heeft ingesteld. Zonder profielwaarden valt de detector terug
        // op het populatie-globale gedrag van vóór 44.5.
        // Epic #49: bij lege samples (typisch Strava-only wandelingen — Strava
        // levert geen 5s-buckets voor walking, alleen voor cycling/running) blijft
        // de detector-output leeg, maar we genereren wél een coach-frame op basis
        // van activity-velden + weer-context. Geen samples ≠ geen analyse.
        let detected: [WorkoutPattern] = samples.isEmpty
            ? []
            : WorkoutPatternDetector.detectAll(
                in: samples,
                profile: UserProfileService.cachedProfile()
              )
        patterns = detected
        // Epic #47 follow-up: ook bij lege patterns een Coach-analyse genereren
        // (positieve uitvoerings-bevestiging). De system-instruction zegt dan
        // "schrijf een korte positieve frame".

        // Epic #48: blueprint- en periodisatie-context per actief doel. Hergebruikt
        // dezelfde formatters die de chat-coach al gebruikt zodat het format
        // identiek blijft. `BlueprintChecker.checkAllGoals` filtert zelf op doelen
        // met blueprint-type; `PeriodizationEngine.evaluateAllGoals` werkt op alle
        // niet-voltooide doelen.
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

        // Epic #52: hourly weer-range vóór de cache-check ophalen — de range
        // gaat in de fingerprint, dus zonder fetch zou een nieuwe range geen
        // cache-invalidatie triggeren. Voor records zonder GPS-coords valt deze
        // call snel terug op nil en is de fingerprint-bijdrage stabiel.
        let weatherRange = await fetchWeatherRange()

        let cache = WorkoutInsightCache()
        // Epic #44 + #48 update: cache-key combineert pattern-fingerprint met
        // profiel-fingerprint én een doelen-fingerprint. Een wijziging in
        // LTHR/max/FTP, milestone-status of fase-overgang invalideert de cache
        // automatisch — anders zou een verouderde framing in de UI blijven hangen.
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
        // Epic #44 update: rijke context meegeven zodat de coach het sessie-type
        // (drempelwerk vs. recovery) en de persoonlijke zones kan meewegen — geen
        // populatie-aannames meer over wat "hoog" of "rustig" voor jou betekent.
        // Epic #47: pauze-recovery-events als aparte laag in de prompt zodat de
        // coach uitstekend herstel positief kan framen ook als er geen pin is.
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
        // Epic #52: cadens-stats voor running. Voor cycling laten we deze nil zodat
        // de Coach geen cadens-koppeling probeert te leggen waar de prompt-regels
        // expliciet "alleen running" zeggen.
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
            // Task-cancellation = nieuwe call onderweg of view weggenavigeerd. Niet
            // klagen in de UI; de volgende `.task`/refresh handelt het af. Zet de
            // state terug op .idle zodat we niet voor altijd op de spinner blijven
            // hangen als er géén nieuwe call meer komt.
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
            // Genummerd badge (1-9 via SF Symbol). Komt 1-op-1 terug op de HR-chart als
            // PointMark-annotatie zodat gebruiker direct ziet welke pin bij welk patroon hoort.
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

    /// Inline detail-card die opent zodra een pattern-chip wordt aangetapt. Drie
    /// secties: **Wat het meet** (algemene fysiologische uitleg per kind), **Drempels**
    /// (de severity-grenzen die de detector hanteert) en **Op deze rit** (de feitelijke
    /// `pattern.detail` met meting). Bewust geen popover/sheet — extra context bij
    /// wat de gebruiker al ziet, niet een secundaire flow.
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
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
            Text(body)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Mens-leesbare uitleg per pattern-kind voor de detail-card. Korte zin over
    /// fysiologische betekenis + drempel-context, los van de feitelijke meting van
    /// deze rit. Bron-drempels matchen de constanten in `WorkoutPatternDetector`.
    private func patternExplanation(_ kind: WorkoutPatternKind) -> (description: String, thresholds: String) {
        switch kind {
        case .aerobicDecoupling:
            return (
                description: "Vergelijkt de hartslag/intensiteit-ratio in helft 1 versus helft 2 van je rit. Als de ratio stijgt, deed je hart in de tweede helft meer werk per watt of m/s — een teken dat je aerobic ceiling onder druk stond.",
                thresholds: "<3% stabiel · 3–5% mild · 5–8% moderate · >8% significant. Wordt niet gemeten bij stop-and-go-ritten (te variabele intensiteit)."
            )
        case .cardiacDrift:
            return (
                description: "HR-stijging tussen helft 1 en helft 2, los van intensiteit. Bij gelijkmatige inspanning duidt drift op vermoeidheid, hitte of dehydratie. Wordt alleen gemeten in Z1–Z3; drift in Z4–Z5 is verwacht gedrag bij drempel-/VO2max-werk.",
                thresholds: "<3% stabiel · 3–5% mild · 5–8% moderate · >8% significant."
            )
        case .cadenceFade:
            return (
                description: "Daling van je gemiddelde cadans tussen het eerste en laatste kwart. Zero-cadence-momenten (verkeerslicht, koffiestop) worden uit de meting gefilterd. Een fors verschil duidt op spiervermoeidheid of bewust temperen aan het einde.",
                thresholds: "3 mild · 5 moderate · 10 significant — eenheden zijn RPM bij cycling, SPM bij lopen."
            )
        case .heartRateRecovery:
            return (
                description: "Hoeveel zakte je hartslag tijdens een rust-pauze (≥45s, power+cadence beide ≈ 0) ten opzichte van de piek-binnen-pauze. Snelle daling = sterk parasympatisch herstel; trage daling kan vermoeidheid, hitte of cumulatieve belasting indiceren. Alleen pauzes ≥90s zijn pin-waardig.",
                thresholds: "Drop als percentage van LTHR: ≥15% uitstekend (geen pin) · 12–15% mild · 9–12% moderate · <9% significant."
            )
        }
    }

    /// Midden van de pattern-range — pin-positie op de HR-chart. Decoupling/drift
    /// gebruiken de hele workout-duur, dus midpoint = midden van de rit. Cadence
    /// fade en HR-recovery hebben smallere ranges (laatste kwart, pauze-duur),
    /// dus midpoint valt daar gericht in het meet-bereik.
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

    /// Epic #47: vertaalt een pauze-recovery-drop naar een label voor de coach-prompt.
    /// Drempels matchen de pin-grenzen in `WorkoutPatternDetector` zodat het label en
    /// de eventuele pin consistent zijn — een "matig" event hoort bij een moderate-pin.
    private func recoveryQualityLabel(drop: Double, referenceHR: Double) -> String {
        guard referenceHR > 0 else { return "onbekend" }
        let ratio = drop / referenceHR
        if ratio >= WorkoutPatternDetector.hrRecoveryGoodRatio { return "uitstekend" }
        if ratio >= WorkoutPatternDetector.hrRecoveryMildRatio { return "goed" }
        if ratio >= WorkoutPatternDetector.hrRecoveryModerateRatio { return "matig" }
        return "slecht"
    }

    // MARK: Weather context chip (Epic #49)

    /// Compacte pill rechts in de Coach-analyse-header die toont welke weer-data
    /// de coach kreeg. Transparantie-laag: zelfs als de coach het weer niet
    /// expliciet in z'n analyse benoemt, ziet de gebruiker dat de informatie wél
    /// is meegegeven (en blijkbaar niet relevant werd gevonden). Verschijnt alleen
    /// als HK-metadata aanwezig is — bij missing-weather is er niets te tonen en
    /// blijft de header schoon.
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
        // Epic 40 Story 40.4: bij een handmatige keuze (incl. wissen) markeren we het
        // record als override. `SessionReclassifier` slaat zulke records over zodat een
        // latere stream-backfill de keuze van de gebruiker niet wegdrukt.
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
                // Epic #44 story 44.5+: zone-bands als zachte achtergrond. Tonen
                // alleen als de gebruiker drempels heeft ingesteld (Friel- of
                // Karvonen-zones). Subtiele kleuren — line blijft prominent.
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
                // Story 32.3b + UX-fix: pattern-pins op het **midden** van de pattern-
                // range (voorheen `lowerBound` — daardoor stond decoupling/drift-pin
                // aan het rit-begin terwijl het effect over de hele rit gemeten werd).
                // Nu: decoupling/drift = midden van workout, cadence fade = midden van
                // laatste kwart, HR-recovery = midden van de pauze.
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
            .chartXAxis(.hidden) // Tijdsverloop staat al in de scrubber-header.
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

    // MARK: Secondary chart (speed of power)

    @ViewBuilder
    private var secondaryChart: some View {
        let title  = secondarySeries == .speed ? "Snelheid" : "Vermogen"
        let unit   = secondarySeries == .speed ? "m/s"      : "W"
        let accent = themeManager.primaryAccentColor

        chartCard(title: title, unit: unit) {
            Chart {
                // Epic #44: Coggan power-zones als zachte achtergrond — alleen als
                // we power tonen én de gebruiker een FTP heeft. Voor speed-charts
                // hebben we (nog) geen pace-zones, dus die blijven schoon.
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

    // MARK: - Epic #52: cadens-grafiek voor hardlopen

    /// Steps-per-minute grafiek onder de secundaire chart. Volgt het zelfde
    /// patroon als de HR-chart: LineMark met catmullRom-interpolatie, gedeelde
    /// scrubber, tight Y-domain. Geen zone-bands — voor running cadens bestaat
    /// nog geen breed-geaccepteerde zone-indeling die we hier veilig kunnen
    /// renderen (180 spm wordt populair als "ideaal" maar is fysiologisch niet
    /// universeel — vermijden om geen normatief gevoel op te roepen).
    @ViewBuilder
    private var cadenceChart: some View {
        let accent = themeManager.primaryAccentColor
        chartCard(title: "Cadens", unit: "spm") {
            Chart {
                ForEach(samples) { sample in
                    if let cd = sample.cadence, cd > 0 {
                        LineMark(
                            x: .value("Tijd", sample.timestamp),
                            y: .value("spm", cd)
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

    /// Story 32.3b: lookup-helper voor de pin-y-positie op de HR-chart.
    private func nearestHeartRate(at date: Date) -> Double? {
        WorkoutAnalysisHelpers.nearestSample(at: date, in: samples, timestamp: { $0.timestamp })?.heartRate
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
            // Epic #49: weer-tiles uit HK-metadata, alleen wanneer de iPhone tijdens
            // de workout aanwezig was. Beide optioneel — soms heeft HK wel temp en
            // geen humidity (of andersom), dan tonen we alleen wat we hebben.
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

    var body: some View {
        // Epic 40: zowel HealthKit-records (UUID-uuidString) als Strava-records
        // (numerieke ID) zijn nu klikbaar. WorkoutAnalysisView maakt zelf onderscheid
        // via `UUID.forActivityRecordID(_:)` en toont samples wanneer aanwezig — bij
        // Strava-records zonder ge-ingestte streams verschijnt de bestaande
        // 'Nog geen samples beschikbaar'-empty-state. Dat is correcter dan een rij
        // zonder navigatie waar de gebruiker geen feedback krijgt over waarom hij
        // niets kan tappen.
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
