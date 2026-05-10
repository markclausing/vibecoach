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
// Zoals SchemaV2 refereert deze ook direct de live runtime-types (geen
// aparte V3-class-definities) — pure addition, dus geen snapshot nodig.

enum SchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

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
