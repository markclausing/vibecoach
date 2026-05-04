import Foundation
import SwiftData

/// Slaat de dagelijkse Readiness Score op, berekend op basis van slaap en HRV (Epic 14).
/// Er wordt maximaal één record per dag bewaard — upsert via de ReadinessService.
///
/// **Schema V2 wijziging:** `@Attribute(.unique)` op `date` toegevoegd zodat de "max 1 per dag"-
/// invariant ook DB-zijdig wordt afgedwongen (voorheen alleen via service-laag upsert, race-
/// gevoelig). Bestaande duplicates worden gededupeerd in `AppMigrationPlan.willMigrateV1toV2`.
@Model
final class DailyReadiness {
    /// Genormaliseerd naar het begin van de dag (00:00:00) voor consistente opslag en queries.
    @Attribute(.unique) var date: Date
    var sleepHours: Double
    /// Gemiddelde HRV van de afgelopen nacht in milliseconden.
    var hrv: Double
    /// De berekende Vibe/Readiness Score, 0 (volledig overtraind/uitgeput) t/m 100 (optimaal).
    var readinessScore: Int

    // Epic 21 Sprint 2 — Slaapfases (iOS 16+ Apple Watch).
    // Waarde 0 = ouder device / Watch niet gedragen → geen strafpunt in ReadinessCalculator.
    var deepSleepMinutes: Int = 0
    var remSleepMinutes: Int  = 0
    var coreSleepMinutes: Int = 0
    /// Rusthartslag in slagen per minuut, direct vanuit HealthKit. Nil als geen data beschikbaar.
    var restingHeartRate: Double? = nil

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
