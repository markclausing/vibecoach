import Foundation
import HealthKit

// MARK: - Epic 24 Sprint 1 & 2: Fysiologisch Profiel + Two-Way Sync

/// Beschrijft het biologische geslacht van de gebruiker, nodig voor de BMR-formule.
enum BiologicalSex: String, Codable {
    case male, female, other, unknown
}

// MARK: - Epic 44 Story 44.1: ThresholdValue

/// Eén fysiologische drempel met source-tracking. Source bepaalt UI-badging
/// ("auto · 14 dagen" / "Strava" / "handmatig") en speelt in 44.2 ook de rol
/// van prioriteit: handmatige overrides winnen altijd van automatische detectie.
struct ThresholdValue: Equatable, Codable {
    let value: Double
    let source: ThresholdSource
}

enum ThresholdSource: String, Codable, Equatable {
    /// Gedetecteerd uit HealthKit-historie via `PhysiologicalThresholdEstimator`.
    case automatic
    /// Door gebruiker handmatig ingevoerd in Settings — wint altijd van automatic.
    case manual
    /// Geïmporteerd vanuit Strava `Athlete`-endpoint (alleen FTP).
    case strava
}

/// Fysiologisch profiel van de gebruiker — opgehaald via HealthKit met fallbacks.
/// Dit profiel is de basis voor alle voedingsberekeningen in `NutritionService`
/// en — sinds Epic #44 — ook voor de zone-kalibratie van `WorkoutPatternDetector`
/// en `SessionClassifier`.
struct UserPhysicalProfile {
    let weightKg: Double        // lichaamsgewicht in kilogram
    let heightCm: Double        // lichaamslengte in centimeter
    let ageYears: Int           // leeftijd in jaren
    let sex: BiologicalSex      // biologisch geslacht voor BMR-formule

    /// Geeft aan of dit profiel van HealthKit komt of van de lokale fallback.
    let weightSource: DataSource
    let heightSource: DataSource

    // Epic #44 Story 44.1: persoonlijke trainingsdrempels. Optioneel — een nieuwe
    // installatie zonder HK-historie en zonder handmatige invoer heeft hier nil.
    // Gebruikers van vóór Epic #44 zien nil totdat ze hun eerste HK-detectie
    // draaien of waardes invoeren in Settings.
    let maxHeartRate: ThresholdValue?
    let restingHeartRate: ThresholdValue?
    let lactateThresholdHR: ThresholdValue?
    let ftp: ThresholdValue?

    enum DataSource { case healthKit, local, defaultValue }

    /// Expliciete init met defaults voor de 44.1-velden. Bestaande callers
    /// (vóór deze Epic) compileren ongewijzigd door — de nieuwe optionele
    /// drempels krijgen automatisch nil.
    init(weightKg: Double,
         heightCm: Double,
         ageYears: Int,
         sex: BiologicalSex,
         weightSource: DataSource,
         heightSource: DataSource,
         maxHeartRate: ThresholdValue? = nil,
         restingHeartRate: ThresholdValue? = nil,
         lactateThresholdHR: ThresholdValue? = nil,
         ftp: ThresholdValue? = nil) {
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.ageYears = ageYears
        self.sex = sex
        self.weightSource = weightSource
        self.heightSource = heightSource
        self.maxHeartRate = maxHeartRate
        self.restingHeartRate = restingHeartRate
        self.lactateThresholdHR = lactateThresholdHR
        self.ftp = ftp
    }

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

    // MARK: - Epic 44: effectieve drempels met fallbacks

    /// Effectieve max-HR voor zone-berekeningen. Valt terug op Tanaka(`ageYears`)
    /// wanneer geen handmatige of auto-gedetecteerde waarde beschikbaar is.
    var effectiveMaxHeartRate: Double {
        if let stored = maxHeartRate?.value, stored > 0 { return stored }
        guard ageYears > 0, ageYears < 120 else { return HeartRateZones.defaultMaxHeartRate }
        return 208.0 - 0.7 * Double(ageYears)
    }

    /// Effectieve rust-HR. Default 60 BPM (gemiddelde gezonde volwassene) als fallback.
    var effectiveRestingHeartRate: Double {
        if let stored = restingHeartRate?.value, stored > 0 { return stored }
        return 60.0
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

    // MARK: - Epic 44 Story 44.1: drempels in UserDefaults
    //
    // Per drempel slaan we een JSON-blob op met `value` + `source`. Eén key per
    // drempel houdt de migratie eenvoudig: nieuwe veldjes voegen we toe aan de
    // `ThresholdValue`-Codable zonder alle keys te moeten herschrijven.
    static let maxHeartRateKey       = "vibecoach_maxHeartRate.v1"
    static let restingHeartRateKey   = "vibecoach_restingHeartRate.v1"
    static let lactateThresholdHRKey = "vibecoach_lactateThresholdHR.v1"
    static let ftpKey                = "vibecoach_ftp.v1"

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

    // MARK: - Synchrone cache-toegang

    /// Bouwt een profiel uitsluitend op basis van UserDefaults-cache — geen HealthKit-aanroep nodig.
    /// Geschikt voor synchrone gebruik in SwiftUI-views (bijv. WorkoutCardView).
    /// Volgorde: UserDefaults-waarden → generieke standaard.
    static func cachedProfile() -> UserPhysicalProfile {
        let weightKg = UserDefaults.standard.object(forKey: weightKey)    as? Double ?? defaultWeightKg
        let heightCm = UserDefaults.standard.object(forKey: heightKey)    as? Double ?? defaultHeightCm
        let ageYears = UserDefaults.standard.object(forKey: cachedAgeKey) as? Int    ?? defaultAgeYears
        return UserPhysicalProfile(
            weightKg:     weightKg,
            heightCm:     heightCm,
            ageYears:     ageYears,
            sex:          defaultSex,       // geslacht is niet gecacht; effect op BMR ≈ 5%
            weightSource: .local,
            heightSource: .local,
            maxHeartRate:       cachedThreshold(forKey: maxHeartRateKey),
            restingHeartRate:   cachedThreshold(forKey: restingHeartRateKey),
            lactateThresholdHR: cachedThreshold(forKey: lactateThresholdHRKey),
            ftp:                cachedThreshold(forKey: ftpKey)
        )
    }

    // MARK: - Epic 44: Threshold persistence

    /// Leest één `ThresholdValue` uit UserDefaults via JSON-decode. Returnt nil als
    /// de key leeg is of de blob corrupt — caller valt dan terug op formule-default
    /// (Tanaka-maxHR, 60 BPM rust, etc.).
    static func cachedThreshold(forKey key: String,
                                defaults: UserDefaults = .standard) -> ThresholdValue? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ThresholdValue.self, from: data)
    }

    /// Slaat één `ThresholdValue` op in UserDefaults. Synchroon — caller kan dit
    /// direct na een UI-actie aanroepen zonder await.
    static func saveThreshold(_ value: ThresholdValue?,
                              forKey key: String,
                              defaults: UserDefaults = .standard) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    /// Convenience: bewaar elke drempel die in `Result` aanwezig is met source
    /// `.automatic`. Bestaande `.manual`-waarden worden behouden — handmatige
    /// invoer wint altijd van automatische detectie. Caller (bv. settings-flow)
    /// moet dus zelf checken op `.manual` voordat hij overschrijft, of expliciet
    /// `force: true` doorgeven om die guard te omzeilen.
    static func storeAutoDetectedThresholds(_ result: PhysiologicalThresholdEstimator.Result,
                                            force: Bool = false,
                                            defaults: UserDefaults = .standard) {
        store(result.maxHeartRate, forKey: maxHeartRateKey, force: force, defaults: defaults)
        store(result.restingHeartRate, forKey: restingHeartRateKey, force: force, defaults: defaults)
        store(result.lactateThresholdHR, forKey: lactateThresholdHRKey, force: force, defaults: defaults)
    }

    private static func store(_ newValue: Double?,
                              forKey key: String,
                              force: Bool,
                              defaults: UserDefaults) {
        guard let newValue else { return }
        if !force, let existing = cachedThreshold(forKey: key, defaults: defaults), existing.source == .manual {
            return // Niet overschrijven; handmatige invoer is leidend.
        }
        saveThreshold(ThresholdValue(value: newValue, source: .automatic), forKey: key, defaults: defaults)
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
            heightSource:  heightSource,
            maxHeartRate:       Self.cachedThreshold(forKey: Self.maxHeartRateKey),
            restingHeartRate:   Self.cachedThreshold(forKey: Self.restingHeartRateKey),
            lactateThresholdHR: Self.cachedThreshold(forKey: Self.lactateThresholdHRKey),
            ftp:                Self.cachedThreshold(forKey: Self.ftpKey)
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
    /// Ruwe geboortedatum wordt bewust NIET gelogd (PII/PHI — CodeQL: cleartext logging of sensitive information).
    /// Alleen de afgeleide leeftijd en foutmeldingen zijn zichtbaar voor sync-debug.
    private func fetchAge() -> Int? {
        do {
            let dob = try healthStore.dateOfBirthComponents()
            guard let birthDate = Calendar.current.date(from: dob) else {
                print("🎂 [HealthKit] ⚠️ Kon DateComponents niet omzetten naar Date.")
                return nil
            }
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
