import Foundation

// MARK: - Epic 33 Story 33.1: SessionClassifier
//
// Pure-Swift classifier die op basis van fysiologische data + titel-keywords een
// `SessionType` voorstelt. Drie strategieën, in volgorde van zekerheid:
//
//   1. Keywords in title  (gebruiker-intentie weegt zwaarder dan ruwe data — een
//      "Sociale rit" met hoge HR blijft sociaal, ook al lijkt-ie qua zone op tempo)
//   2. Zone-distributie via `WorkoutSample` (5s buckets) — preciezer; we kunnen
//      "tijd in zone 5" exact bepalen
//   3. Average HR fallback — voor records zonder samples (Strava, oude HK-data)
//
// Geen HealthKit/SwiftData dependency: pure Swift met geïnjecteerde inputs zodat
// de logica volledig unit-testbaar is.

struct SessionClassifier {

    /// Maximale hartslag van de atleet — basis voor zone-berekeningen.
    /// Wordt door de caller doorgegeven (in productie via `AthleticProfileManager` of
    /// Tanaka-formule; in tests met synthetische waardes).
    let maxHeartRate: Double

    /// Epic #44 story 44.5: optionele LTHR-input. Bij aanwezigheid gebruiken we
    /// Friel-zones (LTHR-percentage) i.p.v. % van max-HR voor de zone-distributie-
    /// classificatie — dat past beter bij atleten met afwijkende max/LTHR-ratio.
    let lactateThresholdHR: Double?

    init(maxHeartRate: Double, lactateThresholdHR: Double? = nil) {
        precondition(maxHeartRate > 0, "maxHeartRate moet positief zijn")
        self.maxHeartRate = maxHeartRate
        self.lactateThresholdHR = lactateThresholdHR
    }

    /// Hoofd-entry: combineert alle beschikbare signalen in één SessionType-voorstel.
    /// Geeft `nil` als er onvoldoende data is om iets zinnigs te zeggen.
    func classify(samples: [WorkoutSample]?,
                  averageHeartRate: Double?,
                  durationSeconds: Int,
                  title: String?) -> SessionType? {
        // 1. Title-keywords overrulen alles. Race en social hebben de hoogste autoriteit
        //    omdat HR-data daar misleidend kan zijn (groep-tempo / wedstrijd-strategie).
        if let title, let kw = classifyByKeywords(title: title) {
            return kw
        }

        // 2. Zone-distributie als de granulaire samples beschikbaar zijn.
        if let samples, !samples.isEmpty,
           let zoned = classifyByZoneDistribution(samples: samples) {
            return zoned
        }

        // 3. Fallback: average HR ratio + duur-heuristiek.
        if let avg = averageHeartRate, avg > 0 {
            return classifyByAverageHR(averageHeartRate: avg, durationSeconds: durationSeconds)
        }

        return nil
    }

    // MARK: Keyword-based

    /// Match op gangbare NL- en EN-trefwoorden in de workout-titel. Volgorde matters:
    /// race en social staan bovenaan — hun keyword-match is sterker dan een fysiologische
    /// classificatie die op zone-data zou kunnen tegenspreken.
    func classifyByKeywords(title: String) -> SessionType? {
        let lower = title.lowercased()

        // Hoogste autoriteit: race en social — hier mag fysiologie niet over heersen.
        if matches(lower, any: ["race", "wedstrijd", "rondje", "criterium"]) { return .race }
        if matches(lower, any: ["social", "sociaal", "samen", "club", "group "]) { return .social }

        // Daarna intensiteit-specifieke keywords.
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

    /// Bepaalt het type op basis van de tijdsverdeling over zones. Gebruikt de
    /// gangbare 5-zone-indeling op % van HRmax:
    ///   Z1: <60%, Z2: 60-70%, Z3: 70-80%, Z4: 80-90%, Z5: >=90%
    /// Drempels (40-60%) zijn pragmatisch — een sessie is "vo2Max" als minstens 25%
    /// van de tijd in Z5 is doorgebracht (intervalwerk vereist ook recovery in lagere zones).
    func classifyByZoneDistribution(samples: [WorkoutSample]) -> SessionType? {
        let hrSamples = samples.compactMap(\.heartRate)
        guard !hrSamples.isEmpty else { return nil }

        // Epic #44 story 44.5: kies tussen Friel- en Karvonen-percentages.
        // Friel-LTHR (<81/81-89/90-93/94-99/100+) is preciezer voor atleten met
        // afwijkende LTHR/max-ratio; Karvonen op % van max-HR is de fallback.
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

        // Volgorde belangrijk: hoge zones eerst — een sessie met 30% Z5 is vo2Max,
        // ook al is 50% in Z2 (de Z5-stimulus domineert het effect).
        if z5Pct >= 0.25 { return .vo2Max }
        if z4Pct >= 0.30 { return .threshold }
        if z3Pct >= 0.40 { return .tempo }
        if z2Pct + z3Pct >= 0.60 { return .endurance }
        if z1Pct >= 0.60 { return .recovery }

        // Geen duidelijke piek — beste gok op basis van zwaartepunt.
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

    /// Voor records zonder fijngranulaire samples (Strava-import, oude HK-data).
    /// Gebruikt alleen het gemiddelde + duur als signaal — minder accuraat maar beter dan niets.
    func classifyByAverageHR(averageHeartRate: Double, durationSeconds: Int) -> SessionType {
        let pct = averageHeartRate / maxHeartRate

        // Duur-heuristiek: een sessie >90 min met matige HR is endurance, ook al ligt
        // het gemiddelde in tempo-range (langere sessies hebben warming-up + cooling).
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
            // Gemiddelde >92% HRmax is zeldzaam — komt het wel voor, dan is dit een
            // VO2max-werk of korte race-effort. Onder de 30 min eerder vo2Max.
            return isShortSession ? .vo2Max : .threshold
        }
    }
}
