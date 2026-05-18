import Foundation

/// Epic #51-A3: splitst een chat-message-array in een zichtbaar deel en een
/// archief-deel zodra het gesprek voorbij `visibleLimit` berichten gaat.
/// Voorkomt UI-bloat bij lange gesprekken (ChatView toont alleen de zichtbare
/// staart; het archief klapt de gebruiker desgewenst zelf uit).
///
/// De huidige `ChatViewModel.fetchAIResponse` stuurt geen message-history mee
/// naar Gemini — elke turn is een one-shot call met alleen de context-prefix.
/// Daardoor heeft trimmen géén invloed op het AI-geheugen; het is puur een
/// UI/geheugen-optimalisatie. Wis-acties zijn niet destructief: het archief
/// blijft in het ChatViewModel staan en is een tap verder.
///
/// Pure-Swift zodat de trim-logica los testbaar is van SwiftUI/SwiftData.
enum ChatConversationTrimmer {

    /// Drempel waarboven oudere berichten standaard naar het archief verschuiven.
    /// 50 is gekozen omdat de acceptance-criteria expliciet "50 berichten breken
    /// de coach niet" noemt — daarmee blijft het hele recente gesprek in beeld
    /// en valt pas archivering in bij echt zeer lange sessies.
    static let defaultVisibleLimit = 50

    /// Splitst `messages` in twee arrays: alle berichten die buiten beeld klappen
    /// (`archived`) en de berichten die direct zichtbaar blijven (`visible`).
    /// Volgorde van de array wordt behouden — `archived` bevat de oudste,
    /// `visible` de meest recente `visibleLimit` berichten.
    ///
    /// Generic over `Element` zodat de helper niets weet over `ChatMessage` zelf
    /// — daardoor compileert hij in unit-tests zonder de SwiftData/SwiftUI-keten
    /// die `ChatMessage` met zich meebrengt.
    static func split<Element>(messages: [Element],
                               visibleLimit: Int = defaultVisibleLimit) -> (archived: [Element], visible: [Element]) {
        guard visibleLimit > 0 else { return (messages, []) }
        guard messages.count > visibleLimit else { return ([], messages) }

        let archivedCount = messages.count - visibleLimit
        let archived = Array(messages.prefix(archivedCount))
        let visible = Array(messages.suffix(visibleLimit))
        return (archived, visible)
    }
}
