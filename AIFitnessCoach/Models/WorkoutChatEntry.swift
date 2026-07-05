import Foundation
import SwiftData

// MARK: - Epic #70: Per-workout chat with local memory

/// One persisted message in the per-workout chat thread ("Discuss this workout").
///
/// Unlike the main Coach tab (whose `ChatMessage` structs are session-only), the
/// workout chat is stored so the conversation is re-readable whenever the user
/// reopens the workout detail page.
///
/// `activityID` is keyed **by value** to `ActivityRecord.id` (String) — deliberately
/// not a SwiftData relationship: activities are re-syncable from HealthKit/Strava
/// while this chat is local-only, so a hard link would couple two lifecycles that
/// differ (a re-synced activity keeps its source id, and the thread reattaches
/// automatically).
@Model
final class WorkoutChatEntry {
    @Attribute(.unique) var id: UUID
    /// `ActivityRecord.id` of the workout this message belongs to.
    var activityID: String
    /// Reuses the main chat's `SenderRole` (`String, Codable`) — .user or .ai.
    var role: SenderRole
    var text: String
    var timestamp: Date

    init(id: UUID = UUID(),
         activityID: String,
         role: SenderRole,
         text: String,
         timestamp: Date = Date()) {
        self.id = id
        self.activityID = activityID
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}
