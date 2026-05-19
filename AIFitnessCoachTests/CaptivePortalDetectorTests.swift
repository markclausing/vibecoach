import XCTest
@testable import AIFitnessCoach

final class CaptivePortalDetectorTests: XCTestCase {

    private func response(status: Int, contentType: String?) -> HTTPURLResponse {
        var fields: [String: String] = [:]
        if let ct = contentType { fields["Content-Type"] = ct }
        return HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: fields
        )!
    }

    // MARK: Reactieve detectie

    func testJSONResponseIsNotCaptivePortal() {
        let resp = response(status: 200, contentType: "application/json; charset=utf-8")
        let data = #"{"hello":"world"}"#.data(using: .utf8)!
        XCTAssertFalse(CaptivePortalDetector.isLikelyCaptivePortal(response: resp, data: data))
    }

    func testHTMLContentTypeIsCaptivePortal() {
        let resp = response(status: 200, contentType: "text/html; charset=utf-8")
        let data = "<html>blocked</html>".data(using: .utf8)!
        XCTAssertTrue(CaptivePortalDetector.isLikelyCaptivePortal(response: resp, data: data))
    }

    func testDoctypePrefixIsCaptivePortal() {
        // Caller stuurt naar een JSON-endpoint, server gaf HTML zonder
        // correcte content-type — vaak het geval bij corporate proxies.
        let resp = response(status: 200, contentType: "application/octet-stream")
        let data = "<!DOCTYPE html><html><body>Login required</body></html>".data(using: .utf8)!
        XCTAssertTrue(CaptivePortalDetector.isLikelyCaptivePortal(response: resp, data: data))
    }

    func testHTMLPrefixWithLeadingWhitespaceIsCaptivePortal() {
        let resp = response(status: 200, contentType: nil)
        let data = "\n  <html><body>portal</body></html>".data(using: .utf8)!
        XCTAssertTrue(CaptivePortalDetector.isLikelyCaptivePortal(response: resp, data: data))
    }

    func testHTMLWithUTF8BOMIsCaptivePortal() {
        let resp = response(status: 200, contentType: nil)
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("<!doctype html><html></html>".data(using: .utf8)!)
        XCTAssertTrue(CaptivePortalDetector.isLikelyCaptivePortal(response: resp, data: data))
    }

    func testEmptyBodyWithJSONContentTypeIsNotCaptivePortal() {
        let resp = response(status: 204, contentType: "application/json")
        XCTAssertFalse(CaptivePortalDetector.isLikelyCaptivePortal(response: resp, data: Data()))
    }

    func testXMLPrefixIsCaptivePortal() {
        let resp = response(status: 200, contentType: nil)
        let data = "<?xml version=\"1.0\"?><portal/>".data(using: .utf8)!
        XCTAssertTrue(CaptivePortalDetector.isLikelyCaptivePortal(response: resp, data: data))
    }

    func testContentTypeCaseInsensitive() {
        let resp = response(status: 200, contentType: "TEXT/HTML; charset=UTF-8")
        let data = "<html></html>".data(using: .utf8)!
        XCTAssertTrue(CaptivePortalDetector.isLikelyCaptivePortal(response: resp, data: data))
    }

    // MARK: Apple-probe

    func testAppleProbeRecognizesSuccessMarker() {
        let resp = response(status: 200, contentType: "text/html")
        let body = "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>"
        let data = body.data(using: .utf8)!
        XCTAssertTrue(CaptivePortalDetector.isAppleProbeSuccess(data: data, response: resp))
    }

    func testAppleProbeRejectsRedirectStatus() {
        let resp = response(status: 302, contentType: "text/html")
        let data = "Success".data(using: .utf8)!
        XCTAssertFalse(CaptivePortalDetector.isAppleProbeSuccess(data: data, response: resp))
    }

    func testAppleProbeRejectsHijackedHTML() {
        // Captive-portal hijack: HTTP 200, maar body bevat geen "Success".
        let resp = response(status: 200, contentType: "text/html")
        let body = "<html><head><title>Login Required</title></head></html>"
        let data = body.data(using: .utf8)!
        XCTAssertFalse(CaptivePortalDetector.isAppleProbeSuccess(data: data, response: resp))
    }

    func testAppleProbeRejectsNonUTF8Body() {
        let resp = response(status: 200, contentType: "text/html")
        let data = Data([0xFF, 0xFE, 0xFD])
        XCTAssertFalse(CaptivePortalDetector.isAppleProbeSuccess(data: data, response: resp))
    }
}
