import Foundation
import SwiftData

/// Represents a stored long-term preference or 'hard rule' of the user.
@Model
final class UserPreference {
    @Attribute(.unique) var id: UUID
    var preferenceText: String
    var createdAt: Date
    var isActive: Bool
    var expirationDate: Date?

    init(id: UUID = UUID(), preferenceText: String, createdAt: Date = Date(), isActive: Bool = true, expirationDate: Date? = nil) {
        self.id = id
        self.preferenceText = preferenceText
        self.createdAt = createdAt
        self.isActive = isActive
        self.expirationDate = expirationDate
    }
}
