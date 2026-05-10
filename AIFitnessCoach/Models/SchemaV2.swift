import Foundation
import SwiftData

// MARK: - SchemaV2: snapshot vóór Epic #49 (mei 2026)
//
// Voorheen refereerde dit schema direct de live runtime-types. Dat werkte zolang
// er na V2 geen verdere wijzigingen kwamen. Bij Epic #49 (weather-metadata op
// `ActivityRecord`) bleek die kortere weg een data-loss-risico: zodra de live
// class verandert, verandert ook de V2-checksum, en SwiftData kan dan niet
// onderscheiden of de store écht V2 of een latere versie is. Resultaat: init-
// failure → fallback wist DB.
//
// Sinds Epic #49 heeft V2 daarom een eigen `ActivityRecord`-snapshot (5 velden,
// vóór de weather-additie). De andere V2-types verwijzen nog naar live — die
// zijn sinds V2 niet gewijzigd. Conventie volgt SchemaV1: nested types houden
// dezelfde unqualified naam als de live versie zodat de SwiftData entity-naam
// matcht ("ActivityRecord", niet "V2ActivityRecord").

enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Symptom.self,
         DailyReadiness.self,
         WorkoutSample.self,
         FitnessGoal.self,
         Self.ActivityRecord.self,
         UserPreference.self,
         UserConfiguration.self]
    }

    /// V2-snapshot van `ActivityRecord` zonder de Epic-#49-weather-velden.
    /// Wordt door SwiftData gelezen om te bepalen wat er in een V2-store staat
    /// vóór de lightweight V2 → V3 migratie (die `temperatureCelsius` +
    /// `humidityPercent` als nieuwe optionele kolommen toevoegt).
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
