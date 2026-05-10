import Foundation

// MARK: - Epic #47: PauseDetector
//
// Pure-Swift detectie van rust-windows binnen een workout — momenten waar de
// gebruiker écht stilstaat (verkeerslicht-langer-dan-verkeerslicht, koffiestop,
// cool-down). Een rust-window is het enige fysiologisch zinnige meet-punt voor
// HR-recovery: zonder externe load kunnen we de parasympatische HR-drop
// vergelijken met richtwaardes uit de literatuur.
//
// Vervangt de oude globale-piek-+-60s-window-aanpak van `WorkoutPatternDetector`
// die op continue rides een non-event mat (HR-spike → korte dip → weer trappen).
// Zie Epic #47 in ROADMAP.md voor de aanleiding.
//
// AppStorage-vrij en zonder framework-afhankelijkheden — caller geeft samples in,
// detector geeft events terug. Volledig unit-testbaar.

/// Eén gedetecteerde pauze plus de HR-recovery die erin gemeten is. De caller
/// (`WorkoutPatternDetector` voor de pin, `WorkoutInsightService` voor de
/// coach-prompt) kiest zelf wat hij ermee doet.
struct PauseRecoveryEvent: Equatable {
    /// Volledige tijdspanne van de pauze (start van eerste stille sample t/m eind van laatste).
    let pauseRange: ClosedRange<Date>
    /// Window waarin we de HR-min hebben gemeten — `min(60s, pauze-duur)` vanaf `pauseRange.lowerBound`.
    let measurementWindow: ClosedRange<Date>
    /// HR aan het begin van de pauze (eerste stille sample met HR-data).
    let hrAtPauseStart: Double
    /// Laagste HR die in `measurementWindow` is gezien.
    let minHRInWindow: Double

    /// Duur van de pauze in seconden.
    var durationSeconds: TimeInterval {
        pauseRange.upperBound.timeIntervalSince(pauseRange.lowerBound)
    }

    /// HR-drop tijdens het meet-window. Kan 0 zijn als HR niet meetbaar is gezakt
    /// (vermoeid herstel, te kort meet-window).
    var drop: Double {
        max(0, hrAtPauseStart - minHRInWindow)
    }
}

enum PauseDetector {

    /// Minimum-duur voor een "echte" pauze. Bewust boven 30s (verkeerslicht-stops
    /// waar je meteen weer wegtrapt) en onder 60s (een 50s-pauze geeft al een
    /// volwaardig signaal). Zie Epic #47 ontwerp-discussie.
    static let minimumPauseSeconds: TimeInterval = 45

    /// Maximaal recovery-meet-window. Voor pauzes korter dan dit valt het window
    /// samen met de pauze-duur (Optie A: eerlijk voor 45-60s-pauzes, simpeler dan
    /// pro-rata drempels).
    static let recoveryWindowSeconds: TimeInterval = 60

    /// "Stil"-drempel voor power en cadence. Kleine drift rond 0 (sensor-ruis,
    /// freewheelen) niet als activiteit interpreteren.
    static let stillnessThreshold: Double = 5

    /// Pre-check: een workout moet minimaal dit aantal samples met daadwerkelijke
    /// activiteit (power>5 OF cadence>5) hebben voordat we überhaupt naar pauzes
    /// zoeken. Anders zou een sport zonder cadence-sensor (zwemmen) of een rit
    /// zonder powermeter waar de cadence-data ontbreekt als één lange pauze worden
    /// geïnterpreteerd, en zou elk HR-zigzag als "pauze-recovery" rapporteren.
    static let minimumActivitySamples: Int = 10

    /// Hoofd-detectie. Geeft alle gevonden pauzes met hun gemeten HR-recovery terug,
    /// gesorteerd op `pauseRange.lowerBound`. Lege array als de workout geen
    /// detecteerbare activiteit heeft of geen pauzes ≥`minimumPauseSeconds`.
    static func detect(in samples: [WorkoutSample]) -> [PauseRecoveryEvent] {
        guard !samples.isEmpty else { return [] }
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }

        // Pre-check: zonder voldoende activiteits-samples is "pauze" een leeg
        // begrip. Filter sporten zonder bruikbare power/cadence-stream uit.
        let activitySamples = sorted.filter { isActive($0) }
        guard activitySamples.count >= minimumActivitySamples else { return [] }

        var events: [PauseRecoveryEvent] = []
        var runStart: Int?

        for (i, sample) in sorted.enumerated() {
            if isStill(sample) {
                if runStart == nil { runStart = i }
            } else if let start = runStart {
                if let event = makeEvent(from: sorted, runStart: start, runEnd: i - 1) {
                    events.append(event)
                }
                runStart = nil
            }
        }
        // Pauze tot het einde van de workout (cool-down die in 'still'-state eindigt).
        if let start = runStart,
           let event = makeEvent(from: sorted, runStart: start, runEnd: sorted.count - 1) {
            events.append(event)
        }
        return events
    }

    // MARK: - Sample-classificatie

    /// Een sample is "stil" als beide aanwezige intensiteits-signalen onder de
    /// drempel zitten. `nil`-waarden tellen als "niet bezig" — sport zonder
    /// powermeter (cadence-only) of zonder cadence-sensor (power-only) wordt zo
    /// alsnog correct geclassificeerd zolang er ergens in de workout activiteit is.
    private static func isStill(_ sample: WorkoutSample) -> Bool {
        let powerStill = (sample.power ?? 0) < stillnessThreshold
        let cadenceStill = (sample.cadence ?? 0) < stillnessThreshold
        return powerStill && cadenceStill
    }

    /// Sample met daadwerkelijke activiteit — gebruikt voor de pre-check.
    private static func isActive(_ sample: WorkoutSample) -> Bool {
        if let p = sample.power, p > stillnessThreshold { return true }
        if let c = sample.cadence, c > stillnessThreshold { return true }
        return false
    }

    // MARK: - Event-bouw

    /// Bouwt een `PauseRecoveryEvent` uit een aaneengesloten run van stille samples.
    /// Returnt nil als de pauze te kort is, geen HR-data heeft, of geen meetbare drop.
    private static func makeEvent(from samples: [WorkoutSample], runStart: Int, runEnd: Int) -> PauseRecoveryEvent? {
        let startSample = samples[runStart]
        let endSample = samples[runEnd]
        let duration = endSample.timestamp.timeIntervalSince(startSample.timestamp)
        guard duration >= minimumPauseSeconds else { return nil }

        // HR aan het begin: eerste stille sample met HR-data. Als de eerste paar
        // stille samples nil-HR hebben (sensor-glitch op de stop-overgang), pakken
        // we de eerstvolgende met data binnen het meet-window.
        let measurementEndDate = min(
            startSample.timestamp.addingTimeInterval(recoveryWindowSeconds),
            endSample.timestamp
        )
        var hrStart: Double?
        var hrMin: Double = .infinity
        for i in runStart...runEnd {
            let sample = samples[i]
            guard sample.timestamp <= measurementEndDate else { break }
            guard let hr = sample.heartRate, hr > 0 else { continue }
            if hrStart == nil { hrStart = hr }
            if hr < hrMin { hrMin = hr }
        }
        guard let hrAtStart = hrStart, hrMin.isFinite else { return nil }
        let pauseRange = startSample.timestamp...endSample.timestamp
        let measurementWindow = startSample.timestamp...measurementEndDate
        return PauseRecoveryEvent(
            pauseRange: pauseRange,
            measurementWindow: measurementWindow,
            hrAtPauseStart: hrAtStart,
            minHRInWindow: hrMin
        )
    }
}
