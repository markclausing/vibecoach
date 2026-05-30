import Foundation
import SwiftData

// MARK: - Epic 32: Time-Series Workout Samples

/// One point in time of physiological data during a workout, at a fixed 5s resolution.
/// Workouts themselves are not persisted in SwiftData — `workoutUUID` links this sample
/// to the source `HKWorkout.uuid` (Route A: foreign key, no redundant Workout model).
///
/// **Schema V2 changes:**
/// - `#Unique<>([\.workoutUUID, \.timestamp])` added — previously the
///   `WorkoutSampleService` relied on an idempotent upsert via that combo without a DB-side guarantee.
/// - `@Attribute(.indexed)` on `workoutUUID` for faster `@Predicate` filters per workout.
/// Existing duplicates are deduped in `AppMigrationPlan.willMigrateV1toV2`.
@Model
final class WorkoutSample {
    #Unique<WorkoutSample>([\.workoutUUID, \.timestamp])
    #Index<WorkoutSample>([\.workoutUUID])

    /// Reference to `HKWorkout.uuid`. Fast lookup per workout via a `@Predicate` filter.
    var workoutUUID: UUID
    /// Start of the 5s bucket this sample applies to.
    var timestamp: Date

    /// Heart rate in beats per minute (average over the bucket).
    var heartRate: Double?
    /// Speed in m/s (linearly interpolated at the bucket boundary).
    var speed: Double?
    /// Power in watts (average over the bucket).
    var power: Double?
    /// Cadence in steps or revolutions per minute (average over the bucket).
    var cadence: Double?
    /// Cumulative distance delta over the bucket in metres.
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
