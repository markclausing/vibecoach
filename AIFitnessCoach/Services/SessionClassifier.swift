import Foundation

// MARK: - Epic 33 Story 33.1: SessionClassifier
//
// Pure-Swift classifier that proposes a `SessionType` based on physiological data +
// title keywords. Three strategies, in order of certainty:
//
//   1. Keywords in title  (user intent weighs more than raw data — a
//      "Social ride" with high HR stays social, even if it looks like tempo by zone)
//   2. Zone distribution via `WorkoutSample` (5s buckets) — more precise; we can
//      determine "time in zone 5" exactly
//   3. Average HR fallback — for records without samples (Strava, old HK data)
//
// No HealthKit/SwiftData dependency: pure Swift with injected inputs so
// the logic is fully unit-testable.

struct SessionClassifier {

    /// The athlete's maximum heart rate — the basis for zone calculations.
    /// Passed by the caller (in production via `AthleticProfileManager` or the
    /// Tanaka formula; in tests with synthetic values).
    let maxHeartRate: Double

    /// Epic #44 story 44.5: optional LTHR input. When present we use
    /// Friel zones (LTHR percentage) instead of % of max HR for the zone-distribution
    /// classification — that fits athletes with a deviating max/LTHR ratio better.
    let lactateThresholdHR: Double?

    init(maxHeartRate: Double, lactateThresholdHR: Double? = nil) {
        precondition(maxHeartRate > 0, "maxHeartRate moet positief zijn")
        self.maxHeartRate = maxHeartRate
        self.lactateThresholdHR = lactateThresholdHR
    }

    /// Main entry: combines all available signals into one SessionType proposal.
    /// Returns `nil` if there is insufficient data to say anything meaningful.
    func classify(samples: [WorkoutSample]?,
                  averageHeartRate: Double?,
                  durationSeconds: Int,
                  title: String?) -> SessionType? {
        // 1. Title keywords override everything. Race and social have the highest authority
        //    because HR data can be misleading there (group tempo / race strategy).
        if let title, let kw = classifyByKeywords(title: title) {
            return kw
        }

        // 2. Zone distribution if the granular samples are available.
        if let samples, !samples.isEmpty,
           let zoned = classifyByZoneDistribution(samples: samples) {
            return zoned
        }

        // 3. Fallback: average HR ratio + duration heuristic.
        if let avg = averageHeartRate, avg > 0 {
            return classifyByAverageHR(averageHeartRate: avg, durationSeconds: durationSeconds)
        }

        return nil
    }

    // MARK: Keyword-based

    /// Matches on common NL and EN keywords in the workout title. Order matters:
    /// race and social come first — their keyword match is stronger than a physiological
    /// classification that zone data might contradict.
    func classifyByKeywords(title: String) -> SessionType? {
        let lower = title.lowercased()

        // Highest authority: race and social — physiology must not override these.
        if matches(lower, any: ["race", "wedstrijd", "rondje", "criterium"]) { return .race }
        if matches(lower, any: ["social", "sociaal", "samen", "club", "group "]) { return .social }

        // Then intensity-specific keywords.
        if matches(lower, any: ["vo2", "vmax", "intervallen", "interval", "5x", "6x", "8x", "10x"]) { return .vo2Max }
        if matches(lower, any: ["threshold", "drempel", "lactaat", "ftp", "sweet spot"]) { return .threshold }
        if matches(lower, any: ["tempo"]) { return .tempo }
        if matches(lower, any: ["recovery", "herstel", "easy", "rustig", "actief herstel"]) { return .recovery }
        if matches(lower, any: ["long", "duurloop", "duurrit", "lange rit", "long run", "endurance"]) { return .endurance }

        return nil
    }

    private func matches(_ haystack: String, any needles: [String]) -> Bool {
        needles.contains(where: { haystack.contains($0) })
    }

    // MARK: Zone-distribution

    /// Determines the type based on the time distribution across zones. Uses the
    /// common 5-zone split on % of HRmax:
    ///   Z1: <60%, Z2: 60-70%, Z3: 70-80%, Z4: 80-90%, Z5: >=90%
    /// Thresholds (40-60%) are pragmatic — a session is "vo2Max" if at least 25%
    /// of the time was spent in Z5 (interval work also requires recovery in lower zones).
    func classifyByZoneDistribution(samples: [WorkoutSample]) -> SessionType? {
        let hrSamples = samples.compactMap(\.heartRate)
        guard !hrSamples.isEmpty else { return nil }

        // Epic #44 story 44.5: choose between Friel and Karvonen percentages.
        // Friel-LTHR (<81/81-89/90-93/94-99/100+) is more precise for athletes with a
        // deviating LTHR/max ratio; Karvonen on % of max HR is the fallback.
        let zoneMatch: (Double) -> Int = { hr in
            if let lthr = self.lactateThresholdHR, lthr > 0 {
                let pct = hr / lthr
                switch pct {
                case ..<0.81:       return 1
                case 0.81..<0.90:   return 2
                case 0.90..<0.94:   return 3
                case 0.94..<1.00:   return 4
                default:             return 5
                }
            } else {
                let pct = hr / self.maxHeartRate
                switch pct {
                case ..<0.60:       return 1
                case 0.60..<0.70:   return 2
                case 0.70..<0.80:   return 3
                case 0.80..<0.90:   return 4
                default:             return 5
                }
            }
        }

        var z1 = 0, z2 = 0, z3 = 0, z4 = 0, z5 = 0
        for hr in hrSamples {
            switch zoneMatch(hr) {
            case 1: z1 += 1
            case 2: z2 += 1
            case 3: z3 += 1
            case 4: z4 += 1
            default: z5 += 1
            }
        }
        let total = Double(hrSamples.count)
        let z1Pct = Double(z1) / total
        let z2Pct = Double(z2) / total
        let z3Pct = Double(z3) / total
        let z4Pct = Double(z4) / total
        let z5Pct = Double(z5) / total

        // Order matters: high zones first — a session with 30% Z5 is vo2Max,
        // even if 50% is in Z2 (the Z5 stimulus dominates the effect).
        if z5Pct >= 0.25 { return .vo2Max }
        if z4Pct >= 0.30 { return .threshold }
        if z3Pct >= 0.40 { return .tempo }
        if z2Pct + z3Pct >= 0.60 { return .endurance }
        if z1Pct >= 0.60 { return .recovery }

        // No clear peak — best guess based on the centre of gravity.
        let weighted = z1Pct * 1 + z2Pct * 2 + z3Pct * 3 + z4Pct * 4 + z5Pct * 5
        switch weighted {
        case ..<1.5: return .recovery
        case 1.5..<2.5: return .endurance
        case 2.5..<3.5: return .tempo
        case 3.5..<4.5: return .threshold
        default: return .vo2Max
        }
    }

    // MARK: Average HR fallback

    /// For records without fine-grained samples (Strava import, old HK data).
    /// Uses only the average + duration as a signal — less accurate but better than nothing.
    func classifyByAverageHR(averageHeartRate: Double, durationSeconds: Int) -> SessionType {
        let pct = averageHeartRate / maxHeartRate

        // Duration heuristic: a session >90 min with moderate HR is endurance, even if
        // the average is in the tempo range (longer sessions include warm-up + cool-down).
        let isLongSession = durationSeconds >= 90 * 60
        let isShortSession = durationSeconds <= 30 * 60

        switch pct {
        case ..<0.60:
            return .recovery
        case 0.60..<0.70:
            return isShortSession ? .recovery : .endurance
        case 0.70..<0.80:
            return isLongSession ? .endurance : .tempo
        case 0.80..<0.87:
            return .tempo
        case 0.87..<0.92:
            return .threshold
        default:
            // An average >92% HRmax is rare — if it does occur, this is
            // VO2max work or a short race effort. Under 30 min more likely vo2Max.
            return isShortSession ? .vo2Max : .threshold
        }
    }
}
