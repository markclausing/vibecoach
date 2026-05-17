import Foundation

/// Epic #51-A4: bewaakt de chat-invoer tegen plak-acties die de Gemini-prompt
/// laten doorslaan in 45s-timeouts of safety-blocks. De pre-#51-implementatie
/// had geen limiet en geen visuele feedback — een gebruiker die een PDF-quote
/// in de input plakte, kreeg pas na drie minuten een vage foutmelding terug.
///
/// Pure-Swift zodat clamp- en counter-logica los testbaar is van SwiftUI.
enum ChatInputValidator {

    /// Maximum aantal tekens dat de coach in één turn accepteert. 5000 chars
    /// komt grofweg overeen met ~1200 tokens — ruim genoeg voor een uitgebreide
    /// reflectie, ruim onder het Gemini-input-window, en geeft de prompt nog
    /// kop-en-staart-ruimte voor onze context-prefix.
    static let maxLength = 5000

    /// Drempel waarboven we de char-counter onder het invoerveld tonen. 80%
    /// van het maximum: de counter verschijnt pas wanneer de gebruiker in de
    /// gevarenzone komt; bij normaal typen blijft de UI rustig.
    static let counterThreshold = 4000

    /// Clamp-resultaat dat caller informatie geeft over wat er gebeurd is —
    /// `didClamp == true` betekent dat de input afgekapt is en een korte toast
    /// gerechtvaardigd is.
    struct ClampResult: Equatable {
        let clamped: String
        let didClamp: Bool
    }

    /// Kapt `text` af op `limit` tekens. Geeft `didClamp = true` terug zodra
    /// er daadwerkelijk iets is afgesneden, zodat de UI eenmalig een toast
    /// kan tonen.
    static func clamp(_ text: String, limit: Int = maxLength) -> ClampResult {
        guard limit >= 0 else { return ClampResult(clamped: "", didClamp: !text.isEmpty) }
        if text.count <= limit {
            return ClampResult(clamped: text, didClamp: false)
        }
        let clamped = String(text.prefix(limit))
        return ClampResult(clamped: clamped, didClamp: true)
    }

    /// Bepaalt of de visuele counter zichtbaar moet zijn. Caller (ChatView)
    /// rendert hem onder de TextField als deze functie `true` retourneert.
    static func shouldShowCounter(_ text: String, threshold: Int = counterThreshold) -> Bool {
        text.count >= threshold
    }
}
