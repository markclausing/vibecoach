import Foundation

// MARK: - Epic #51-F6: Captive Portal Detector
//
// Pure-Swift helpers om twee soorten "schijnbaar online maar geblokkeerd"-
// situaties te herkennen:
//
//   1. **Reactief** (`isLikelyCaptivePortal(response:data:)`) — kijkt naar een
//      live API-response: als de content-type `text/html` is of de body met
//      `<!DOCTYPE`, `<html`, of een UTF-BOM-variant daarvan begint, terwijl
//      de caller JSON verwachtte, dan zit er bijna zeker een hotel-/airport-
//      portal of corporate-VPN-redirect tussen. We gooien een netwerk-fout
//      i.p.v. een misleidende decode-fout en zetten een flag voor de banner.
//
//   2. **Actief** (`isAppleProbeSuccess(data:response:)`) — Apple's
//      `captive.apple.com/hotspot-detect.html` retourneert exact
//      `<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>`
//      met HTTP 200 + `text/html`. Bij een captive-portal stuurt de portal
//      een eigen HTML- of redirect-pagina terug die deze marker mist.
//      Wordt geprobed door `CaptivePortalProbe` na elke offline → online-
//      transitie van `NetworkReachabilityMonitor`.
//
// AppStorage-vrij, side-effect-vrij. Caller bepaalt zelf wat met het
// resultaat te doen (banner zetten, error gooien, opnieuw proberen).

enum CaptivePortalDetector {

    /// HTTP-content-type-waarden die we als "geen JSON" beschouwen wanneer
    /// een endpoint expliciet JSON had moeten teruggeven.
    static let htmlContentTypes: Set<String> = [
        "text/html",
        "application/xhtml+xml"
    ]

    /// HTML/markup-prefixes na trimmen van whitespace en BOM-bytes.
    static let markupPrefixes: [String] = [
        "<!DOCTYPE",
        "<!doctype",
        "<HTML",
        "<html",
        "<?xml"
    ]

    /// Reactieve detectie: caller verwachtte JSON, server gaf HTML/markup
    /// terug. Returnt `true` wanneer dat patroon zichtbaar is.
    static func isLikelyCaptivePortal(response: HTTPURLResponse, data: Data) -> Bool {
        if let contentType = contentType(from: response) {
            for htmlType in htmlContentTypes {
                if contentType.hasPrefix(htmlType) {
                    return true
                }
            }
        }
        return startsWithMarkup(data)
    }

    /// Actieve probe: Apple's hotspot-detect-pagina retourneert HTTP 200
    /// + body bevat `Success`. Captive-portals hijacken de respons; herken
    /// daarom op de exacte success-marker, niet alleen op de statuscode.
    static let appleProbeURL = URL(string: "https://captive.apple.com/hotspot-detect.html")!
    static let appleProbeSuccessMarker = "Success"

    static func isAppleProbeSuccess(data: Data, response: HTTPURLResponse) -> Bool {
        guard response.statusCode == 200 else { return false }
        guard let body = String(data: data, encoding: .utf8) else { return false }
        // Apple's body is "<HTML><HEAD><TITLE>Success</TITLE>..."; ruim BOM
        // en whitespace op en check op het exacte token.
        return body.contains(appleProbeSuccessMarker)
    }

    // MARK: Private

    private static func contentType(from response: HTTPURLResponse) -> String? {
        // `HTTPURLResponse.mimeType` past al lowercase-normalisatie toe maar
        // strip soms de charset-suffix; voor zekerheid lezen we de raw header
        // direct én vergelijken case-insensitief.
        if let raw = response.value(forHTTPHeaderField: "Content-Type") {
            return raw.lowercased()
        }
        return response.mimeType?.lowercased()
    }

    private static func startsWithMarkup(_ data: Data) -> Bool {
        // Strip UTF-8/UTF-16 BOM voordat we de prefix-vergelijking doen —
        // sommige proxy-portals serveren HTML met een BOM die anders de
        // markup-detectie zou laten missen.
        let stripped = stripLeadingBOM(data)
        guard !stripped.isEmpty else { return false }

        // Beperkt sample-window — 64 bytes is genoeg voor een doctype/html-tag
        // zonder dat we bij grote responses de hele body in een String hoeven
        // te zetten.
        let prefixCount = min(stripped.count, 64)
        let prefixBytes = stripped.prefix(prefixCount)
        guard let prefix = String(data: prefixBytes, encoding: .utf8) else {
            return false
        }
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        for markup in markupPrefixes {
            if trimmed.hasPrefix(markup) {
                return true
            }
        }
        return false
    }

    private static func stripLeadingBOM(_ data: Data) -> Data {
        // UTF-8 BOM: EF BB BF.
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            return data.subdata(in: 3..<data.count)
        }
        return data
    }
}
