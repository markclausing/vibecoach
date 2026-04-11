import Foundation
import HealthKit

// MARK: - Epic 24 Sprint 1 & 2: Fysiologisch Profiel + Two-Way Sync

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

    /// Geeft aan of dit profiel van HealthKit komt of van de lokale fallback.
    let weightSource: DataSource
    let heightSource: DataSource

    enum DataSource { case healthKit, local, defaultValue }

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

/// Beheert het fysiologische profiel van de gebruiker.
///
/// **Resolutie-hiërarchie (van hoog naar laag):**
/// 1. Recente HealthKit data (single source of truth)
/// 2. Lokale UserDefaults fallback (door gebruiker zelf ingevoerd)
/// 3. Generieke standaardwaarden ("Average Joe")
///
/// **Two-Way Sync:** wijzigingen worden zowel naar UserDefaults als HealthKit geschreven
/// zodat het gehele iOS-ecosysteem up-to-date blijft.
final class UserProfileService: @unchecked Sendable {

    // MARK: - Constanten

    /// UserDefaults-sleutels voor de lokale fallback.
    static let weightKey = "vibecoach_userWeightKg"
    static let heightKey = "vibecoach_userHeightCm"

    /// Standaard-fallbacks als zowel HealthKit als UserDefaults leeg zijn.
    /// Gebaseerd op gemiddelde Nederlandse recreatieve atleet (man, 35j, 75 kg, 178 cm).
    static let defaultWeightKg: Double   = 75.0
    static let defaultHeightCm: Double   = 178.0
    static let defaultAgeYears: Int      = 35
    static let defaultSex: BiologicalSex = .male

    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
    }

    // MARK: - Profiel ophalen

    /// Haalt het volledige profiel op via de 3-tier resolutie-hiërarchie.
    func fetchProfile() async -> UserPhysicalProfile {
        async let hkWeight = fetchLatestQuantity(identifier: .bodyMass, unit: .gramUnit(with: .kilo))
        async let hkHeight = fetchLatestQuantity(identifier: .height,   unit: .meterUnit(with: .centi))
        let (hkWeightResult, hkHeightResult) = await (hkWeight, hkHeight)

        let ageYears = fetchAge() ?? Self.defaultAgeYears
        let sex      = fetchSex() ?? Self.defaultSex

        // Gewicht: HealthKit → UserDefaults → Default
        let (weightKg, weightSource): (Double, UserPhysicalProfile.DataSource)
        if let hk = hkWeightResult {
            (weightKg, weightSource) = (hk, .healthKit)
        } else if let local = UserDefaults.standard.object(forKey: Self.weightKey) as? Double, local > 0 {
            (weightKg, weightSource) = (local, .local)
        } else {
            (weightKg, weightSource) = (Self.defaultWeightKg, .defaultValue)
        }

        // Lengte: HealthKit → UserDefaults → Default
        let (heightCm, heightSource): (Double, UserPhysicalProfile.DataSource)
        if let hk = hkHeightResult {
            (heightCm, heightSource) = (hk, .healthKit)
        } else if let local = UserDefaults.standard.object(forKey: Self.heightKey) as? Double, local > 0 {
            (heightCm, heightSource) = (local, .local)
        } else {
            (heightCm, heightSource) = (Self.defaultHeightCm, .defaultValue)
        }

        return UserPhysicalProfile(
            weightKg:      weightKg,
            heightCm:      heightCm,
            ageYears:      ageYears,
            sex:           sex,
            weightSource:  weightSource,
            heightSource:  heightSource
        )
    }

    // MARK: - Two-Way Sync: opslaan

    /// Slaat een nieuw gewicht op in UserDefaults én HealthKit.
    /// UserDefaults wordt direct bijgewerkt; HealthKit is async maar ook de 'bron van waarheid'.
    func saveWeight(kg: Double) async throws {
        guard kg > 0 else { return }
        UserDefaults.standard.set(kg, forKey: Self.weightKey)
        try await saveQuantity(value: kg, identifier: .bodyMass, unit: .gramUnit(with: .kilo))
    }

    /// Slaat een nieuwe lengte op in UserDefaults én HealthKit.
    func saveHeight(cm: Double) async throws {
        guard cm > 0 else { return }
        UserDefaults.standard.set(cm, forKey: Self.heightKey)
        try await saveQuantity(value: cm, identifier: .height, unit: .meterUnit(with: .centi))
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

    /// Schrijft een kwantitatieve meting als nieuw HKQuantitySample naar HealthKit.
    private func saveQuantity(value: Double, identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return }
        let quantity = HKQuantity(unit: unit, doubleValue: value)
        let sample   = HKQuantitySample(type: type, quantity: quantity, start: Date(), end: Date())

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(sample) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
