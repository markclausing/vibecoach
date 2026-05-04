import Foundation
import SwiftData

// MARK: - SchemaV2: huidige (live) staat (na tech-debt-audit, mei 2026)
//
// Dit schema refereert direct de live runtime-types (Models/Symptom.swift etc.) — er zijn
// geen aparte V2-class-definities want we willen niet alle global types opnieuw declareren.
// SwiftData onderscheidt V1 en V2 op `versionIdentifier`, niet op type-namespace.

enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

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
