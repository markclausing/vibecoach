import XCTest
@testable import AIFitnessCoach

final class StravaRateLimitParserTests: XCTestCase {

    private let fixedNow = Date(timeIntervalSince1970: 1_715_000_000) // 2024-05-06 12:53:20 UTC

    // MARK: Delta-seconds variant

    func testParsesIntegerSeconds() {
        let headers: [AnyHashable: Any] = ["Retry-After": "60"]
        let result = StravaRateLimitParser.retryAfter(headers: headers, now: fixedNow)
        XCTAssertEqual(result.timeIntervalSince(fixedNow), 60, accuracy: 0.001)
    }

    func testParsesLargeSeconds() {
        let headers: [AnyHashable: Any] = ["Retry-After": "900"] // 15 min
        let result = StravaRateLimitParser.retryAfter(headers: headers, now: fixedNow)
        XCTAssertEqual(result.timeIntervalSince(fixedNow), 900, accuracy: 0.001)
    }

    func testParsesZeroSeconds() {
        // Zero is een geldige delta-seconds-waarde — hervat onmiddellijk.
        // Bescherming tegen retry-storm zit in de caller-side cooldown-check.
        let headers: [AnyHashable: Any] = ["Retry-After": "0"]
        let result = StravaRateLimitParser.retryAfter(headers: headers, now: fixedNow)
        XCTAssertEqual(result.timeIntervalSince(fixedNow), 0, accuracy: 0.001)
    }

    func testTrimsWhitespaceAroundSeconds() {
        let headers: [AnyHashable: Any] = ["Retry-After": "  120  "]
        let result = StravaRateLimitParser.retryAfter(headers: headers, now: fixedNow)
        XCTAssertEqual(result.timeIntervalSince(fixedNow), 120, accuracy: 0.001)
    }

    // MARK: HTTP-datum variant

    func testParsesHTTPDate() {
        // RFC 7231 IMF-fixdate. 2024-05-06 13:03:20 GMT = +600s vs fixedNow.
        let headers: [AnyHashable: Any] = ["Retry-After": "Mon, 06 May 2024 13:03:20 GMT"]
        let result = StravaRateLimitParser.retryAfter(headers: headers, now: fixedNow)
        XCTAssertEqual(result.timeIntervalSince(fixedNow), 600, accuracy: 1.0)
    }

    func testHTTPDateInThePastFallsBackToDefault() {
        // Datum vóór `now` — klok-skew of stale header. Gebruik default
        // i.p.v. onmiddellijke retry zodat we niet in een storm belanden.
        let headers: [AnyHashable: Any] = ["Retry-After": "Sun, 05 May 2024 13:03:20 GMT"]
        let result = StravaRateLimitParser.retryAfter(headers: headers, now: fixedNow)
        XCTAssertEqual(result.timeIntervalSince(fixedNow),
                       StravaRateLimitParser.defaultCooldownSeconds,
                       accuracy: 0.001)
    }

    // MARK: Case-insensitivity

    func testHeaderLookupIsCaseInsensitive() {
        let lowercased: [AnyHashable: Any] = ["retry-after": "30"]
        let uppercased: [AnyHashable: Any] = ["RETRY-AFTER": "30"]
        let mixedCase: [AnyHashable: Any] = ["ReTrY-aFtEr": "30"]

        for headers in [lowercased, uppercased, mixedCase] {
            let result = StravaRateLimitParser.retryAfter(headers: headers, now: fixedNow)
            XCTAssertEqual(result.timeIntervalSince(fixedNow), 30, accuracy: 0.001)
        }
    }

    // MARK: Fallback paden

    func testMissingHeaderUsesDefaultCooldown() {
        let result = StravaRateLimitParser.retryAfter(headers: [:], now: fixedNow)
        XCTAssertEqual(result.timeIntervalSince(fixedNow),
                       StravaRateLimitParser.defaultCooldownSeconds,
                       accuracy: 0.001)
    }

    func testEmptyValueUsesDefault() {
        let headers: [AnyHashable: Any] = ["Retry-After": ""]
        let result = StravaRateLimitParser.retryAfter(headers: headers, now: fixedNow)
        XCTAssertEqual(result.timeIntervalSince(fixedNow),
                       StravaRateLimitParser.defaultCooldownSeconds,
                       accuracy: 0.001)
    }

    func testUnparseableValueUsesDefault() {
        let headers: [AnyHashable: Any] = ["Retry-After": "not-a-number-or-date"]
        let result = StravaRateLimitParser.retryAfter(headers: headers, now: fixedNow)
        XCTAssertEqual(result.timeIntervalSince(fixedNow),
                       StravaRateLimitParser.defaultCooldownSeconds,
                       accuracy: 0.001)
    }

    func testNegativeSecondsUsesDefault() {
        // RFC sta géén negatieve delta-seconds toe; behandel als ongeldig.
        let headers: [AnyHashable: Any] = ["Retry-After": "-10"]
        let result = StravaRateLimitParser.retryAfter(headers: headers, now: fixedNow)
        XCTAssertEqual(result.timeIntervalSince(fixedNow),
                       StravaRateLimitParser.defaultCooldownSeconds,
                       accuracy: 0.001)
    }
}
