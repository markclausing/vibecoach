import Foundation
import SwiftUI

/// Representeert de afzender van het chatbericht in de applicatie.
enum SenderRole: String, Codable {
    case user // De eindgebruiker
    case ai   // De virtuele AI coach
}

/// Representeert een individueel chatbericht (zowel inkomend als uitgaand).
/// Bevat optionele ondersteuning voor beelddata (bijv. grafieken/foto's).
struct ChatMessage: Identifiable, Equatable {
    /// De unieke identificatiecode van dit bericht, cruciaal voor SwiftUI iteratie.
    let id: UUID
    /// De afzender: AI of gebruiker.
    let role: SenderRole
    /// De tekstuele inhoud van het bericht.
    let text: String
    /// Het tijdstip waarop het bericht is aangemaakt.
    let timestamp: Date
    /// Optionele ruwe JPEG data van een bijgevoegde afbeelding.
    let attachedImageData: Data?

    /// Sprint 8.2: Een optioneel voorgesteld trainingsplan dat uit de gestructureerde JSON komt.
    let suggestedPlan: SuggestedTrainingPlan?

    /// Creëert een nieuw `ChatMessage` object.
    ///
    /// - Parameters:
    ///   - id: Unieke identifier, standaard gegenereerd met `UUID()`.
    ///   - role: Bepaalt of dit een `.user` of `.ai` bericht is.
    ///   - text: De tekst van het bericht.
    ///   - timestamp: Het verzendmoment.
    ///   - attachedImageData: Optionele bytes van een gecomprimeerde JPEG afbeelding.
    ///   - suggestedPlan: Een dynamisch gegenereerde kalender in JSON.
    init(id: UUID = UUID(), role: SenderRole, text: String, timestamp: Date = Date(), attachedImageData: Data? = nil, suggestedPlan: SuggestedTrainingPlan? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.attachedImageData = attachedImageData
        self.suggestedPlan = suggestedPlan
    }
}
