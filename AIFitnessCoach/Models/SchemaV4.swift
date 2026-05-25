import Foundation
import SwiftData

// MARK: - SchemaV4: Epic #52 — GPS-start-coördinaten op ActivityRecord
//
// Verschil met SchemaV3: `ActivityRecord` krijgt twee nieuwe optionele velden,
// `startLatitude: Double?` en `startLongitude: Double?`. Pure addition, dus
// `MigrationStage.lightweight(fromVersion: V3, toVersion: V4)` is voldoende.
// Bestaande records krijgen `nil` op beide velden — voor records zónder coords
// blijft de Coach-analyse terugvallen op de snapshot in `temperatureCelsius`/
// `humidityPercent`.
//
// **Waarom de bump?** Epic #52 voegt hourly weer-range (peak temp, avg humidity)
// over [start, end] toe aan de Coach-prompt. Voor de range-fetch hebben we GPS
// nodig; voorheen leefde lat/lng alleen op `StravaActivity` (niet @Model) en
// dus alleen tijdens ingest beschikbaar. Door de coords op `ActivityRecord` te
// persisteren kunnen we ze later — bij Coach-call op een willekeurige workout —
// hergebruiken zonder de bron-API te bevragen.
//
// Conform CLAUDE.md §2.1: élke `@Model`-wijziging vereist een schema-bump, óók
// pure additions. SwiftData's lightweight-inference werkt anders bij een
// explicit `migrationPlan` — zonder versie-bump ziet de container een hash-
// mismatch op V3 en valt terug op fresh-DB (data-loss).
//
// Net als V3 refereert deze direct de live runtime-types — geen aparte
// V4-class-definities nodig voor pure addition.

enum SchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Symptom.self,
         DailyReadiness.self,
         WorkoutSample.self,
         FitnessGoal.self,
         ActivityRecord.self,
         UserPreference.self,
         UserConfiguration.self]
    }
}
