import Foundation
import SwiftData

// MARK: - Epic #70: Per-workout chat with local memory

/// Category of a distilled workout fact. Type-safe per CLAUDE.md §2 — the raw
/// category string from the model response is mapped to this enum at the front
/// door (`WorkoutChatResponseParser`); unknown categories are dropped there.
enum WorkoutFactCategory: String, Codable, CaseIterable {
    /// How the workout felt relative to its load (e.g. "felt heavy despite low TRIMP").
    case feel
    /// Route/course/conditions feedback (e.g. "loved the loop around the lake").
    case route
    /// The user's condition that day/week explaining a deviation (e.g. "bad night's sleep").
    case dayCondition
}

/// One durable, plan-relevant fact the coach distilled from the per-workout chat.
///
/// Facts are the "memory" half of the hybrid design: the thread (`WorkoutChatEntry`)
/// is the archive, facts are the compact context that flows into coach plans and
/// feedback via `WorkoutFactsContextFormatter`. Facts are hard-deleted — the chip's
/// ✕ on the workout detail page is the single management surface.
@Model
final class WorkoutChatFact {
    @Attribute(.unique) var id: UUID
    /// `ActivityRecord.id` of the workout this fact was distilled from (by value,
    /// same convention and rationale as `WorkoutChatEntry.activityID`).
    var activityID: String
    var factText: String
    var category: WorkoutFactCategory
    var createdAt: Date

    init(id: UUID = UUID(),
         activityID: String,
         factText: String,
         category: WorkoutFactCategory,
         createdAt: Date = Date()) {
        self.id = id
        self.activityID = activityID
        self.factText = factText
        self.category = category
        self.createdAt = createdAt
    }
}
