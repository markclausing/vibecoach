import SwiftUI
import SafariServices

/// In-app browser (`SFSafariViewController`) for external links — for example the
/// "how do I get a key" pages per AI provider. More reliable than a plain SwiftUI
/// `Link` (which opens the external Safari app and sometimes shows a blank page on
/// a cold start) and keeps the user inside the app.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// `Identifiable` wrapper so a `URL` can be presented via `.sheet(item:)`
/// (the presentation state holds the URL to open).
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}
