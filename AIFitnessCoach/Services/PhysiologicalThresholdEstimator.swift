import Foundation

// MARK: - Epic 44 Story 44.2: PhysiologicalThresholdEstimator
//
// Pure-Swift afleiding van fysiologische drempels (max-HR, rust-HR, LTHR) uit
// een verzameling HK-samples. Bewust géén HK-query in deze laag — caller doet
// de fetch en geeft de samples mee. Dat houdt de schatting volledig unit-testbaar
// en compatibel met zowel HK als toekomstige bronnen (bv. ingest van CSV).
//
// Uitgangspunt: zes maanden aan workout-HR-samples + dagelijkse `restingHeartRate`-
// samples geven samen genoeg signaal voor een betrouwbare eerste schatting. We
// zijn conservatief — losse outliers door sensorfouten worden gefilterd, en we
// vereisen een minimum-aantal samples voordat we überhaupt iets durven te claimen.

enum PhysiologicalThresholdEstimator {

    // MARK: Drempels & filters

    /// Workouts korter dan 20 minuten zijn onbetrouwbaar voor max-HR-detectie:
    /// een korte sprint kan tot een echte max leiden, maar de meeste korte
    /// HK-records zijn loop-walks of cooldowns met spikes door sensor-dropout.
    static let minimumWorkoutDurationForMaxHR: TimeInterval = 20 * 60

    /// Sample-counts: minder dan 30 datapunten in een workout = onbetrouwbaar.
    static let minimumSamplesPerWorkout: Int = 30

    /// HR-samples buiten dit absolute bereik zijn sensorfouten of jitter.
    /// 200+ kan, maar zonder context (bv. plotse 220 BPM) klopt het zelden.
    static let plausibleMaxHRRange: ClosedRange<Double> = 80...220

    /// Voor rust-HR vereisen we minstens 14 dagelijkse samples; minder = nog te
    /// vroeg om een baseline te claimen.
    static let minimumRestingHRSamples: Int = 14

    /// LTHR-detectie vereist een hoge-intensiteit-workout — we kijken naar het
    /// hoogste 30-minuten-rolling-average HR. Onder dit drempel is de schatting
    /// alleen maar de gemiddelde HR van een rustige workout, niet LTHR.
    static let minimumLTHRWindowSamples: Int = 30
    static let lthrWindowSize: Int = 30  // 30 buckets van 60s = 30 min met 1-minuut-resolutie

    // MARK: Input types

    /// Eén workout-sessie geabstraheerd voor de estimator. Caller mapt HK-data
    /// of testdata naar deze struct.
    struct WorkoutHRSample {
        /// Begin van de workout.
        let startDate: Date
        /// Duur in seconden.
        let durationSeconds: TimeInterval
        /// HR-samples in BPM, in chronologische volgorde.
        let heartRates: [Double]
    }

    /// Resultaat van een schatting. Eén van de waardes mag nil zijn als er
    /// onvoldoende data was. UI laat dit zien als "Wij hebben nog te weinig
    /// data — log nog X workouts en probeer opnieuw."
    struct Result: Equatable {
        let maxHeartRate: Double?
        let restingHeartRate: Double?
        let lactateThresholdHR: Double?
    }

    // MARK: Estimators

    /// Schat alle drie de drempels uit de meegegeven datasets. Pure functie.
    /// - Parameters:
    ///   - workouts: Workout-records van de afgelopen ~6 maanden, in willekeurige volgorde.
    ///   - dailyRestingHR: Dagelijkse resting-HR-samples uit HK (gemiddelde rust per dag).
    static func estimate(workouts: [WorkoutHRSample],
                         dailyRestingHR: [Double]) -> Result {
        Result(
            maxHeartRate: estimateMaxHeartRate(workouts: workouts),
            restingHeartRate: estimateRestingHeartRate(samples: dailyRestingHR),
            lactateThresholdHR: estimateLactateThresholdHR(workouts: workouts)
        )
    }

    /// Hoogste plausibele HR-piek uit alle eligible workouts. We pakken niet
    /// blindelings de absolute max — eerst filteren we per workout op duur en
    /// sample-count, daarna kijken we naar het 95e percentiel om losse spikes
    /// uit te sluiten.
    static func estimateMaxHeartRate(workouts: [WorkoutHRSample]) -> Double? {
        var topPercentilePerWorkout: [Double] = []
        for workout in workouts {
            guard workout.durationSeconds >= minimumWorkoutDurationForMaxHR,
                  workout.heartRates.count >= minimumSamplesPerWorkout else { continue }
            let plausible = workout.heartRates.filter { plausibleMaxHRRange.contains($0) }
            guard !plausible.isEmpty else { continue }
            // 95e percentiel binnen de workout sluit losse jitter-spikes uit.
            let sorted = plausible.sorted()
            let idx = min(sorted.count - 1, Int(Double(sorted.count) * 0.95))
            topPercentilePerWorkout.append(sorted[idx])
        }
        guard !topPercentilePerWorkout.isEmpty else { return nil }
        // Op workout-niveau pakken we wél het echte max — dit is een atleet die
        // sporadisch tot z'n top gaat, en het hoogste "stabiele" piek uit alle
        // workouts is dan de beste schatting van zijn werkelijke max-HR.
        return topPercentilePerWorkout.max()
    }

    /// Mediane rust-HR uit de dagelijkse samples van de afgelopen periode.
    /// Mediaan is robuuster dan gemiddelde — één dag met sensorfout door
    /// een Apple Watch op het nachtkastje weerhoudt geen normale baseline.
    static func estimateRestingHeartRate(samples: [Double]) -> Double? {
        let plausible = samples.filter { $0 >= 30 && $0 <= 100 }
        guard plausible.count >= minimumRestingHRSamples else { return nil }
        let sorted = plausible.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }

    /// LTHR via Friel's protocol-equivalent: hoogste 30-min rolling avg HR
    /// uit de zwaarste workout. Niet exact lab-LTHR (dat vereist een 30-min-
    /// time-trial), maar voor gebruik in zone-kalibratie ruim voldoende.
    /// Caller resamplet bij voorkeur naar 60s-buckets vóór ze de samples meegeven —
    /// 30 buckets dekt dan netjes het 30-min window.
    static func estimateLactateThresholdHR(workouts: [WorkoutHRSample]) -> Double? {
        var perWorkoutHighest: [Double] = []
        for workout in workouts {
            guard workout.heartRates.count >= minimumLTHRWindowSamples else { continue }
            let filtered = workout.heartRates.filter { plausibleMaxHRRange.contains($0) }
            guard filtered.count >= lthrWindowSize else { continue }
            // Rolling 30-window gemiddelde — pak het hoogste.
            var highest: Double = 0
            for start in 0...(filtered.count - lthrWindowSize) {
                let window = filtered[start..<(start + lthrWindowSize)]
                let avg = window.reduce(0, +) / Double(lthrWindowSize)
                if avg > highest { highest = avg }
            }
            if highest > 0 { perWorkoutHighest.append(highest) }
        }
        guard !perWorkoutHighest.isEmpty else { return nil }
        // Hoogste over alle workouts — corresponderend met de zwaarste 30-min-blok
        // van de afgelopen 6 maanden, een redelijke proxy voor LTHR.
        return perWorkoutHighest.max()
    }
}
