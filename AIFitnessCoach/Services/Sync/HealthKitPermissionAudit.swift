import Foundation

/// Epic #62 story 62.4 (was 51.F3) — pure-Swift mapping from *which critical HealthKit signals
/// are unavailable* (denied or not-determined per type) to *which app features degrade*. Lets the
/// permission overview tell the user concretely what stops working ("no HRV → no Vibe Score")
/// instead of a blanket "HealthKit not fully connected".
///
/// Framework-free (§6): the caller reads `authorizationStatus(for:)` per type and passes the set
/// of missing signals; this type owns only the signal→feature mapping. The View localises the
/// returned feature cases.
enum HealthKitPermissionAudit {

    /// The critical read signals whose absence breaks a coaching feature (mirrors
    /// `HealthKitPermissionTypes.critical`).
    enum CriticalSignal: String, CaseIterable, Equatable {
        case workouts
        case heartRate
        case hrv
        case activeEnergy
    }

    /// App features that stop working when their underlying signal is unavailable.
    enum DegradedFeature: String, CaseIterable, Equatable {
        case schedule          // training history + the generated week schedule
        case intensityZones    // HR-zone classification of sessions
        case vibeScore         // recovery score (needs HRV)
        case loadEstimate      // active-energy-based load/fuel estimates
    }

    /// The features that degrade given the set of unavailable critical signals. Empty in, empty out.
    static func degradedFeatures(missing: Set<CriticalSignal>) -> Set<DegradedFeature> {
        var features: Set<DegradedFeature> = []
        for signal in missing {
            switch signal {
            case .workouts:     features.insert(.schedule)
            case .heartRate:    features.insert(.intensityZones)
            case .hrv:          features.insert(.vibeScore)
            case .activeEnergy: features.insert(.loadEstimate)
            }
        }
        return features
    }
}
