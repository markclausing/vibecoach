import Foundation

// MARK: - Epic 32 Story 32.3a: WorkoutPatternDetector
//
// Pure-Swift detectors for physiological patterns in a 5s-resampled
// `WorkoutSample` series. No UI, AppStorage or AI dependency — the detectors
// take samples in and return `WorkoutPattern` values. That keeps them fully
// unit-testable and independent of app state, as agreed for pure-Swift helpers
// in this codebase.
//
// Thresholds (decoupling, drift, fade) follow the endurance-run/cycling norm
// from the Joe Friel / TrainingPeaks literature. Story 32.3b consumes these
// patterns to draw annotation pins on `WorkoutAnalysisView` and enrich the
// coach prompt with structured physiological context.

enum WorkoutPatternKind: String, Codable, Equatable {
    /// HR rises faster than power or pace in the second half.
    case aerobicDecoupling
    /// HR-only rise between half 1 and half 2 — works without power/speed.
    case cardiacDrift
    /// Cadence drop between the start and end of the workout.
    case cadenceFade
    /// HR drop in the 60s after the global peak effort.
    case heartRateRecovery
}

struct WorkoutPattern: Equatable {
    let kind: WorkoutPatternKind
    let severity: Severity
    /// Time span over which the pattern occurs — for 32.3b annotation pins.
    let range: ClosedRange<Date>
    /// Numeric value behind the pattern. The unit depends on `kind`:
    /// decoupling/drift = drift percentage; cadenceFade = RPM/SPM drop;
    /// heartRateRecovery = BPM drop in 60s.
    let value: Double
    /// Human-readable explanation for the coach prompt and UI popover.
    let detail: String

    enum Severity: Int, Codable, Comparable {
        case mild = 1
        case moderate = 2
        case significant = 3
        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }
}

enum WorkoutPatternDetector {

    // MARK: Thresholds

    /// Aerobic decoupling — Joe Friel / TrainingPeaks norm. <3% = stable; 3-5% mild;
    /// 5-8% moderate; >8% significant.
    static let decouplingMild: Double = 3.0
    static let decouplingModerate: Double = 5.0
    static let decouplingSignificant: Double = 8.0

    /// Cardiac drift — HR rise between half 1 and 2 at equal intensity.
    static let cardiacDriftMild: Double = 3.0
    static let cardiacDriftModerate: Double = 5.0
    static let cardiacDriftSignificant: Double = 8.0

    /// Cadence fade — drop between the first and last quarter.
    static let cadenceFadeMild: Double = 3.0
    static let cadenceFadeModerate: Double = 5.0
    static let cadenceFadeSignificant: Double = 10.0

    /// HR-recovery thresholds (Epic #47): drop in a detected pause as a ratio of
    /// the personal `referenceHR` (LTHR preferred, else 0.88×maxHR, else
    /// `referenceHRFallback`). Above `hrRecoveryGoodRatio` the recovery is
    /// excellent and not worth pinning.
    static let hrRecoveryGoodRatio: Double = 0.15
    static let hrRecoveryMildRatio: Double = 0.12
    static let hrRecoveryModerateRatio: Double = 0.09

    /// Population default for `referenceHR` when no LTHR/maxHR is known. 165 BPM
    /// is a reasonable LTHR estimate for a modern 35+ adult and matches the old
    /// absolute thresholds (165 × 0.15 = 24.75 ≈ 25 BPM good bound).
    static let referenceHRFallback: Double = 165.0

    /// Minimum pause duration to qualify as a pin. Pauses of 45-89s still go to
    /// the prompt as coach-context events (informing about ride structure), but
    /// produce no pin — a traffic-light/junction stop is physiologically not a
    /// "recovery event to inform the user about". Under 90s you're still before
    /// the vagally-dominant HRR phase fully kicks in; pinning a small drop in
    /// that window frames it misleadingly for the user (Epic #47 follow-up).
    static let hrRecoveryMinPauseForPinSeconds: TimeInterval = 90

    /// Workouts shorter than 10 minutes are too short for half-vs-half comparisons.
    static let minimumDurationSeconds: TimeInterval = 600

    /// Decoupling measurement requires steady-state effort. With high variance in
    /// power or pace (think: stop-and-go rides with traffic lights, social rides
    /// with coffee stops) the Pa:HR ratio in each half is an average over different
    /// effort levels, and the difference between them says nothing about fitness
    /// drift. Coefficient of variation (stddev / mean) > 0.30 = don't measure. Real
    /// Z2 rides on flat terrain typically sit at CV < 0.20; this threshold lets
    /// light terrain variation through but filters out chaos.
    static let maxIntensityCV: Double = 0.30

    // MARK: Aerobic decoupling

    /// Compares the HR/intensity ratio in half 1 vs half 2. Tries power first
    /// (richer signal if a power meter is present), otherwise falls back to speed.
    /// Both paths require `isSteadyEffort` to avoid reporting nonsense drift on
    /// stop-and-go rides (city, social rides).
    static func detectAerobicDecoupling(in samples: [WorkoutSample]) -> WorkoutPattern? {
        guard let halves = splitInHalves(samples) else { return nil }
        if isSteadyEffort(samples, value: { $0.power }),
           let pattern = decoupling(firstHalf: halves.first, secondHalf: halves.second,
                                    intensity: { $0.power }, label: "power") {
            return pattern
        }
        if isSteadyEffort(samples, value: { $0.speed }),
           let pattern = decoupling(firstHalf: halves.first, secondHalf: halves.second,
                                    intensity: { $0.speed }, label: "pace") {
            return pattern
        }
        return nil
    }

    /// Coefficient of variation (stddev / mean) over the positive values. A high CV
    /// indicates variable effort where decoupling becomes unreliable.
    private static func isSteadyEffort(_ samples: [WorkoutSample],
                                        value: (WorkoutSample) -> Double?) -> Bool {
        var values: [Double] = []
        for sample in samples {
            if let v = value(sample), v > 0 { values.append(v) }
        }
        guard values.count >= 10 else { return false }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return false }
        let variance = values.reduce(0) { acc, v in acc + pow(v - mean, 2) } / Double(values.count)
        let stdDev = variance.squareRoot()
        return (stdDev / mean) < maxIntensityCV
    }

    private static func decoupling(firstHalf: [WorkoutSample],
                                   secondHalf: [WorkoutSample],
                                   intensity: (WorkoutSample) -> Double?,
                                   label: String) -> WorkoutPattern? {
        guard let firstRatio = pairedRatio(firstHalf, intensity: intensity),
              let secondRatio = pairedRatio(secondHalf, intensity: intensity),
              firstRatio > 0 else {
            return nil
        }
        let driftPct = ((secondRatio / firstRatio) - 1.0) * 100.0
        // Negative drift (HR grows slower than intensity) is not a pain point.
        guard driftPct >= decouplingMild else { return nil }
        let severity: WorkoutPattern.Severity = {
            if driftPct >= decouplingSignificant { return .significant }
            if driftPct >= decouplingModerate { return .moderate }
            return .mild
        }()
        let range = samplesStart(firstHalf) ... samplesEnd(secondHalf)
        let detail = String(format: "Aerobic decoupling: HR rose %.1f%% faster than %@ in the second half", driftPct, label)
        return WorkoutPattern(kind: .aerobicDecoupling, severity: severity, range: range, value: driftPct, detail: detail)
    }

    /// Average HR/intensity ratio over samples where both are present (>0).
    private static func pairedRatio(_ samples: [WorkoutSample], intensity: (WorkoutSample) -> Double?) -> Double? {
        var ratios: [Double] = []
        for sample in samples {
            guard let hr = sample.heartRate, hr > 0,
                  let intens = intensity(sample), intens > 0 else { continue }
            ratios.append(hr / intens)
        }
        guard !ratios.isEmpty else { return nil }
        return ratios.reduce(0, +) / Double(ratios.count)
    }

    // MARK: Cardiac drift (HR-only)

    /// HR rise between half 1 and 2 — requires only heart-rate data, intended for
    /// steady-state aerobic workouts without a power meter.
    /// - Parameter zones: Personal HR zones (Friel or Karvonen). When present we
    ///   only trigger on Z1-Z3 workouts; in Z4/Z5 an HR rise between halves is
    ///   expected behaviour (threshold/VO2max work) and not "drift". Backwards-compat
    ///   default nil = old population-global behaviour (Epic #44 story 44.5 addition).
    static func detectCardiacDrift(in samples: [WorkoutSample],
                                    zones: [HeartRateZone]? = nil) -> WorkoutPattern? {
        guard let halves = splitInHalves(samples) else { return nil }
        guard let firstHR = average(halves.first, value: { $0.heartRate }, minimum: 1),
              let secondHR = average(halves.second, value: { $0.heartRate }, minimum: 1),
              firstHR > 0 else {
            return nil
        }
        // Zone gate: cardiac drift only has meaning in Z1-Z3 (steady-state
        // aerobic). In Z4/Z5 an HR rise between halves is not "drift" but simply
        // the effect of harder work in the second half.
        if let zones {
            let avgHR = (firstHR + secondHR) / 2.0
            let zone = HeartRateZoneCalculator.zoneIndex(for: avgHR, in: zones)
            guard (1...3).contains(zone) else { return nil }
        }
        let driftPct = ((secondHR / firstHR) - 1.0) * 100.0
        guard driftPct >= cardiacDriftMild else { return nil }
        let severity: WorkoutPattern.Severity = {
            if driftPct >= cardiacDriftSignificant { return .significant }
            if driftPct >= cardiacDriftModerate { return .moderate }
            return .mild
        }()
        let range = samplesStart(halves.first) ... samplesEnd(halves.second)
        let detail = String(format: "Cardiac drift: average HR rose %.1f%% from half 1 to half 2", driftPct)
        return WorkoutPattern(kind: .cardiacDrift, severity: severity, range: range, value: driftPct, detail: detail)
    }

    // MARK: Cadence fade

    /// Cadence drop between the first and last quarter. Filters zero cadence (stopped
    /// at a traffic light, end of the ride) so the baseline isn't dragged down by stops.
    static func detectCadenceFade(in samples: [WorkoutSample]) -> WorkoutPattern? {
        guard durationSeconds(samples) >= minimumDurationSeconds else { return nil }
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 4 else { return nil }
        let quarter = sorted.count / 4
        let firstQuarter = Array(sorted.prefix(quarter))
        let lastQuarter = Array(sorted.suffix(quarter))
        guard let firstAvg = average(firstQuarter, value: { $0.cadence }, minimum: 1),
              let lastAvg = average(lastQuarter, value: { $0.cadence }, minimum: 1) else {
            return nil
        }
        let drop = firstAvg - lastAvg
        guard drop >= cadenceFadeMild else { return nil }
        let severity: WorkoutPattern.Severity = {
            if drop >= cadenceFadeSignificant { return .significant }
            if drop >= cadenceFadeModerate { return .moderate }
            return .mild
        }()
        let range = samplesStart(firstQuarter) ... samplesEnd(lastQuarter)
        let detail = String(format: "Cadence fade: %.0f → %.0f (%.0f-unit drop between start and end)", firstAvg, lastAvg, drop)
        return WorkoutPattern(kind: .cadenceFade, severity: severity, range: range, value: drop, detail: detail)
    }

    // MARK: HR recovery (via pause detection — Epic #47)

    /// Iterates pauses from `PauseDetector.detect(in:)`, computes per pause the
    /// HR-drop ratio relative to `referenceHR`, and pins the pause with the worst
    /// recovery (lowest ratio) — per Management by Exception §1: only when there
    /// is something to say, and then about the weakest signal.
    /// - Parameter referenceHR: LTHR preferred, else 0.88 × maxHR, else nil.
    ///   On nil it falls back to `referenceHRFallback` (165 BPM population default).
    /// - Returns: nil if there is no pause, no pause with a measurable drop, or if
    ///   all pauses show excellent recovery.
    static func detectHeartRateRecovery(in samples: [WorkoutSample],
                                         referenceHR: Double? = nil) -> WorkoutPattern? {
        let events = PauseDetector.detect(in: samples)
        guard !events.isEmpty else { return nil }
        let refHR = (referenceHR ?? referenceHRFallback)
        guard refHR > 0 else { return nil }

        // For each event: compute ratio + severity. Two filters for pin consideration:
        //  1. Pause ≥ `hrRecoveryMinPauseForPinSeconds` — traffic-light stops 45-89s
        //     produce no pin, only coach context. A short stop is physiologically
        //     not a "recovery event to report on".
        //  2. Ratio < `hrRecoveryGoodRatio` — excellent recovery is not pinned
        //     (Management by Exception §1), but still goes to coach context.
        var pinnable: [(event: PauseRecoveryEvent, ratio: Double, severity: WorkoutPattern.Severity)] = []
        for event in events {
            guard event.durationSeconds >= hrRecoveryMinPauseForPinSeconds else { continue }
            guard event.drop > 0 else { continue }
            let ratio = event.drop / refHR
            guard ratio < hrRecoveryGoodRatio else { continue }
            let severity: WorkoutPattern.Severity = {
                if ratio < hrRecoveryModerateRatio { return .significant }
                if ratio < hrRecoveryMildRatio { return .moderate }
                return .mild
            }()
            pinnable.append((event, ratio, severity))
        }
        guard let worst = pinnable.min(by: { $0.ratio < $1.ratio }) else { return nil }

        let dropInt = Int(worst.event.drop.rounded())
        let durationStr = formatDuration(worst.event.durationSeconds)
        let goodThreshold = Int((refHR * hrRecoveryGoodRatio).rounded())
        let detail = "HR-recovery: \(dropInt) BPM drop in a pause of \(durationStr) (reference >\(goodThreshold) BPM)"
        return WorkoutPattern(
            kind: .heartRateRecovery,
            severity: worst.severity,
            range: worst.event.pauseRange,
            value: worst.event.drop,
            detail: detail
        )
    }

    /// Format `m:ss` for the pause duration in the detail text.
    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: Convenience

    /// Runs all detectors and returns the patterns that triggered.
    static func detectAll(in samples: [WorkoutSample]) -> [WorkoutPattern] {
        detectAll(in: samples, zones: nil)
    }

    /// Epic #44 story 44.5 + Epic #47: profile-aware variant. Derives personal
    /// HR zones (Friel-LTHR preferred, else Karvonen) and `referenceHR` (LTHR
    /// preferred, else 0.88 × maxHR) from `profile` and threads both through:
    /// `zones` for the cardiac-drift gate, `referenceHR` for the HR-recovery
    /// thresholds. Decoupling and cadence fade are intensity-independent and
    /// need no profile input.
    static func detectAll(in samples: [WorkoutSample],
                          profile: UserPhysicalProfile) -> [WorkoutPattern] {
        detectAll(in: samples,
                  zones: heartRateZones(from: profile),
                  referenceHR: referenceHeartRate(from: profile))
    }

    static func detectAll(in samples: [WorkoutSample],
                          zones: [HeartRateZone]?,
                          referenceHR: Double? = nil) -> [WorkoutPattern] {
        var patterns: [WorkoutPattern] = []
        if let p = detectAerobicDecoupling(in: samples) { patterns.append(p) }
        if let p = detectCardiacDrift(in: samples, zones: zones) { patterns.append(p) }
        if let p = detectCadenceFade(in: samples) { patterns.append(p) }
        if let p = detectHeartRateRecovery(in: samples, referenceHR: referenceHR) { patterns.append(p) }
        return patterns
    }

    /// Friel is preferred when LTHR is known (more precise for athletic zones);
    /// Karvonen works when both max + rest are filled in; otherwise nil so the
    /// gates don't trigger incorrectly on population defaults.
    static func heartRateZones(from profile: UserPhysicalProfile) -> [HeartRateZone]? {
        if let lthr = profile.lactateThresholdHR?.value, lthr > 0 {
            return HeartRateZoneCalculator.friel(lactateThresholdHR: lthr)
        }
        guard let maxHR = profile.maxHeartRate?.value, maxHR > 0,
              let restHR = profile.restingHeartRate?.value, restHR > 0 else {
            return nil
        }
        return HeartRateZoneCalculator.karvonen(maxHR: maxHR, restingHR: restHR)
    }

    /// Reference HR for the HR-recovery thresholds (Epic #47). LTHR is the most
    /// physiologically correct anchor; when absent we fall back to the common
    /// `LTHR ≈ 0.88 × maxHR` relation. With neither, returns nil so the detector
    /// falls back to `referenceHRFallback` (165 BPM).
    static func referenceHeartRate(from profile: UserPhysicalProfile) -> Double? {
        if let lthr = profile.lactateThresholdHR?.value, lthr > 0 {
            return lthr
        }
        if let maxHR = profile.maxHeartRate?.value, maxHR > 0 {
            return maxHR * 0.88
        }
        return nil
    }

    // MARK: Sample helpers

    private static func splitInHalves(_ samples: [WorkoutSample]) -> (first: [WorkoutSample], second: [WorkoutSample])? {
        guard durationSeconds(samples) >= minimumDurationSeconds else { return nil }
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        let mid = sorted.count / 2
        guard mid > 0, mid < sorted.count else { return nil }
        return (Array(sorted.prefix(mid)), Array(sorted.suffix(sorted.count - mid)))
    }

    private static func durationSeconds(_ samples: [WorkoutSample]) -> TimeInterval {
        guard let first = samples.min(by: { $0.timestamp < $1.timestamp }),
              let last = samples.max(by: { $0.timestamp < $1.timestamp }) else { return 0 }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }

    private static func samplesStart(_ samples: [WorkoutSample]) -> Date {
        samples.min(by: { $0.timestamp < $1.timestamp })?.timestamp ?? Date()
    }

    private static func samplesEnd(_ samples: [WorkoutSample]) -> Date {
        samples.max(by: { $0.timestamp < $1.timestamp })?.timestamp ?? Date()
    }

    /// Average of the given Double value; only samples where the value is
    /// `>= minimum` (default 0) count. Filters nil + outliers in one pass.
    private static func average(_ samples: [WorkoutSample],
                                value: (WorkoutSample) -> Double?,
                                minimum: Double = 0) -> Double? {
        var values: [Double] = []
        for sample in samples {
            guard let v = value(sample), v >= minimum else { continue }
            values.append(v)
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
