import Foundation

// MARK: - Epic 32 Story 32.1: SampleResampler
//
// Pure-Swift resampling van onregelmatige HealthKit-tijdreeksdata naar vaste 5s-buckets.
// Geen HealthKit-dependency zodat de logica volledig testbaar is met synthetische input.

/// Eén meetpunt — tijdstempel + numerieke waarde.
/// Generieke representatie zodat we HR/Power/Cadence/Speed/Distance allemaal door dezelfde resampler kunnen jagen.
struct TimedValue: Equatable {
    let timestamp: Date
    let value: Double
}

/// Strategie waarmee onregelmatige samples naar één 5s-bucket worden gereduceerd.
enum ResampleStrategy {
    /// Gemiddelde van alle samples binnen het bucket-window. Geschikt voor: HR, Power, Cadence.
    case average
    /// Lineair geïnterpoleerd naar het bucket-startpunt o.b.v. de twee dichtstbijzijnde samples.
    /// Geschikt voor signalen waarvan momentane waarde betekenisvoller is dan een gemiddelde — bv. snelheid.
    case linearInterpolation
    /// Som van alle waarden binnen het bucket-window. Geschikt voor cumulatieve metingen — bv. afstand-delta's.
    case deltaAccumulation
}

struct SampleResampler {
    /// Bucket-grootte in seconden. Vast op 5 voor Story 32.1.
    let bucketSeconds: TimeInterval

    init(bucketSeconds: TimeInterval = 5) {
        self.bucketSeconds = bucketSeconds
    }

    /// Genereert alle bucket-starttijdstempels van `start` tot strikt vóór `end`.
    /// Lege workout-windows (start ≥ end) leveren een lege array op.
    func bucketStarts(from start: Date, to end: Date) -> [Date] {
        guard end > start, bucketSeconds > 0 else { return [] }
        var result: [Date] = []
        var t = start
        while t < end {
            result.append(t)
            t = t.addingTimeInterval(bucketSeconds)
        }
        return result
    }

    /// Resamplet `samples` naar 5s-buckets binnen [`start`, `end`) volgens de gekozen strategie.
    /// Lege buckets worden als `nil` teruggegeven — vul nooit met 0 (dat zou downstream-analyses bedriegen).
    func resample(samples: [TimedValue],
                  from start: Date,
                  to end: Date,
                  strategy: ResampleStrategy) -> [(timestamp: Date, value: Double?)] {
        let starts = bucketStarts(from: start, to: end)
        guard !starts.isEmpty else { return [] }

        // Sorteer voor robuustheid — HealthKit garandeert volgorde meestal, maar tests/mocks vaak niet.
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }

        switch strategy {
        case .average:
            return starts.map { bucketStart in
                let bucketEnd = bucketStart.addingTimeInterval(bucketSeconds)
                let inBucket = sorted.filter { $0.timestamp >= bucketStart && $0.timestamp < bucketEnd }
                guard !inBucket.isEmpty else { return (bucketStart, nil) }
                let avg = inBucket.map(\.value).reduce(0, +) / Double(inBucket.count)
                return (bucketStart, avg)
            }

        case .linearInterpolation:
            return starts.map { bucketStart in
                (bucketStart, interpolate(at: bucketStart, in: sorted))
            }

        case .deltaAccumulation:
            return starts.map { bucketStart in
                let bucketEnd = bucketStart.addingTimeInterval(bucketSeconds)
                let inBucket = sorted.filter { $0.timestamp >= bucketStart && $0.timestamp < bucketEnd }
                guard !inBucket.isEmpty else { return (bucketStart, nil) }
                let sum = inBucket.map(\.value).reduce(0, +)
                return (bucketStart, sum)
            }
        }
    }

    // MARK: Private helpers

    /// Lineaire interpolatie naar tijdstip `t` op basis van een gesorteerde reeks samples.
    /// Retourneert nil als `t` buiten het bereik valt — extrapoleren is onbetrouwbaar bij GPS-gaten.
    private func interpolate(at t: Date, in sortedSamples: [TimedValue]) -> Double? {
        guard let first = sortedSamples.first, let last = sortedSamples.last else { return nil }
        if t < first.timestamp || t > last.timestamp { return nil }

        // Exacte match — komt voor bij synthetische tests en samples die exact op een bucket-grens vallen.
        if let exact = sortedSamples.first(where: { $0.timestamp == t }) {
            return exact.value
        }

        // Zoek het paar (vorige, volgende) waar `t` tussen ligt.
        for i in 0..<(sortedSamples.count - 1) {
            let a = sortedSamples[i]
            let b = sortedSamples[i + 1]
            if a.timestamp <= t && t <= b.timestamp {
                let span = b.timestamp.timeIntervalSince(a.timestamp)
                guard span > 0 else { return a.value }
                let progress = t.timeIntervalSince(a.timestamp) / span
                return a.value + (b.value - a.value) * progress
            }
        }
        return nil
    }
}
