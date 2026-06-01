import Foundation

// MARK: - Epic #51-F1/F2/F5: Sync-banner state builder
//
// Pure function that, based on a `SyncStatusSnapshot`, determines which banner
// should be shown. One banner at a time per this priority:
//   1. **offline** — `isOffline == true`  (beats everything, because without a
//      connection all sub-errors are irrelevant)
//   2. **rate-limit** — `stravaRateLimitedUntil > now`
//   3. **error** — most recent non-rate-limit error on Strava or HK
//   4. **nil** — no banner
//
// AppStorage-free, side-effect-free, deterministic. Tests verify each
// priority boundary so we don't discover in production that a rate-limit
// banner stays up while the user has gone offline.

enum SyncBannerState: Equatable {
    case offline(lastSyncAt: Date?)
    case rateLimited(until: Date)
    case stravaError(SyncErrorCategory)
    case healthKitError(SyncErrorCategory)
}

enum SyncBannerStateBuilder {

    /// Computes the banner state for the current moment. Returns `nil`
    /// when there is nothing to show.
    /// - Parameters:
    ///   - snapshot: snapshotted sync status from the `SyncStatusStore`.
    ///   - now: current time — injectable for deterministic tests.
    static func state(from snapshot: SyncStatusSnapshot,
                      now: Date = Date()) -> SyncBannerState? {
        if snapshot.isOffline {
            return .offline(lastSyncAt: snapshot.lastAnySyncSuccessAt)
        }

        if let until = snapshot.stravaRateLimitedUntil, until > now {
            return .rateLimited(until: until)
        }

        // Take the most recent error — an older HK error must not override a fresh
        // Strava error and vice versa. `.rateLimit` is not relevant here
        // (the cooldown has expired or there was no 429), so the
        // corresponding error-category entry may remain — we sweep it
        // away when a successful sync clears the error fields.
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
