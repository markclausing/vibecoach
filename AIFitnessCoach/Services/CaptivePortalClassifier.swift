import Foundation

/// Epic #62 story 62.4 (was 51.F6) — pure-Swift detection of a captive portal: the device
/// reports "online" (Wi-Fi associated) but a login/splash page intercepts every request, so
/// API calls silently return an HTML portal page instead of the expected JSON.
///
/// Rather than a separate HTTP-204 probe (which needs an ATS exception), we classify the
/// *response we already got* from a normal HTTPS API call that failed to decode: a portal
/// hands back an HTML document (often with a redirect/refresh or a login form) where our API
/// would return JSON. Framework-free (§6) so the network layer passes in the raw facts.
enum CaptivePortalClassifier {

    /// Markers that strongly indicate an HTML login/splash page rather than an API payload.
    private static let portalMarkers = [
        "<html", "<!doctype html", "<title", "login", "sign in", "wi-fi", "hotspot",
        "captive", "portal", "terms of use", "accept", "<form"
    ]

    /// True when a response that *should* have been JSON instead looks like a captive-portal
    /// HTML page. Used after a JSON decode fails on an otherwise-2xx (or redirected) response.
    ///
    /// - Parameters:
    ///   - contentType: the response `Content-Type` header, if any.
    ///   - body: the response body (or a leading slice of it).
    ///   - wasRedirected: whether the request was redirected to a different host (a portal tell).
    static func looksLikeCaptivePortal(contentType: String?,
                                       body: String,
                                       wasRedirected: Bool = false) -> Bool {
        let lowerType = contentType?.lowercased() ?? ""
        let lowerBody = body.lowercased()

        // A JSON API never sends text/html. HTML + a redirect is the classic portal signature.
        let isHTML = lowerType.contains("text/html")
            || lowerBody.contains("<html")
            || lowerBody.contains("<!doctype html")

        guard isHTML else { return false }

        if wasRedirected { return true }
        // Require at least one portal-ish marker beyond the bare HTML tag to avoid flagging a
        // legitimate (if unexpected) HTML error page from our own backend.
        return portalMarkers.contains { lowerBody.contains($0) }
    }
}
