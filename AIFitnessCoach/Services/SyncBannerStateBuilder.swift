import Foundation

// MARK: - Epic #51-F1/F2/F5/F6: Sync-banner-state-builder
//
// Pure functie die op basis van een `SyncStatusSnapshot` bepaalt welke banner
// moet worden getoond. Eén banner tegelijk volgens deze prioriteit:
//   1. **offline** — `isOffline == true`  (wint van alles, want zonder
//      verbinding zijn alle sub-fouten irrelevant)
//   2. **captive-portal** — `isCaptivePortal == true` (F6 — netwerk lijkt
//      open maar wordt actief geblokkeerd door portal of VPN-redirect)
//   3. **rate-limit** — `stravaRateLimitedUntil > now`
//   4. **error** — meest recente niet-rate-limit-fout op Strava of HK
//   5. **nil** — geen banner
//
// AppStorage-vrij, side-effect-vrij, deterministisch. Tests verifiëren elke
// prioriteit-grens zodat we niet in productie ontdekken dat een rate-limit
// banner blijft staan terwijl de gebruiker offline is gegaan.

enum SyncBannerState: Equatable {
    case offline(lastSyncAt: Date?)
    case captivePortal(lastSyncAt: Date?)
    case rateLimited(until: Date)
    case stravaError(SyncErrorCategory)
    case healthKitError(SyncErrorCategory)
}

enum SyncBannerStateBuilder {

    /// Berekent de banner-staat voor het huidige moment. Geeft `nil` terug
    /// wanneer er niets te tonen is.
    /// - Parameters:
    ///   - snapshot: gefotografeerde sync-status van de `SyncStatusStore`.
    ///   - now: huidig tijdstip — injecteerbaar voor deterministische tests.
    static func state(from snapshot: SyncStatusSnapshot,
                      now: Date = Date()) -> SyncBannerState? {
        if snapshot.isOffline {
            return .offline(lastSyncAt: snapshot.lastAnySyncSuccessAt)
        }

        if snapshot.isCaptivePortal {
            return .captivePortal(lastSyncAt: snapshot.lastAnySyncSuccessAt)
        }

        if let until = snapshot.stravaRateLimitedUntil, until > now {
            return .rateLimited(until: until)
        }

        // Pak de meest recente fout — een oudere HK-fout mag een verse
        // Strava-fout niet overschrijven en vice versa. `.rateLimit` is hier
        // niet relevant (de cooldown is verlopen of er was geen 429), dus de
        // bijbehorende error-category-entry kan blijven staan — we vegen 'm
        // mee wanneer een succesvolle sync de error-velden wist.
        let stravaCandidate = nonRateLimitError(
            category: snapshot.lastStravaError,
            at: snapshot.lastStravaErrorAt
        )
        let hkCandidate = nonRateLimitError(
            category: snapshot.lastHKError,
            at: snapshot.lastHKErrorAt
        )

        switch (stravaCandidate, hkCandidate) {
        case (nil, nil):
            return nil
        case let (s?, nil):
            return .stravaError(s.category)
        case let (nil, h?):
            return .healthKitError(h.category)
        case let (s?, h?):
            return s.at >= h.at ? .stravaError(s.category) : .healthKitError(h.category)
        }
    }

    // MARK: Private

    private struct ErrorCandidate {
        let category: SyncErrorCategory
        let at: Date
    }

    private static func nonRateLimitError(category: SyncErrorCategory?,
                                          at date: Date?) -> ErrorCandidate? {
        guard let category, category != .rateLimit, let date else { return nil }
        return ErrorCandidate(category: category, at: date)
    }
}
