import Foundation
import SwiftData

/// Representeert een opgeslagen langetermijnvoorkeur of 'harde regel' van de gebruiker.
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
