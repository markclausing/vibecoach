import Foundation
import SwiftData

/// Stores the daily Readiness Score, computed from sleep and HRV (Epic 14).
/// At most one record per day is kept — upsert via the ReadinessService.
///
/// **Schema V2 change:** `@Attribute(.unique)` added on `date` so the "max 1 per day"
/// invariant is also enforced DB-side (previously only via the service-layer upsert, which
/// was race-prone). Existing duplicates are deduped in `AppMigrationPlan.willMigrateV1toV2`.
@Model
final class DailyReadiness {
    /// Normalised to the start of the day (00:00:00) for consistent storage and queries.
    @Attribute(.unique) var date: Date
    var sleepHours: Double
    /// Average HRV of the past night in milliseconds.
    var hrv: Double
    /// The computed Vibe/Readiness Score, 0 (fully overtrained/exhausted) to 100 (optimal).
    var readinessScore: Int

    // Epic 21 Sprint 2 — sleep stages (iOS 16+ Apple Watch).
    // Value 0 = older device / Watch not worn → no penalty in ReadinessCalculator.
    var deepSleepMinutes: Int = 0
    var remSleepMinutes: Int  = 0
    var coreSleepMinutes: Int = 0
    /// Resting heart rate in beats per minute, straight from HealthKit. Nil if no data available.
    var restingHeartRate: Double?

    init(date: Date, sleepHours: Double, hrv: Double, readinessScore: Int,
         deepSleepMinutes: Int = 0, remSleepMinutes: Int = 0, coreSleepMinutes: Int = 0,
         restingHeartRate: Double? = nil) {
        self.date              = Calendar.current.startOfDay(for: date)
        self.sleepHours        = sleepHours
        self.hrv               = hrv
        self.readinessScore    = readinessScore
        self.deepSleepMinutes  = deepSleepMinutes
        self.remSleepMinutes   = remSleepMinutes
        self.coreSleepMinutes  = coreSleepMinutes
        self.restingHeartRate  = restingHeartRate
    }
}
