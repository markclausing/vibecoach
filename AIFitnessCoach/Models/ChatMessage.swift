import Foundation
import SwiftUI

/// Represents the sender of a chat message in the application.
enum SenderRole: String, Codable {
    case user // The end user
    case ai   // The virtual AI coach
}

/// Represents an individual chat message (both incoming and outgoing).
/// Includes optional support for image data (e.g. charts/photos).
struct ChatMessage: Identifiable, Equatable {
    /// The unique identifier of this message, crucial for SwiftUI iteration.
    let id: UUID
    /// The sender: AI or user.
    let role: SenderRole
    /// The textual content of the message.
    let text: String
    /// The moment the message was created.
    let timestamp: Date
    /// Optional raw JPEG data of an attached image.
    let attachedImageData: Data?

    /// Sprint 8.2: an optional suggested training plan that comes from the structured JSON.
    let suggestedPlan: SuggestedTrainingPlan?

    /// Indicates whether this message is a recoverable error (e.g. a server timeout).
    /// If true, the MessageBubble shows a 'Try again' button.
    let isError: Bool

    /// Creates a new `ChatMessage` object.
    ///
    /// - Parameters:
    ///   - id: Unique identifier, generated with `UUID()` by default.
    ///   - role: Determines whether this is a `.user` or `.ai` message.
    ///   - text: The text of the message.
    ///   - timestamp: The moment it was sent.
    ///   - attachedImageData: Optional bytes of a compressed JPEG image.
    ///   - suggestedPlan: A dynamically generated calendar in JSON.
    ///   - isError: Whether this is a recoverable error. Defaults to false.
    init(id: UUID = UUID(), role: SenderRole, text: String, timestamp: Date = Date(), attachedImageData: Data? = nil, suggestedPlan: SuggestedTrainingPlan? = nil, isError: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.attachedImageData = attachedImageData
        self.suggestedPlan = suggestedPlan
        self.isError = isError
    }
}
