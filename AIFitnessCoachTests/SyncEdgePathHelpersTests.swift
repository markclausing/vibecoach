import XCTest
@testable import AIFitnessCoach

/// Epic #62 story 62.4 — captive-portal classification, weather retry policy, HK permission audit.
final class SyncEdgePathHelpersTests: XCTestCase {

    // MARK: - CaptivePortalClassifier

    func testJSONResponseIsNotCaptive() {
        XCTAssertFalse(CaptivePortalClassifier.looksLikeCaptivePortal(
            contentType: "application/json", body: #"{"daily":{"time":[]}}"#))
    }

    func testHTMLLoginPageIsCaptive() {
        let body = "<html><head><title>Sign in to Wi-Fi</title></head><body><form>...</form></body></html>"
        XCTAssertTrue(CaptivePortalClassifier.looksLikeCaptivePortal(contentType: "text/html", body: body))
    }

    func testHTMLContentTypeWithRedirectIsCaptive() {
        // Redirected to a portal host, even without obvious markers in this slice.
        XCTAssertTrue(CaptivePortalClassifier.looksLikeCaptivePortal(
            contentType: "text/html; charset=utf-8", body: "<html></html>", wasRedirected: true))
    }

    func testBareHTMLErrorPageWithoutMarkersIsNotCaptive() {
        // A plain HTML error from our own backend (no portal markers, no redirect) must not flag.
        XCTAssertFalse(CaptivePortalClassifier.looksLikeCaptivePortal(
            contentType: "text/html", body: "<html><body>502 Bad Gateway</body></html>"))
    }

    func testDetectsHTMLEvenWhenContentTypeMissing() {
        let body = "<!DOCTYPE html><html><body>Please accept the terms of use to continue</body></html>"
        XCTAssertTrue(CaptivePortalClassifier.looksLikeCaptivePortal(contentType: nil, body: body))
    }

    // MARK: - WeatherRetryPolicy

    func testRetryAllowedWithNoPriorFailure() {
        XCTAssertTrue(WeatherRetryPolicy.shouldRetry(lastFailureAt: nil))
    }

    func testRetryBlockedWithinCooldown() {
        let now = Date()
        let recent = now.addingTimeInterval(-60) // 1 min ago, cooldown is 5 min
        XCTAssertFalse(WeatherRetryPolicy.shouldRetry(lastFailureAt: recent, now: now))
    }

    func testRetryAllowedAfterCooldown() {
        let now = Date()
        let old = now.addingTimeInterval(-(WeatherRetryPolicy.retryCooldown + 1))
        XCTAssertTrue(WeatherRetryPolicy.shouldRetry(lastFailureAt: old, now: now))
    }

    func testSecondsUntilRetryCountsDown() {
        let now = Date()
        let recent = now.addingTimeInterval(-120) // 2 min ago
        let remaining = WeatherRetryPolicy.secondsUntilRetry(lastFailureAt: recent, now: now)
        XCTAssertEqual(remaining, WeatherRetryPolicy.retryCooldown - 120, accuracy: 0.5)
    }

    func testSecondsUntilRetryZeroWhenAllowed() {
        XCTAssertEqual(WeatherRetryPolicy.secondsUntilRetry(lastFailureAt: nil), 0)
    }

    // MARK: - HealthKitPermissionAudit

    func testNoMissingSignalsNoDegradedFeatures() {
        XCTAssertTrue(HealthKitPermissionAudit.degradedFeatures(missing: []).isEmpty)
    }

    func testMissingHRVDegradesVibeScore() {
        XCTAssertEqual(HealthKitPermissionAudit.degradedFeatures(missing: [.hrv]), [.vibeScore])
    }

    func testMissingWorkoutsDegradesSchedule() {
        XCTAssertEqual(HealthKitPermissionAudit.degradedFeatures(missing: [.workouts]), [.schedule])
    }

    func testMultipleMissingSignalsMapToMultipleFeatures() {
        let result = HealthKitPermissionAudit.degradedFeatures(missing: [.heartRate, .activeEnergy])
        XCTAssertEqual(result, [.intensityZones, .loadEstimate])
    }

    func testAllSignalsMissingDegradesAllFeatures() {
        let result = HealthKitPermissionAudit.degradedFeatures(missing: Set(HealthKitPermissionAudit.CriticalSignal.allCases))
        XCTAssertEqual(result, Set(HealthKitPermissionAudit.DegradedFeature.allCases))
    }
}
