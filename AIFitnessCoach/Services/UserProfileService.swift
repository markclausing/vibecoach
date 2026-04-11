import Foundation
import HealthKit

// MARK: - Epic 24 Sprint 1: Fysiologisch Profiel

/// Beschrijft het biologische geslacht van de gebruiker, nodig voor de BMR-formule.
enum BiologicalSex: String, Codable {
    case male, female, other, unknown
}

/// Fysiologisch profiel van de gebruiker — opgehaald via HealthKit met fallbacks.
/// Dit profiel is de basis voor alle voedingsberekeningen in `NutritionService`.
struct UserPhysicalProfile {
    let weightKg: Double        // lichaamsgewicht in kilogram
    let heightCm: Double        // lichaamslengte in centimeter
    let ageYears: Int           // leeftijd in jaren
    let sex: BiologicalSex      // biologisch geslacht voor BMR-formule

    /// True als het profiel volledig is (geen defaults gebruikt).
    var isComplete: Bool {
        weightKg > 0 && heightCm > 0 && ageYears > 0 && sex != .unknown
    }

    /// Leesbare samenvatting voor de coach-prompt.
    var coachSummary: String {
        let sexLabel: String
        switch sex {
        case .male:    sexLabel = "man"
        case .female:  sexLabel = "vrouw"
        case .other:   sexLabel = "divers"
        case .unknown: sexLabel = "onbekend"
        }
        return "\(Int(weightKg)) kg, \(Int(heightCm)) cm, \(ageYears) jaar, \(sexLabel)"
    }
}

/// Haalt het fysiologische profiel op uit HealthKit.
/// Karakteristieke types (geboortedatum, geslacht) vereisen geen async query —
/// ze zijn direct synchronous beschikbaar als de gebruiker toestemming heeft verleend.
/// Kwantitatieve types (gewicht, lengte) worden via HKSampleQuery opgehaald.
final class UserProfileService: @unchecked Sendable {

    // Standaard-fallbacks als HealthKit-data ontbreekt.
    // Gebaseerd op gemiddelde Nederlandse recreatieve atleet (man, 35j, 75 kg, 178 cm).
    static let defaultWeightKg: Double  = 75.0
    static let defaultHeightCm: Double  = 178.0
    static let defaultAgeYears: Int     = 35
    static let defaultSex: BiologicalSex = .male

    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
    }

    /// Haalt het volledige profiel op. Valt terug op defaults als HealthKit data niet beschikbaar is.
    func fetchProfile() async -> UserPhysicalProfile {
        async let weight = fetchLatestQuantity(identifier: .bodyMass, unit: .gramUnit(with: .kilo))
        async let height = fetchLatestQuantity(identifier: .height,   unit: .meterUnit(with: .centi))
        let (weightResult, heightResult) = await (weight, height)

        let ageYears  = fetchAge()    ?? Self.defaultAgeYears
        let sex       = fetchSex()    ?? Self.defaultSex
        let weightKg  = weightResult  ?? Self.defaultWeightKg
        let heightCm  = heightResult  ?? Self.defaultHeightCm

        return UserPhysicalProfile(
            weightKg:  weightKg,
            heightCm:  heightCm,
            ageYears:  ageYears,
            sex:       sex
        )
    }

    // MARK: - Private helpers

    /// Leest geboortedatum synchronous en berekent de leeftijd in jaren.
    private func fetchAge() -> Int? {
        guard let dob = try? healthStore.dateOfBirthComponents(),
              let birthDate = Calendar.current.date(from: dob) else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }

    /// Leest biologisch geslacht synchronous.
    private func fetchSex() -> BiologicalSex? {
        guard let hkSex = try? healthStore.biologicalSex() else { return nil }
        switch hkSex.biologicalSex {
        case .male:         return .male
        case .female:       return .female
        case .other:        return .other
        case .notSet:       return nil
        @unknown default:   return nil
        }
    }

    /// Haalt de meest recente waarde op voor een kwantitatief HealthKit-type.
    private func fetchLatestQuantity(identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
}
