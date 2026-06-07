import Foundation

/// Epic #51-A2: generates the banner text shown above the coach chat
/// when the user switches model in Settings while a reply is still
/// in flight. Prevents confusion about which model produces the in-flight
/// reply and that the next question automatically uses the new model.
///
/// Pure-Swift so the text logic is testable independently of `ChatViewModel`
/// (no AppStorage, no MainActor, no SDK types).
enum ChatModelSwitchNotice {

    /// Returns banner text when the actively-used model names
    /// (snapshot at the start of the current request) differ from the currently
    /// configured model names in AppStorage.
    ///
    /// - Returns: `nil` if nothing changed — the caller then shows no banner.
    static func message(activePrimary: String,
                        activeFallback: String,
                        configuredPrimary: String,
                        configuredFallback: String) -> String? {
        let primaryChanged = !activePrimary.isEmpty && activePrimary != configuredPrimary
        let fallbackChanged = !activeFallback.isEmpty && activeFallback != configuredFallback
        guard primaryChanged || fallbackChanged else { return nil }

        // Epic #37 story 37.1c: banner shown in the UI, so resolve via the String Catalog. Model
        // names interpolate as %@ (data). EN/DE keep the word "fallback" (asserted by tests).
        if primaryChanged {
            return String(localized: "Modelwissel gedetecteerd — het huidige antwoord komt nog van \(activePrimary). Je volgende vraag gebruikt \(configuredPrimary).")
        }
        return String(localized: "Fallback-model gewijzigd — het huidige antwoord gebruikt nog \(activeFallback). Bij overbelasting valt de coach voortaan terug op \(configuredFallback).")
    }
}
