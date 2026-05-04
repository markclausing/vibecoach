import Foundation
import SwiftData

// MARK: - Epic 32: Time-Series Workout Samples

/// Eén tijdpunt van fysiologische data tijdens een workout, op een vaste 5s-resolutie.
/// Workouts zelf worden niet in SwiftData gepersisteerd — `workoutUUID` koppelt deze sample
/// aan de bron-`HKWorkout.uuid` (Route A: foreign key, geen redundant Workout-model).
///
/// **Schema V2 wijzigingen:**
/// - `#Unique<>([\.workoutUUID, \.timestamp])` toegevoegd — voorheen vertrouwde de
///   `WorkoutSampleService` op idempotente upsert via die combo zonder DB-zijdige garantie.
/// - `@Attribute(.indexed)` op `workoutUUID` voor snellere `@Predicate`-filters per workout.
/// Bestaande duplicates worden gededupeerd in `AppMigrationPlan.willMigrateV1toV2`.
@Model
final class WorkoutSample {
    #Unique<WorkoutSample>([\.workoutUUID, \.timestamp])
    #Index<WorkoutSample>([\.workoutUUID])

    /// Verwijzing naar `HKWorkout.uuid`. Snelle lookup per workout via `@Predicate`-filter.
    var workoutUUID: UUID
    /// Begin van het 5s-bucket waarvoor deze sample geldt.
    var timestamp: Date

    /// Hartslag in slagen per minuut (gemiddelde over het bucket).
    var heartRate: Double?
    /// Snelheid in m/s (lineair geïnterpoleerd op het bucket-grenspunt).
    var speed: Double?
    /// Vermogen in watt (gemiddelde over het bucket).
    var power: Double?
    /// Cadans in stappen of omwentelingen per minuut (gemiddelde over het bucket).
    var cadence: Double?
    /// Cumulatieve afstand-delta over het bucket in meters.
    var distance: Double?

    init(workoutUUID: UUID,
         timestamp: Date,
         heartRate: Double? = nil,
         speed: Double? = nil,
         power: Double? = nil,
         cadence: Double? = nil,
         distance: Double? = nil) {
        self.workoutUUID = workoutUUID
        self.timestamp = timestamp
        self.heartRate = heartRate
        self.speed = speed
        self.power = power
        self.cadence = cadence
        self.distance = distance
    }
}
