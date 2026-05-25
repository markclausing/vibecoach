import Foundation
import SwiftData

// MARK: - SchemaV3: huidige (live) staat — Epic #49 weather-metadata
//
// Verschil met SchemaV2: `ActivityRecord` heeft twee nieuwe optionele velden,
// `temperatureCelsius: Double?` en `humidityPercent: Double?` (gevuld vanuit
// `HKMetadataKeyWeatherTemperature` / `HKMetadataKeyWeatherHumidity`). Pure
// addition, dus de migratie-stage is `.lightweight` (V2 → V3).
//
// **Waarom toch een schema-versie-bump voor pure additions?** Onze app geeft
// een explicit `migrationPlan: AppMigrationPlan.self` mee aan `ModelContainer`
// en niet `nil`. SwiftData's lightweight inference werkt anders bij een
// explicit plan: zodra de schema-hash van de live `@Model`-class verandert
// zonder bijbehorende `VersionedSchema` om naar te migreren, faalt de init.
// In `AIFitnessCoachApp.makeModelContainer()` valt dat in de fallback-tak
// die de SQLite-store wist — `FitnessGoal` + `UserPreference` + `Symptom`
// zijn dan kwijt. Mei 2026 incident: Epic #49-build wiste lokale doelen
// omdat we de schema-bump oversloegen. Sindsdien: élke `@Model`-wijziging
// vereist een schema-versie-bump (zie CLAUDE.md §2.1).
//
// **Epic #52 update (V4-introductie):** voorheen refereerde SchemaV3 direct de
// live `ActivityRecord`-class. Dat werkte zolang er na V3 geen verdere wijziging
// kwam. Bij Epic #52 (GPS-coords) krijgt de live class twee nieuwe velden — als
// SchemaV3 nog naar de live class blijft wijzen, krijgt V3 een V4-checksum en
// gaat de migratie-keten stuk. Daarom heeft V3 sinds Epic #52 een eigen
// `ActivityRecord`-snapshot (V3-shape, mét weather-velden maar zonder coords).
// Andere V3-types zijn sinds V3 niet gewijzigd en verwijzen nog naar live.

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

    /// V3-snapshot van `ActivityRecord` — bevat de Epic-#49-weather-velden maar
    /// nog géén Epic-#52-coords. Wordt door SwiftData gelezen om te bepalen wat
    /// er in een V3-store staat vóór de lightweight V3 → V4 migratie (die
    /// `startLatitude` + `startLongitude` als nieuwe optionele kolommen toevoegt).
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
