import Foundation
import SwiftData

// MARK: - SchemaV7: Epic #70 — per-workout chat with local memory

// Difference from SchemaV6: adds `WorkoutChatEntry` (the persisted per-workout chat
// thread) and `WorkoutChatFact` (durable facts the coach distils from that chat).
// Two new @Models are a pure addition — `MigrationStage.lightweight` from V6 to V7
// is sufficient (SwiftData creates the new tables; no existing rows are touched).
//
// **Epic #73 update (V8 introduction):** previously SchemaV7 referenced the live
// `FitnessGoal` class directly. With Epic #73 (`racePriority`) the live class gets a
// new field — if SchemaV7 keeps pointing at the live class, V7 gets a V8 checksum and
// CoreData rejects the plan with "Duplicate version checksums detected". So, like the
// V4 snapshot before it, V7 now carries its own `FitnessGoal` snapshot (V7 shape: with
// `eventDurationDays`, without `racePriority`). V5 + V6 (identical FitnessGoal shape)
// point at this same snapshot — it is the most recent unchanged version (§2.1).
//
// Per CLAUDE.md §2.1: every @Model change requires a schema bump, including pure
// additions (the May 2026 incident proves lightweight inference is not enough).

enum SchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Symptom.self,
         DailyReadiness.self,
         WorkoutSample.self,
         Self.FitnessGoal.self,
         ActivityRecord.self,
         UserPreference.self,
         UserConfiguration.self,
         CoachContextCache.self,
         WorkoutChatEntry.self,
         WorkoutChatFact.self]
    }

    /// V7 snapshot of `FitnessGoal` — the shape before Epic #73, i.e. with
    /// `eventDurationDays` but without `racePriority`. Read by SwiftData to determine what
    /// is in a V5/V6/V7 store before the lightweight V7 → V8 migration (which adds
    /// `racePriority` as a new optional column). Keeps the unqualified name `FitnessGoal`
    /// so the SwiftData entity name matches the store.
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
        var eventDurationDays: Int?

        init(id: UUID = UUID(), title: String, details: String? = nil, targetDate: Date,
             createdAt: Date = Date(), isCompleted: Bool = false,
             sportCategory: SportCategory? = nil, targetTRIMP: Double? = nil,
             format: EventFormat? = .singleDayRace, intent: PrimaryIntent? = .peakPerformance,
             stretchGoalTime: TimeInterval? = nil, eventDurationDays: Int? = nil) {
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
            self.eventDurationDays = eventDurationDays
        }
    }
}
