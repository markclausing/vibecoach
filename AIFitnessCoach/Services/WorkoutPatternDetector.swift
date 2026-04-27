import Foundation

// MARK: - Epic 32 Story 32.3a: WorkoutPatternDetector
//
// Pure-Swift detectoren voor fysiologische patronen in een 5s-resampled
// `WorkoutSample`-reeks. Geen UI, AppStorage of AI-afhankelijkheid — de
// detectoren krijgen samples in en geven `WorkoutPattern`-waarden terug.
// Dat houdt ze volledig unit-testbaar én onafhankelijk van app-state, zoals
// afgesproken voor pure-Swift helpers in deze codebase.
//
// Drempelwaarden (decoupling, drift, fade) volgen de duurloop-/cycling-norm
// uit Joe Friel / TrainingPeaks-literatuur. Story 32.3b consumeert deze
// patronen om annotation-pins op `WorkoutAnalysisView` te tekenen en de
// coach-prompt te verrijken met gestructureerde fysiologische context.

enum WorkoutPatternKind: String, Codable, Equatable {
    /// HR stijgt sneller dan vermogen of pace in de tweede helft.
    case aerobicDecoupling
    /// HR-only stijging tussen helft 1 en helft 2 — werkt zonder power/speed.
    case cardiacDrift
    /// Cadence-daling tussen begin en eind van de workout.
    case cadenceFade
    /// HR-drop in 60s na de globale piek-inspanning.
    case heartRateRecovery
}

struct WorkoutPattern: Equatable {
    let kind: WorkoutPatternKind
    let severity: Severity
    /// Tijdspanne waarop het patroon zich voordoet — voor 32.3b annotation-pins.
    let range: ClosedRange<Date>
    /// Numerieke waarde achter het patroon. Eenheid hangt af van `kind`:
    /// decoupling/drift = drift-percentage; cadenceFade = RPM-/SPM-daling;
    /// heartRateRecovery = BPM-drop in 60s.
    let value: Double
    /// Mens-leesbare uitleg voor coach-prompt en UI-popover.
    let detail: String

    enum Severity: Int, Codable, Comparable {
        case mild = 1
        case moderate = 2
        case significant = 3
        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }
}

enum WorkoutPatternDetector {

    // MARK: Drempelwaarden

    /// Aerobic decoupling — Joe Friel / TrainingPeaks norm. <3% = stabiel; 3-5% mild;
    /// 5-8% moderate; >8% significant.
    static let decouplingMild: Double = 3.0
    static let decouplingModerate: Double = 5.0
    static let decouplingSignificant: Double = 8.0

    /// Cardiac drift — HR-stijging tussen helft 1 en 2 bij gelijke intensiteit.
    static let cardiacDriftMild: Double = 3.0
    static let cardiacDriftModerate: Double = 5.0
    static let cardiacDriftSignificant: Double = 8.0

    /// Cadence fade — daling tussen het eerste en laatste kwart.
    static let cadenceFadeMild: Double = 3.0
    static let cadenceFadeModerate: Double = 5.0
    static let cadenceFadeSignificant: Double = 10.0

    /// HR-recovery drempels: lage drop = ergere recovery. Boven `hrRecoveryGood`
    /// vinden we niet de moeite waard om te rapporteren.
    static let hrRecoveryGood: Double = 25.0
    static let hrRecoveryMild: Double = 20.0
    static let hrRecoveryModerate: Double = 15.0

    /// Workouts korter dan 10 minuten zijn te kort voor halve-vs-halve-vergelijkingen.
    static let minimumDurationSeconds: TimeInterval = 600

    /// Window voor HR-recovery-meting na de piek.
    static let hrRecoveryWindowSeconds: TimeInterval = 60

    /// Decoupling-meting vereist steady-state effort. Bij hoge variantie in vermogen
    /// of pace (denk: stop-and-go-ritjes met verkeerslichten, sociale ritten met
    /// koffiestops) is de Pa:HR-ratio in elke helft een gemiddelde over verschillende
    /// inspannings-niveaus en zegt het verschil daartussen niets over fitness-drift.
    /// Coefficient of variation (stddev / mean) > 0.30 = niet meten. Echte Z2-rondjes
    /// op vlak parcours zitten typisch op CV < 0.20; deze drempel laat lichte
    /// terreinvariatie door, maar fileert chaos uit.
    static let maxIntensityCV: Double = 0.30

    // MARK: Aerobic decoupling

    /// Vergelijkt de HR/intensity-ratio in helft 1 vs helft 2. Probeert eerst power
    /// (rijker signal als powermeter aanwezig is), valt anders terug op speed.
    /// Beide paden vereisen `isSteadyEffort` om te voorkomen dat we op stop-and-go-
    /// ritjes (city, social rides) onzin-drift rapporteren.
    static func detectAerobicDecoupling(in samples: [WorkoutSample]) -> WorkoutPattern? {
        guard let halves = splitInHalves(samples) else { return nil }
        if isSteadyEffort(samples, value: { $0.power }),
           let pattern = decoupling(firstHalf: halves.first, secondHalf: halves.second,
                                    intensity: { $0.power }, label: "vermogen") {
            return pattern
        }
        if isSteadyEffort(samples, value: { $0.speed }),
           let pattern = decoupling(firstHalf: halves.first, secondHalf: halves.second,
                                    intensity: { $0.speed }, label: "tempo") {
            return pattern
        }
        return nil
    }

    /// Coefficient of variation (stddev / mean) over de positieve waardes. Hoge CV
    /// duidt op variabele inspanning waar decoupling onbetrouwbaar wordt.
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
        // Negatieve drift (HR groeit trager dan intensiteit) is geen pijnpunt.
        guard driftPct >= decouplingMild else { return nil }
        let severity: WorkoutPattern.Severity = {
            if driftPct >= decouplingSignificant { return .significant }
            if driftPct >= decouplingModerate { return .moderate }
            return .mild
        }()
        let range = samplesStart(firstHalf) ... samplesEnd(secondHalf)
        let detail = String(format: "Aerobic decoupling: HR steeg %.1f%% sneller dan %@ in de tweede helft", driftPct, label)
        return WorkoutPattern(kind: .aerobicDecoupling, severity: severity, range: range, value: driftPct, detail: detail)
    }

    /// Gemiddelde HR/intensity-ratio over samples waar beide aanwezig zijn (>0).
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

    /// HR-stijging tussen helft 1 en 2 — vereist alleen hartslag-data, bedoeld voor
    /// steady-state aerobic workouts zonder power-meter.
    static func detectCardiacDrift(in samples: [WorkoutSample]) -> WorkoutPattern? {
        guard let halves = splitInHalves(samples) else { return nil }
        guard let firstHR = average(halves.first, value: { $0.heartRate }, minimum: 1),
              let secondHR = average(halves.second, value: { $0.heartRate }, minimum: 1),
              firstHR > 0 else {
            return nil
        }
        let driftPct = ((secondHR / firstHR) - 1.0) * 100.0
        guard driftPct >= cardiacDriftMild else { return nil }
        let severity: WorkoutPattern.Severity = {
            if driftPct >= cardiacDriftSignificant { return .significant }
            if driftPct >= cardiacDriftModerate { return .moderate }
            return .mild
        }()
        let range = samplesStart(halves.first) ... samplesEnd(halves.second)
        let detail = String(format: "Cardiac drift: HR-gemiddelde steeg %.1f%% van helft 1 naar helft 2", driftPct)
        return WorkoutPattern(kind: .cardiacDrift, severity: severity, range: range, value: driftPct, detail: detail)
    }

    // MARK: Cadence fade

    /// Cadence-daling tussen het eerste en laatste kwart. Filtert zero-cadence (gestopt
    /// voor verkeerslicht, einde van de rit) zodat de baseline niet meegaat met stops.
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
        let detail = String(format: "Cadence-fade: %.0f → %.0f (%.0f-eenheden daling tussen begin en eind)", firstAvg, lastAvg, drop)
        return WorkoutPattern(kind: .cadenceFade, severity: severity, range: range, value: drop, detail: detail)
    }

    // MARK: HR recovery (post-peak)

    /// Vindt de globale max-HR en meet de drop in de 60s erna. Lage drop = matige
    /// recovery → signal van vermoeidheid. Skipt als het peak-moment in de laatste
    /// 60s ligt (geen volledig recovery-window beschikbaar).
    static func detectHeartRateRecovery(in samples: [WorkoutSample]) -> WorkoutPattern? {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        guard let peak = peakHeartRateSample(sorted), let peakHR = peak.heartRate else { return nil }
        let recoveryEnd = peak.timestamp.addingTimeInterval(hrRecoveryWindowSeconds)
        guard let workoutEnd = sorted.last?.timestamp, recoveryEnd <= workoutEnd else { return nil }
        guard let endSample = nearestSample(at: recoveryEnd, in: sorted),
              let endHR = endSample.heartRate else {
            return nil
        }
        let drop = peakHR - endHR
        // Strict > 0: drop = 0 betekent HR-plateau (geen recovery-event), geen patroon.
        // Negatief = HR steeg verder na de "piek" — ook geen recovery-window.
        guard drop > 0 else { return nil }
        guard drop < hrRecoveryGood else { return nil } // Goede recovery; geen reden voor pin.
        let severity: WorkoutPattern.Severity = {
            if drop < hrRecoveryModerate { return .significant }
            if drop < hrRecoveryMild { return .moderate }
            return .mild
        }()
        let range = peak.timestamp ... endSample.timestamp
        let detail = String(format: "HR-recovery: %.0f BPM drop in 60s na piek (richtwaarde >%.0f BPM)", drop, hrRecoveryGood)
        return WorkoutPattern(kind: .heartRateRecovery, severity: severity, range: range, value: drop, detail: detail)
    }

    private static func peakHeartRateSample(_ samples: [WorkoutSample]) -> WorkoutSample? {
        var best: WorkoutSample?
        var bestHR: Double = 0
        for sample in samples {
            if let hr = sample.heartRate, hr > bestHR {
                bestHR = hr
                best = sample
            }
        }
        return best
    }

    // MARK: Convenience

    /// Runt alle detectoren en geeft de patronen terug die getriggerd zijn.
    static func detectAll(in samples: [WorkoutSample]) -> [WorkoutPattern] {
        var patterns: [WorkoutPattern] = []
        if let p = detectAerobicDecoupling(in: samples) { patterns.append(p) }
        if let p = detectCardiacDrift(in: samples) { patterns.append(p) }
        if let p = detectCadenceFade(in: samples) { patterns.append(p) }
        if let p = detectHeartRateRecovery(in: samples) { patterns.append(p) }
        return patterns
    }

    // MARK: Sample-helpers

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

    /// Gemiddelde van de meegegeven Double-waarde, alleen samples waar de waarde
    /// `>= minimum` (default 0) telt mee. Filter nil + uitschieters in één pas.
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

    /// Nearest-sample lookup zonder dependency op `WorkoutAnalysisHelpers` zodat
    /// de detector zelf-stantig blijft. O(n) lineaire scan.
    private static func nearestSample(at targetDate: Date, in samples: [WorkoutSample]) -> WorkoutSample? {
        guard let first = samples.first else { return nil }
        var best = first
        var bestDelta = abs(first.timestamp.timeIntervalSince(targetDate))
        for sample in samples.dropFirst() {
            let delta = abs(sample.timestamp.timeIntervalSince(targetDate))
            if delta < bestDelta {
                bestDelta = delta
                best = sample
            }
        }
        return best
    }
}
