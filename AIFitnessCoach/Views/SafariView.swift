import SwiftUI
import SafariServices

/// In-app browser (`SFSafariViewController`) voor externe links — bijvoorbeeld de
/// "hoe kom ik aan een sleutel"-pagina's per AI-provider. Betrouwbaarder dan een
/// gewone SwiftUI `Link` (die de externe Safari-app opent en bij een koude start
/// soms een lege pagina toont) en houdt de gebruiker binnen de app.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// `Identifiable`-wrapper zodat een `URL` via `.sheet(item:)` gepresenteerd kan
/// worden (de presentatie-state houdt de te openen URL vast).
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}
