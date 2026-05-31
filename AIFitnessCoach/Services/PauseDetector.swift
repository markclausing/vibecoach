import Foundation

// MARK: - Epic #47: PauseDetector
//
// Pure-Swift detection of rest windows within a workout — moments where the
// user is genuinely still (a traffic light longer than a traffic light, a coffee stop,
// a cool-down). A rest window is the only physiologically meaningful measurement point for
// HR recovery: without external load we can compare the parasympathetic HR drop
// with reference values from the literature.
//
// Replaces the old global-peak-+-60s-window approach of `WorkoutPatternDetector`
// that measured a non-event on continuous rides (HR spike → short dip → pedalling again).
// See Epic #47 in ROADMAP.md for the rationale.
//
// AppStorage-free and without framework dependencies — the caller passes samples in,
// the detector returns events. Fully unit-testable.

/// One detected pause plus the HR recovery measured in it. The caller
/// (`WorkoutPatternDetector` for the pin, `WorkoutInsightService` for the
/// coach prompt) decides what to do with it.
struct PauseRecoveryEvent: Equatable {
    /// Full time span of the pause (start of the first still sample to the end of the last).
    let pauseRange: ClosedRange<Date>
    /// The window in which we measured the HR min: from the peak HR within the pause
    /// to the pause end. Not from the pause start (on an abrupt stop the HR
    /// often still peaks for 5-15s) and not limited to a vagal time window (on longer
    /// pauses the drop often only gets going after 90s).
    let measurementWindow: ClosedRange<Date>
    /// Highest HR within the pause — anchor point for the drop calculation.
    let peakHRInPause: Double
    /// Lowest HR seen in `measurementWindow` (from the peak).
    let minHRInWindow: Double

    /// Duration of the pause in seconds.
    var durationSeconds: TimeInterval {
        pauseRange.upperBound.timeIntervalSince(pauseRange.lowerBound)
    }

    /// HR drop = peak-within-pause − minimum-after-peak. 0 if HR rose after the
    /// "peak" (HR plateau or climbed during the pause — itself a poor-recovery signal).
    var drop: Double {
        max(0, peakHRInPause - minHRInWindow)
    }
}

enum PauseDetector {

    /// Minimum duration for a "real" pause. Deliberately above 30s (traffic-light stops
    /// where you pedal off again immediately) and below 60s (a 50s pause already gives
    /// a full signal). See the Epic #47 design discussion.
    static let minimumPauseSeconds: TimeInterval = 45

    // (Previously: `recoveryWindowSeconds = 90` cap from the peak. Removed in
    // the Epic #47 follow-up because a 10-min pause with a visual 40 BPM drop was then
    // reported as "3 BPM" — the cool-down window cut off before the
    // actual drop got going. The window now runs to the pause end;
    // thresholds (% of LTHR) decide which drops are pin-worthy.)

    /// "Still" threshold for power and cadence. Small drift around 0 (sensor noise,
    /// freewheeling) should not be interpreted as activity.
    static let stillnessThreshold: Double = 5

    /// Pre-check: a workout must have at least this many samples with actual
    /// activity (power>5 OR cadence>5) before we look for pauses
    /// at all. Otherwise a sport without a cadence sensor (swimming) or a ride
    /// without a power meter where the cadence data is missing would be
    /// interpreted as one long pause, and every HR zigzag would be reported as
    /// "pause recovery".
    static let minimumActivitySamples: Int = 10

    /// Main detection. Returns all found pauses with their measured HR recovery,
    /// sorted by `pauseRange.lowerBound`. Empty array if the workout has no
    /// detectable activity or no pauses ≥`minimumPauseSeconds`.
    static func detect(in samples: [WorkoutSample]) -> [PauseRecoveryEvent] {
        guard !samples.isEmpty else { return [] }
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }

        // Pre-check: without enough activity samples "pause" is an empty
        // concept. Filter out sports without a usable power/cadence stream.
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
        // Pause to the end of the workout (a cool-down that ends in the 'still' state).
        if let start = runStart,
           let event = makeEvent(from: sorted, runStart: start, runEnd: sorted.count - 1) {
            events.append(event)
        }
        return events
    }

    // MARK: - Sample classification

    /// A sample is "still" if both present intensity signals are below the
    /// threshold. `nil` values count as "not active" — a sport without a
    /// power meter (cadence-only) or without a cadence sensor (power-only) is thus
    /// still classified correctly as long as there is activity somewhere in the workout.
    private static func isStill(_ sample: WorkoutSample) -> Bool {
        let powerStill = (sample.power ?? 0) < stillnessThreshold
        let cadenceStill = (sample.cadence ?? 0) < stillnessThreshold
        return powerStill && cadenceStill
    }

    /// Sample with actual activity — used for the pre-check.
    private static func isActive(_ sample: WorkoutSample) -> Bool {
        if let p = sample.power, p > stillnessThreshold { return true }
        if let c = sample.cadence, c > stillnessThreshold { return true }
        return false
    }

    // MARK: - Event building

    /// Builds a `PauseRecoveryEvent` from a contiguous run of still samples.
    /// Returns nil if the pause is too short or contains no HR data.
    ///
    /// Measurement strategy: find the peak HR within the pause, measure `peak − min` over
    /// `[peakTime, pause.end]`. Reason for peak-anchoring: on an abrupt stop
    /// the HR often still peaks briefly before it starts to drop — measuring from the first
    /// pause sample captures the plateau phase, not the drop. Reason to measure over
    /// the whole pause (instead of a vagal time window of 60-90s): on a
    /// longer coffee/photo stop the actual drop often only gets going after the first
    /// 90s. A 10-min pause with a visual 40 BPM drop was previously reported as
    /// "3 BPM" because the window cut off. Thresholds (% of LTHR in
    /// `WorkoutPatternDetector`) decide which drops are pin-worthy.
    private static func makeEvent(from samples: [WorkoutSample], runStart: Int, runEnd: Int) -> PauseRecoveryEvent? {
        let startSample = samples[runStart]
        let endSample = samples[runEnd]
        let duration = endSample.timestamp.timeIntervalSince(startSample.timestamp)
        guard duration >= minimumPauseSeconds else { return nil }

        // Step 1: find the peak-HR-within-the-pause.
        var peakHR: Double = 0
        var peakIndex: Int?
        for i in runStart...runEnd {
            guard let hr = samples[i].heartRate, hr > 0 else { continue }
            if hr > peakHR {
                peakHR = hr
                peakIndex = i
            }
        }
        guard let pkIdx = peakIndex else { return nil }
        let peakSample = samples[pkIdx]

        // Step 2: minimum HR within [peakTime, pause.end] — over the whole rest of
        // the pause, not limited to 60-90s.
        var minHR: Double = peakHR
        for i in pkIdx...runEnd {
            guard let hr = samples[i].heartRate, hr > 0 else { continue }
            if hr < minHR { minHR = hr }
        }

        let pauseRange = startSample.timestamp...endSample.timestamp
        let measurementWindow = peakSample.timestamp...endSample.timestamp
        return PauseRecoveryEvent(
            pauseRange: pauseRange,
            measurementWindow: measurementWindow,
            peakHRInPause: peakHR,
            minHRInWindow: minHR
        )
    }
}
