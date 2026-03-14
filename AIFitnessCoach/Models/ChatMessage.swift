import Foundation
import SwiftUI

/// Representeert de rol van de verzender
enum SenderRole: String, Codable {
    case user
    case ai
}

/// Representeert een chatbericht
struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: SenderRole
    let text: String
    let timestamp: Date
    let attachedImageData: Data?

    init(id: UUID = UUID(), role: SenderRole, text: String, timestamp: Date = Date(), attachedImageData: Data? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.attachedImageData = attachedImageData
    }
}
