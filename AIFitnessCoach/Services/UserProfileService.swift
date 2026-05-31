import Foundation
import HealthKit

// MARK: - Epic 24 Sprint 1 & 2: Physiological Profile + Two-Way Sync

/// Describes the user's biological sex, needed for the BMR formula.
enum BiologicalSex: String, Codable {
    case male, female, other, unknown
}

// MARK: - Epic 44 Story 44.1: ThresholdValue

/// One physiological threshold with source tracking. The source determines UI
/// badging ("auto · 14 dagen" / "Strava" / "handmatig") and in 44.2 also plays
/// the role of priority: manual overrides always beat automatic detection.
struct ThresholdValue: Equatable, Codable {
    let value: Double
    let source: ThresholdSource
}

enum ThresholdSource: String, Codable, Equatable {
    /// Detected from HealthKit history via `PhysiologicalThresholdEstimator`.
    case automatic
    /// Entered manually by the user in Settings — always beats automatic.
    case manual
    /// Imported from the Strava `Athlete` endpoint (FTP only).
    case strava
}

/// The user's physiological profile — fetched via HealthKit with fallbacks.
/// This profile is the basis for all nutrition calculations in `NutritionService`
/// and — since Epic #44 — also for the zone calibration of `WorkoutPatternDetector`
/// and `SessionClassifier`.
struct UserPhysicalProfile {
    let weightKg: Double        // body weight in kilograms
    let heightCm: Double        // body height in centimeters
    let ageYears: Int           // age in years
    let sex: BiologicalSex      // biological sex for the BMR formula

    /// Indicates whether this profile comes from HealthKit or the local fallback.
    let weightSource: DataSource
    let heightSource: DataSource

    // Epic #44 Story 44.1: personal training thresholds. Optional — a fresh
    // install without HK history and without manual input has nil here.
    // Users from before Epic #44 see nil until they run their first HK detection
    // or enter values in Settings.
    let maxHeartRate: ThresholdValue?
    let restingHeartRate: ThresholdValue?
    let lactateThresholdHR: ThresholdValue?
    let ftp: ThresholdValue?

    enum DataSource { case healthKit, local, defaultValue }

    /// Explicit init with defaults for the 44.1 fields. Existing callers
    /// (from before this Epic) keep compiling unchanged — the new optional
    /// thresholds automatically get nil.
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

    /// True if the profile is complete (no defaults used).
    var isComplete: Bool {
        weightKg > 0 && heightCm > 0 && ageYears > 0 && sex != .unknown
    }

    /// Readable summary for the coach prompt.
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

    // MARK: - Epic 44: effective thresholds with fallbacks

    /// Effective max HR for zone calculations. Falls back to Tanaka(`ageYears`)
    /// when no manual or auto-detected value is available.
    var effectiveMaxHeartRate: Double {
        if let stored = maxHeartRate?.value, stored > 0 { return stored }
        guard ageYears > 0, ageYears < 120 else { return HeartRateZones.defaultMaxHeartRate }
        return 208.0 - 0.7 * Double(ageYears)
    }

    /// Effective resting HR. Default 60 BPM (average healthy adult) as fallback.
    var effectiveRestingHeartRate: Double {
        if let stored = restingHeartRate?.value, stored > 0 { return stored }
        return 60.0
    }
}

/// Manages the user's physiological profile.
///
/// **Resolution hierarchy (high to low):**
/// 1. Recent HealthKit data (single source of truth)
/// 2. Local UserDefaults fallback (entered by the user)
/// 3. Generic default values ("Average Joe")
///
/// **Two-Way Sync:** changes are written to both UserDefaults and HealthKit so
/// the whole iOS ecosystem stays up to date.
final class UserProfileService: @unchecked Sendable {

    // MARK: - Constants

    /// UserDefaults keys for the local fallback and the age cache.
    static let weightKey    = "vibecoach_userWeightKg"
    static let heightKey    = "vibecoach_userHeightCm"
    /// Cached age — to detect whether HealthKit returns a changed value.
    static let cachedAgeKey = "vibecoach_cachedAgeYears"

    // MARK: - Epic 44 Story 44.1: thresholds in UserDefaults
    //
    // Per threshold we store a JSON blob with `value` + `source`. One key per
    // threshold keeps the migration simple: new fields go into the
    // `ThresholdValue` Codable without having to rewrite all keys.
    static let maxHeartRateKey       = "vibecoach_maxHeartRate.v1"
    static let restingHeartRateKey   = "vibecoach_restingHeartRate.v1"
    static let lactateThresholdHRKey = "vibecoach_lactateThresholdHR.v1"
    static let ftpKey                = "vibecoach_ftp.v1"

    /// Default fallbacks when both HealthKit and UserDefaults are empty.
    /// Based on an average Dutch recreational athlete (male, 35y, 75 kg, 178 cm).
    static let defaultWeightKg: Double   = 75.0
    static let defaultHeightCm: Double   = 178.0
    static let defaultAgeYears: Int      = 35
    static let defaultSex: BiologicalSex = .male

    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
    }

    // MARK: - Synchronous cache access

    /// Builds a profile purely from the UserDefaults cache — no HealthKit call needed.
    /// Suitable for synchronous use in SwiftUI views (e.g. WorkoutCardView).
    /// Order: UserDefaults values → generic default.
    static func cachedProfile() -> UserPhysicalProfile {
        let weightKg = UserDefaults.standard.object(forKey: weightKey)    as? Double ?? defaultWeightKg
        let heightCm = UserDefaults.standard.object(forKey: heightKey)    as? Double ?? defaultHeightCm
        let ageYears = UserDefaults.standard.object(forKey: cachedAgeKey) as? Int    ?? defaultAgeYears
        return UserPhysicalProfile(
            weightKg: weightKg,
            heightCm: heightCm,
            ageYears: ageYears,
            sex: defaultSex,       // sex isn't cached; effect on BMR ≈ 5%
            weightSource: .local,
            heightSource: .local,
            maxHeartRate: cachedThreshold(forKey: maxHeartRateKey),
            restingHeartRate: cachedThreshold(forKey: restingHeartRateKey),
            lactateThresholdHR: cachedThreshold(forKey: lactateThresholdHRKey),
            ftp: cachedThreshold(forKey: ftpKey)
        )
    }

    // MARK: - Epic 44: Threshold persistence

    /// Reads one `ThresholdValue` from UserDefaults via JSON decode. Returns nil if
    /// the key is empty or the blob is corrupt — the caller then falls back to the
    /// formula default (Tanaka maxHR, 60 BPM rest, etc.).
    static func cachedThreshold(forKey key: String,
                                defaults: UserDefaults = .standard) -> ThresholdValue? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ThresholdValue.self, from: data)
    }

    /// Stores one `ThresholdValue` in UserDefaults. Synchronous — the caller can
    /// call this directly after a UI action without await.
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

    /// Convenience: store every threshold present in `Result` with source
    /// `.automatic`. Existing `.manual` values are preserved — manual input always
    /// beats automatic detection. The caller (e.g. settings flow) must therefore
    /// check for `.manual` itself before overwriting, or explicitly pass
    /// `force: true` to bypass that guard.
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
            return // Don't overwrite; manual input is authoritative.
        }
        saveThreshold(ThresholdValue(value: newValue, source: .automatic), forKey: key, defaults: defaults)
    }

    // MARK: - Authorization

    /// Requests read access for the full physiological profile.
    ///
    /// This is a separate path from the main HealthKit authorization in `HealthKitManager`.
    /// Users who linked HealthKit before Epic 24 never granted permission for
    /// `dateOfBirth`, `biologicalSex`, `bodyMass` or `height`. iOS shows the popup
    /// **again** for types not yet requested — but only once we explicitly include
    /// them in a `requestAuthorization` call.
    ///
    /// Characteristic types (dateOfBirth, biologicalSex) are read-only in HealthKit
    /// and must NOT be in `toShare` — only in `read`.
    func requestProfileReadAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        var read = Set<HKObjectType>()
        if let bodyMass   = HKQuantityType.quantityType(forIdentifier: .bodyMass) { read.insert(bodyMass) }
        if let height     = HKQuantityType.quantityType(forIdentifier: .height) { read.insert(height) }
        if let dob        = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { read.insert(dob) }
        if let sex        = HKObjectType.characteristicType(forIdentifier: .biologicalSex) { read.insert(sex) }

        let share: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
            HKQuantityType.quantityType(forIdentifier: .height)!
        ]

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            healthStore.requestAuthorization(toShare: share, read: read) { _, _ in
                continuation.resume()
            }
        }
        AppLoggers.userProfile.info("requestProfileReadAuthorization voltooid")
    }

    // MARK: - Fetch profile

    /// Fetches the full profile via the 3-tier resolution hierarchy.
    func fetchProfile() async -> UserPhysicalProfile {
        async let hkWeight = fetchLatestQuantity(identifier: .bodyMass, unit: .gramUnit(with: .kilo))
        async let hkHeight = fetchLatestQuantity(identifier: .height, unit: .meterUnit(with: .centi))
        let (hkWeightResult, hkHeightResult) = await (hkWeight, hkHeight)

        let ageYears = fetchAge() ?? Self.defaultAgeYears
        let sex      = fetchSex() ?? Self.defaultSex

        // Weight: HealthKit → UserDefaults → Default
        let (weightKg, weightSource): (Double, UserPhysicalProfile.DataSource)
        if let hk = hkWeightResult {
            (weightKg, weightSource) = (hk, .healthKit)
        } else if let local = UserDefaults.standard.object(forKey: Self.weightKey) as? Double, local > 0 {
            (weightKg, weightSource) = (local, .local)
        } else {
            (weightKg, weightSource) = (Self.defaultWeightKg, .defaultValue)
        }

        // Height: HealthKit → UserDefaults → Default
        let (heightCm, heightSource): (Double, UserPhysicalProfile.DataSource)
        if let hk = hkHeightResult {
            (heightCm, heightSource) = (hk, .healthKit)
        } else if let local = UserDefaults.standard.object(forKey: Self.heightKey) as? Double, local > 0 {
            (heightCm, heightSource) = (local, .local)
        } else {
            (heightCm, heightSource) = (Self.defaultHeightCm, .defaultValue)
        }

        return UserPhysicalProfile(
            weightKg: weightKg,
            heightCm: heightCm,
            ageYears: ageYears,
            sex: sex,
            weightSource: weightSource,
            heightSource: heightSource,
            maxHeartRate: Self.cachedThreshold(forKey: Self.maxHeartRateKey),
            restingHeartRate: Self.cachedThreshold(forKey: Self.restingHeartRateKey),
            lactateThresholdHR: Self.cachedThreshold(forKey: Self.lactateThresholdHRKey),
            ftp: Self.cachedThreshold(forKey: Self.ftpKey)
        )
    }

    // MARK: - Two-Way Sync: saving

    /// The result of a save action.
    /// Regardless of the result, the value has always already been saved locally in UserDefaults.
    enum SaveResult {
        case savedToHealthKit               // Both UserDefaults and HealthKit updated
        case savedLocallyOnly(String)       // UserDefaults only; HealthKit denied or unavailable
    }

    /// Saves a new weight.
    /// UserDefaults is always updated immediately.
    /// HealthKit authorization is requested before the write action (pop-up if not yet determined).
    func saveWeight(kg: Double) async -> SaveResult {
        guard kg > 0 else { return .savedLocallyOnly("Ongeldig gewicht.") }
        UserDefaults.standard.set(kg, forKey: Self.weightKey)
        return await saveQuantityIfAuthorized(
            value: kg,
            identifier: .bodyMass,
            unit: .gramUnit(with: .kilo)
        )
    }

    /// Saves a new height.
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

    /// Reads the date of birth synchronously and computes the age in years.
    /// The raw date of birth is deliberately NOT logged (PII/PHI — CodeQL: cleartext logging of sensitive information).
    /// Only the derived age and error messages are visible for sync debugging.
    private func fetchAge() -> Int? {
        do {
            let dob = try healthStore.dateOfBirthComponents()
            guard let birthDate = Calendar.current.date(from: dob) else {
                AppLoggers.userProfile.error("Kon DateComponents niet omzetten naar Date")
                return nil
            }
            let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
            AppLoggers.userProfile.info("Berekende leeftijd: \(age ?? -1, privacy: .private) jaar")
            return age
        } catch {
            AppLoggers.userProfile.error("dateOfBirthComponents mislukt: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Compares the newly fetched age with the cached value.
    /// Returns `true` if the age changed relative to the previous fetch.
    /// Always stores the new age as the new cache baseline.
    func checkAndUpdateAgeCache(newAge: Int) -> Bool {
        let previous = UserDefaults.standard.object(forKey: Self.cachedAgeKey) as? Int
        UserDefaults.standard.set(newAge, forKey: Self.cachedAgeKey)
        guard let prev = previous else { return false }   // first time — no change to report
        let changed = prev != newAge
        if changed {
            AppLoggers.userProfile.info("Leeftijd gewijzigd: \(prev, privacy: .private) → \(newAge, privacy: .private) jaar")
        }
        return changed
    }

    /// Reads biological sex synchronously.
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

    /// Fetches the most recent value for a quantitative HealthKit type.
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

    /// Requests write permission for the given type (if not yet determined), and
    /// only then writes the sample to HealthKit.
    /// Always returns a `SaveResult` — never throws — so the UI always reaches a
    /// usable state, even on denial.
    private func saveQuantityIfAuthorized(
        value: Double,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async -> SaveResult {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return .savedLocallyOnly("HealthKit type niet beschikbaar op dit apparaat.")
        }

        // Step 1: Request authorization if not yet determined.
        // requestAuthorization shows the iOS pop-up on .notDetermined.
        // On .sharingAuthorized or .sharingDenied iOS skips the request.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            healthStore.requestAuthorization(toShare: [type], read: [type]) { _, _ in
                // success only indicates whether the request could be made,
                // not whether the user said 'yes'. Check the status separately.
                continuation.resume()
            }
        }

        // Step 2: Check the actual write status after the request.
        let status = healthStore.authorizationStatus(for: type)
        guard status == .sharingAuthorized else {
            return .savedLocallyOnly("Geen schrijftoegang tot HealthKit. Pas dit aan via Instellingen → Gezondheid.")
        }

        // Step 3: Write the sample to HealthKit.
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
