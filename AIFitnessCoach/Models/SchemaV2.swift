import Foundation
import SwiftData

// MARK: - SchemaV2: snapshot before Epic #49 (May 2026)
//
// Previously this schema referenced the live runtime types directly. That worked as long
// as no further changes came after V2. With Epic #49 (weather metadata on
// `ActivityRecord`) that shortcut turned out to be a data-loss risk: as soon as the live
// class changes, the V2 checksum changes too, and SwiftData can then no longer
// distinguish whether the store is really V2 or a later version. Result: init
// failure → fallback wipes the DB.
//
// Since Epic #49, V2 therefore has its own `ActivityRecord` snapshot (5 fields,
// before the weather addition). The other V2 types still reference the live ones — those
// have not changed since V2. The convention follows SchemaV1: nested types keep
// the same unqualified name as the live version so the SwiftData entity name
// matches ("ActivityRecord", not "V2ActivityRecord").

enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Symptom.self,
         DailyReadiness.self,
         WorkoutSample.self,
         SchemaV4.FitnessGoal.self,
         Self.ActivityRecord.self,
         UserPreference.self,
         UserConfiguration.self]
    }

    /// V2 snapshot of `ActivityRecord` without the Epic #49 weather fields.
    /// Read by SwiftData to determine what is in a V2 store
    /// before the lightweight V2 → V3 migration (which adds `temperatureCelsius` +
    /// `humidityPercent` as new optional columns).
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

        init(id: String, name: String, distance: Double, movingTime: Int,
             averageHeartrate: Double?, sportCategory: SportCategory, startDate: Date,
             trimp: Double? = nil, rpe: Int? = nil, mood: String? = nil,
             sessionType: SessionType? = nil, deviceWatts: Bool? = nil,
             manualSessionTypeOverride: Bool? = nil) {
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
        }
    }
}
