import Foundation
import SwiftData

// MARK: - SchemaV4: Epic #52 — GPS start coordinates on ActivityRecord
//
// Difference from SchemaV3: `ActivityRecord` gets two new optional fields,
// `startLatitude: Double?` and `startLongitude: Double?`. A pure addition, so
// `MigrationStage.lightweight(fromVersion: V3, toVersion: V4)` is sufficient.
//
// **Epic #55 update (V5 introduction):** previously SchemaV4 referenced the live
// `FitnessGoal` class directly. That worked as long as no further change came after
// V4. With Epic #55 (`eventDurationDays`) the live class gets a new field — if
// SchemaV4 keeps pointing at the live class, V4 gets a V5 checksum (CoreData then
// rejects the plan with "Duplicate version checksums detected"). That is why, since
// Epic #55, V4 has its own `FitnessGoal` snapshot (V4 shape, without
// `eventDurationDays`). `ActivityRecord` is still current as of V4/V5, so it keeps
// referencing the live type.
//
// Per CLAUDE.md §2.1: every `@Model` change requires a schema bump, including pure
// additions — without it the container falls back to a fresh DB (data loss).

enum SchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Symptom.self,
         DailyReadiness.self,
         WorkoutSample.self,
         Self.FitnessGoal.self,
         ActivityRecord.self,
         UserPreference.self,
         UserConfiguration.self]
    }

    /// V4 snapshot of `FitnessGoal` — the shape before Epic #55, i.e. without
    /// `eventDurationDays`. Read by SwiftData to determine what is in a V4 store
    /// before the lightweight V4 → V5 migration (which adds `eventDurationDays`
    /// as a new optional column). Keeps the unqualified name `FitnessGoal` so the
    /// SwiftData entity name matches the store.
    @Model
    final class FitnessGoal {
        @Attribute(.unique) var id: UUID
        var title: String
        var details: String?
        var targetDate: Date
        var createdAt: Date
        var isCompleted: Bool
        var sportCategory: SportCategory?
        var targetTRIMP: Double?
        var format: EventFormat?
        var intent: PrimaryIntent?
        var stretchGoalTime: TimeInterval?

        init(id: UUID = UUID(), title: String, details: String? = nil, targetDate: Date,
             createdAt: Date = Date(), isCompleted: Bool = false,
             sportCategory: SportCategory? = nil, targetTRIMP: Double? = nil,
             format: EventFormat? = .singleDayRace, intent: PrimaryIntent? = .peakPerformance,
             stretchGoalTime: TimeInterval? = nil) {
            self.id = id
            self.title = title
            self.details = details
            self.targetDate = targetDate
            self.createdAt = createdAt
            self.isCompleted = isCompleted
            self.sportCategory = sportCategory
            self.targetTRIMP = targetTRIMP
            self.format = format
            self.intent = intent
            self.stretchGoalTime = stretchGoalTime
        }
    }
}
