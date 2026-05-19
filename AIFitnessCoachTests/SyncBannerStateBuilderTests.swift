import XCTest
@testable import AIFitnessCoach

final class SyncBannerStateBuilderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_715_000_000)

    private func emptySnapshot() -> SyncStatusSnapshot {
        SyncStatusSnapshot(
            isOffline: false,
            isCaptivePortal: false,
            stravaRateLimitedUntil: nil,
            lastStravaError: nil,
            lastStravaErrorAt: nil,
            lastHKError: nil,
            lastHKErrorAt: nil,
            lastStravaSuccessAt: nil,
            lastHKSuccessAt: nil
        )
    }

    // MARK: Geen banner

    func testNoBannerWhenAllClear() {
        let snap = emptySnapshot()
        XCTAssertNil(SyncBannerStateBuilder.state(from: snap, now: now))
    }

    func testNoBannerWhenOnlyRateLimitIsExpired() {
        var snap = emptySnapshot()
        snap.stravaRateLimitedUntil = now.addingTimeInterval(-60)
        XCTAssertNil(SyncBannerStateBuilder.state(from: snap, now: now))
    }

    // MARK: Offline wint van alles

    func testOfflineOutranksRateLimit() {
        var snap = emptySnapshot()
        snap.isOffline = true
        snap.stravaRateLimitedUntil = now.addingTimeInterval(300)
        snap.lastStravaSuccessAt = now.addingTimeInterval(-3600)

        guard case .offline(let lastSyncAt) = SyncBannerStateBuilder.state(from: snap, now: now) else {
            return XCTFail("Verwachtte .offline")
        }
        XCTAssertEqual(lastSyncAt, now.addingTimeInterval(-3600))
    }

    func testOfflineOutranksErrors() {
        var snap = emptySnapshot()
        snap.isOffline = true
        snap.lastStravaError = .network
        snap.lastStravaErrorAt = now

        guard case .offline = SyncBannerStateBuilder.state(from: snap, now: now) else {
            return XCTFail("Verwachtte .offline")
        }
    }

    func testOfflineWithoutPriorSyncShowsNilTimestamp() {
        var snap = emptySnapshot()
        snap.isOffline = true

        guard case .offline(let last) = SyncBannerStateBuilder.state(from: snap, now: now) else {
            return XCTFail("Verwachtte .offline")
        }
        XCTAssertNil(last)
    }

    // MARK: Rate-limit

    func testRateLimitOutranksError() {
        var snap = emptySnapshot()
        snap.stravaRateLimitedUntil = now.addingTimeInterval(300)
        snap.lastStravaError = .network
        snap.lastStravaErrorAt = now

        guard case .rateLimited(let until) = SyncBannerStateBuilder.state(from: snap, now: now) else {
            return XCTFail("Verwachtte .rateLimited")
        }
        XCTAssertEqual(until, now.addingTimeInterval(300))
    }

    func testExpiredRateLimitFallsThroughToError() {
        var snap = emptySnapshot()
        snap.stravaRateLimitedUntil = now.addingTimeInterval(-60) // verlopen
        snap.lastStravaError = .network
        snap.lastStravaErrorAt = now

        guard case .stravaError(let cat) = SyncBannerStateBuilder.state(from: snap, now: now) else {
            return XCTFail("Verwachtte .stravaError")
        }
        XCTAssertEqual(cat, .network)
    }

    // MARK: Error-prioriteit

    func testStravaErrorShownWhenOnlyStravaFailed() {
        var snap = emptySnapshot()
        snap.lastStravaError = .authentication
        snap.lastStravaErrorAt = now

        guard case .stravaError(let cat) = SyncBannerStateBuilder.state(from: snap, now: now) else {
            return XCTFail("Verwachtte .stravaError")
        }
        XCTAssertEqual(cat, .authentication)
    }

    func testHKErrorShownWhenOnlyHKFailed() {
        var snap = emptySnapshot()
        snap.lastHKError = .other
        snap.lastHKErrorAt = now

        guard case .healthKitError(let cat) = SyncBannerStateBuilder.state(from: snap, now: now) else {
            return XCTFail("Verwachtte .healthKitError")
        }
        XCTAssertEqual(cat, .other)
    }

    func testMostRecentErrorWins_StravaNewer() {
        var snap = emptySnapshot()
        snap.lastStravaError = .network
        snap.lastStravaErrorAt = now
        snap.lastHKError = .other
        snap.lastHKErrorAt = now.addingTimeInterval(-60)

        guard case .stravaError = SyncBannerStateBuilder.state(from: snap, now: now) else {
            return XCTFail("Verwachtte verse Strava-fout")
        }
    }

    func testMostRecentErrorWins_HKNewer() {
        var snap = emptySnapshot()
        snap.lastStravaError = .network
        snap.lastStravaErrorAt = now.addingTimeInterval(-60)
        snap.lastHKError = .other
        snap.lastHKErrorAt = now

        guard case .healthKitError = SyncBannerStateBuilder.state(from: snap, now: now) else {
            return XCTFail("Verwachtte verse HK-fout")
        }
    }

    func testRateLimitCategoryInErrorFieldIsIgnored() {
        // De rate-limit-banner wordt al via `stravaRateLimitedUntil` aangestuurd.
        // Een achtergebleven `.rateLimit` in de error-category mag geen aparte
        // banner forceren wanneer de cooldown verlopen is.
        var snap = emptySnapshot()
        snap.lastStravaError = .rateLimit
        snap.lastStravaErrorAt = now
        XCTAssertNil(SyncBannerStateBuilder.state(from: snap, now: now))
    }

    // MARK: Captive portal (Epic #51-F6)

    func testCaptivePortalShownWhenFlagSet() {
        var snap = emptySnapshot()
        snap.isCaptivePortal = true
        snap.lastStravaSuccessAt = now.addingTimeInterval(-120)

        guard case .captivePortal(let last) = SyncBannerStateBuilder.state(from: snap, now: now) else {
            return XCTFail("Verwachtte .captivePortal")
        }
        XCTAssertEqual(last, now.addingTimeInterval(-120))
    }

    func testOfflineOutranksCaptivePortal() {
        // Bij echte offline-status is captive-portal niet relevant — wis-bare
        // staat zou anders flikkeren tussen banners als de NWPath wisselt.
        var snap = emptySnapshot()
        snap.isOffline = true
        snap.isCaptivePortal = true

        guard case .offline = SyncBannerStateBuilder.state(from: snap, now: now) else {
            return XCTFail("Verwachtte .offline")
        }
    }

    func testCaptivePortalOutranksRateLimit() {
        var snap = emptySnapshot()
        snap.isCaptivePortal = true
        snap.stravaRateLimitedUntil = now.addingTimeInterval(300)

        guard case .captivePortal = SyncBannerStateBuilder.state(from: snap, now: now) else {
            return XCTFail("Verwachtte .captivePortal")
        }
    }

    func testCaptivePortalOutranksErrors() {
        var snap = emptySnapshot()
        snap.isCaptivePortal = true
        snap.lastStravaError = .network
        snap.lastStravaErrorAt = now

        guard case .captivePortal = SyncBannerStateBuilder.state(from: snap, now: now) else {
            return XCTFail("Verwachtte .captivePortal")
        }
    }

    // MARK: lastAnySyncSuccessAt helper

    func testLastAnySyncSuccessReturnsMostRecent() {
        var snap = emptySnapshot()
        snap.lastStravaSuccessAt = now.addingTimeInterval(-600)
        snap.lastHKSuccessAt = now.addingTimeInterval(-300)
        XCTAssertEqual(snap.lastAnySyncSuccessAt, now.addingTimeInterval(-300))
    }

    func testLastAnySyncSuccessHandlesNils() {
        var snap = emptySnapshot()
        XCTAssertNil(snap.lastAnySyncSuccessAt)
        snap.lastStravaSuccessAt = now.addingTimeInterval(-100)
        XCTAssertEqual(snap.lastAnySyncSuccessAt, now.addingTimeInterval(-100))
    }
}
