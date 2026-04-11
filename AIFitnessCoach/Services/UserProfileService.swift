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

    /// UserDefaults-sleutels voor de lokale fallback en leeftijdscache.
    static let weightKey    = "vibecoach_userWeightKg"
    static let heightKey    = "vibecoach_userHeightCm"
    /// Gecachte leeftijd — om te detecteren of HealthKit een gewijzigde waarde teruggeeft.
    static let cachedAgeKey = "vibecoach_cachedAgeYears"

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

    // MARK: - Autorisatie

    /// Vraagt leesrechten voor het volledige fysiologische profiel op.
    ///
    /// Dit is een apart pad van de hoofd-HealthKit-autorisatie in `HealthKitManager`.
    /// Gebruikers die vóór Epic 24 HealthKit koppelden, hebben nooit toestemming gegeven
    /// voor `dateOfBirth`, `biologicalSex`, `bodyMass` of `height`. iOS toont de popup
    /// **opnieuw** voor types die nog niet gevraagd zijn — maar pas als we ze expliciet
    /// meegeven in een `requestAuthorization`-aanroep.
    ///
    /// Karakteristieke types (dateOfBirth, biologicalSex) zijn read-only in HealthKit
    /// en mogen NIET in `toShare` zitten — alleen in `read`.
    func requestProfileReadAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        var read = Set<HKObjectType>()
        if let bodyMass   = HKQuantityType.quantityType(forIdentifier: .bodyMass)   { read.insert(bodyMass) }
        if let height     = HKQuantityType.quantityType(forIdentifier: .height)     { read.insert(height) }
        if let dob        = HKObjectType.characteristicType(forIdentifier: .dateOfBirth)    { read.insert(dob) }
        if let sex        = HKObjectType.characteristicType(forIdentifier: .biologicalSex)  { read.insert(sex) }

        let share: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
            HKQuantityType.quantityType(forIdentifier: .height)!
        ]

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            healthStore.requestAuthorization(toShare: share, read: read) { _, _ in
                continuation.resume()
            }
        }
        print("🔑 [ProfileService] requestProfileReadAuthorization voltooid")
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

    /// Het resultaat van een save-actie.
    /// Ongeacht het resultaat is de waarde altijd al lokaal opgeslagen in UserDefaults.
    enum SaveResult {
        case savedToHealthKit               // Zowel UserDefaults als HealthKit bijgewerkt
        case savedLocallyOnly(String)       // Alleen UserDefaults; HealthKit geweigerd of niet beschikbaar
    }

    /// Slaat een nieuw gewicht op.
    /// UserDefaults wordt altijd direct bijgewerkt.
    /// HealthKit-autorisatie wordt gevraagd vóór de schrijfactie (pop-up als nog niet bepaald).
    func saveWeight(kg: Double) async -> SaveResult {
        guard kg > 0 else { return .savedLocallyOnly("Ongeldig gewicht.") }
        UserDefaults.standard.set(kg, forKey: Self.weightKey)
        return await saveQuantityIfAuthorized(
            value: kg,
            identifier: .bodyMass,
            unit: .gramUnit(with: .kilo)
        )
    }

    /// Slaat een nieuwe lengte op.
    func saveHeight(cm: Double) async -> SaveResult {
        guard cm > 0 else { return .savedLocallyOnly("Ongeldige lengte.") }
        UserDefaults.standard.set(cm, forKey: Self.heightKey)
        return await saveQuantityIfAuthorized(
            value: cm,
            identifier: .height,
            unit: .meterUnit(with: .centi)
        )
    }

    // MARK: - Private helpers

    /// Leest geboortedatum synchronous en berekent de leeftijd in jaren.
    /// Logt de ruwe HealthKit-waarden zodat sync-problemen direct zichtbaar zijn in de console.
    private func fetchAge() -> Int? {
        do {
            let dob = try healthStore.dateOfBirthComponents()
            print("🎂 [HealthKit] Geboortedatum components: \(dob)")
            guard let birthDate = Calendar.current.date(from: dob) else {
                print("🎂 [HealthKit] ⚠️ Kon DateComponents niet omzetten naar Date: \(dob)")
                return nil
            }
            print("🎂 [HealthKit] Geboortedatum als Date: \(birthDate)")
            let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
            print("🎂 [HealthKit] Berekende leeftijd: \(age ?? -1) jaar")
            return age
        } catch {
            print("🎂 [HealthKit] ⚠️ dateOfBirthComponents mislukt — geen leestoegang of niet ingevuld: \(error.localizedDescription)")
            return nil
        }
    }

    /// Vergelijkt de nieuw opgehaalde leeftijd met de gecachte waarde.
    /// Retourneert `true` als de leeftijd is gewijzigd ten opzichte van de vorige fetch.
    /// Slaat de nieuwe leeftijd altijd op als nieuwe cache-baseline.
    func checkAndUpdateAgeCache(newAge: Int) -> Bool {
        let previous = UserDefaults.standard.object(forKey: Self.cachedAgeKey) as? Int
        UserDefaults.standard.set(newAge, forKey: Self.cachedAgeKey)
        guard let prev = previous else { return false }   // eerste keer — geen wijziging te melden
        let changed = prev != newAge
        if changed {
            print("🎂 [ProfileService] Leeftijd gewijzigd: \(prev) → \(newAge) jaar")
        }
        return changed
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

    /// Vraagt schrijftoestemming voor het gegeven type op (als nog niet bepaald),
    /// en schrijft daarna pas het sample naar HealthKit.
    /// Geeft altijd een `SaveResult` terug — gooit nooit — zodat de UI altijd een
    /// bruikbare toestand bereikt, ook bij weigering.
    private func saveQuantityIfAuthorized(
        value: Double,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async -> SaveResult {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return .savedLocallyOnly("HealthKit type niet beschikbaar op dit apparaat.")
        }

        // Stap 1: Vraag autorisatie op als deze nog niet is bepaald.
        // requestAuthorization toont de iOS pop-up bij .notDetermined.
        // Bij .sharingAuthorized of .sharingDenied slaat iOS de aanvraag over.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            healthStore.requestAuthorization(toShare: [type], read: [type]) { _, _ in
                // success geeft alleen aan of de aanvraag kon worden gedaan,
                // niet of de gebruiker 'ja' heeft gezegd. Controleer de status apart.
                continuation.resume()
            }
        }

        // Stap 2: Controleer de daadwerkelijke schrijfstatus na de aanvraag.
        let status = healthStore.authorizationStatus(for: type)
        guard status == .sharingAuthorized else {
            return .savedLocallyOnly("Geen schrijftoegang tot HealthKit. Pas dit aan via Instellingen → Gezondheid.")
        }

        // Stap 3: Schrijf het sample naar HealthKit.
        let quantity = HKQuantity(unit: unit, doubleValue: value)
        let sample   = HKQuantitySample(type: type, quantity: quantity, start: Date(), end: Date())

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                healthStore.save(sample) { _, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            return .savedToHealthKit
        } catch {
            return .savedLocallyOnly("HealthKit schrijven mislukt: \(error.localizedDescription)")
        }
    }
}
