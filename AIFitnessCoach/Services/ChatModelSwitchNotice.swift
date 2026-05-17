import Foundation

/// Epic #51-A2: genereert de banner-tekst die boven de coach-chat verschijnt
/// wanneer de gebruiker in Settings van Gemini-model wisselt terwijl er nog
/// een antwoord onderweg is. Voorkomt verwarring over welk model het lopende
/// antwoord produceert en dat de volgende vraag automatisch het nieuwe model
/// gebruikt.
///
/// Pure-Swift zodat de tekst-logica los testbaar is van `ChatViewModel`
/// (geen AppStorage, geen MainActor, geen SDK-types).
enum ChatModelSwitchNotice {

    /// Geeft een banner-tekst terug wanneer de actief-gebruikte modelnamen
    /// (snapshot bij start van de huidige request) afwijken van de momenteel
    /// in AppStorage geconfigureerde modelnamen.
    ///
    /// - Returns: `nil` als er niets gewijzigd is — caller toont dan geen banner.
    static func message(activePrimary: String,
                        activeFallback: String,
                        configuredPrimary: String,
                        configuredFallback: String) -> String? {
        let primaryChanged = !activePrimary.isEmpty && activePrimary != configuredPrimary
        let fallbackChanged = !activeFallback.isEmpty && activeFallback != configuredFallback
        guard primaryChanged || fallbackChanged else { return nil }

        if primaryChanged {
            return "Modelwissel gedetecteerd — het huidige antwoord komt nog van \(activePrimary). Je volgende vraag gebruikt \(configuredPrimary)."
        }
        return "Fallback-model gewijzigd — het huidige antwoord gebruikt nog \(activeFallback). Bij overbelasting valt de coach voortaan terug op \(configuredFallback)."
    }
}
