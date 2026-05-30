import Foundation
import SwiftData

// MARK: - SchemaV3: current (live) state — Epic #49 weather metadata
//
// Difference from SchemaV2: `ActivityRecord` has two new optional fields,
// `temperatureCelsius: Double?` and `humidityPercent: Double?` (filled from
// `HKMetadataKeyWeatherTemperature` / `HKMetadataKeyWeatherHumidity`). A pure
// addition, so the migration stage is `.lightweight` (V2 → V3).
//
// **Why a schema version bump for pure additions anyway?** Our app passes an
// explicit `migrationPlan: AppMigrationPlan.self` to `ModelContainer`
// rather than `nil`. SwiftData's lightweight inference behaves differently with an
// explicit plan: as soon as the schema hash of the live `@Model` class changes
// without a corresponding `VersionedSchema` to migrate to, the init fails.
// In `AIFitnessCoachApp.makeModelContainer()` that lands in the fallback branch
// that wipes the SQLite store — `FitnessGoal` + `UserPreference` + `Symptom`
// are then lost. May 2026 incident: the Epic #49 build wiped local goals
// because we skipped the schema bump. Since then: every `@Model` change
// requires a schema version bump (see CLAUDE.md §2.1).
//
// **Epic #52 update (V4 introduction):** previously SchemaV3 referenced the
// live `ActivityRecord` class directly. That worked as long as no further change
// came after V3. With Epic #52 (GPS coords) the live class gets two new fields — if
// SchemaV3 keeps pointing at the live class, V3 gets a V4 checksum and
// the migration chain breaks. That is why, since Epic #52, V3 has its own
// `ActivityRecord` snapshot (V3 shape, with weather fields but without coords).
// Other V3 types have not changed since V3 and still reference the live types.

enum SchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Symptom.self,
         DailyReadiness.self,
         WorkoutSample.self,
         FitnessGoal.self,
         Self.ActivityRecord.self,
         UserPreference.self,
         UserConfiguration.self]
    }

    /// V3 snapshot of `ActivityRecord` — contains the Epic #49 weather fields but
    /// not yet the Epic #52 coords. Read by SwiftData to determine what
    /// is in a V3 store before the lightweight V3 → V4 migration (which
    /// adds `startLatitude` + `startLongitude` as new optional columns).
    @Model
    final class ActivityRecord {
        @Attribute(.unique)
        var id: String

        var name: String
        var distance: Double
        var movingTime: Int
        var averageHeartrate: Double?
        var sportCategory: SportCategory
        var startDate: Date

        var trimp: Double?
        var rpe: Int?
        var mood: String?
        var sessionType: SessionType?
        var deviceWatts: Bool?
        var manualSessionTypeOverride: Bool?

        var temperatureCelsius: Double?
        var humidityPercent: Double?

        init(id: String, name: String, distance: Double, movingTime: Int,
             averageHeartrate: Double?, sportCategory: SportCategory, startDate: Date,
             trimp: Double? = nil, rpe: Int? = nil, mood: String? = nil,
             sessionType: SessionType? = nil, deviceWatts: Bool? = nil,
             manualSessionTypeOverride: Bool? = nil,
             temperatureCelsius: Double? = nil, humidityPercent: Double? = nil) {
            self.id = id
            self.name = name
            self.distance = distance
            self.movingTime = movingTime
            self.averageHeartrate = averageHeartrate
            self.sportCategory = sportCategory
            self.startDate = startDate
            self.trimp = trimp
            self.rpe = rpe
            self.mood = mood
            self.sessionType = sessionType
            self.deviceWatts = deviceWatts
            self.manualSessionTypeOverride = manualSessionTypeOverride
            self.temperatureCelsius = temperatureCelsius
            self.humidityPercent = humidityPercent
        }
    }
}
