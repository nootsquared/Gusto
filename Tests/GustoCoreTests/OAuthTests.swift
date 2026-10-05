import XCTest

#if canImport(GustoCore)
    @testable import GustoCore
#else
    @testable import Gusto
#endif

final class OAuthTests: XCTestCase {
    func testPKCEStandardVector() {
        XCTAssertEqual(
            GustoOAuth.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
    func testCallbackRejectsWrongStateDestinationAndDuplicates() throws {
        XCTAssertEqual(
            try GustoOAuth.callbackCode(
                URL(string: "\(GustoOAuth.redirect)?state=expected&code=valid")!, state: "expected"
            ), "valid")
        for url in [
            "\(GustoOAuth.redirect)?state=wrong&code=valid",
            "com.other.app://oauth/callback?state=expected&code=valid",
            "\(GustoOAuth.redirect)?state=expected&code=one&code=two",
            "\(GustoOAuth.redirect)?state=expected&error=access_denied",
            "\(GustoOAuth.redirect)?state=expected&code=valid&iss=https://other.example",
        ] {
            XCTAssertThrowsError(try GustoOAuth.callbackCode(URL(string: url)!, state: "expected"))
        }
    }
    func testTokenResponseBinding() throws {
        var payload: [String: Any] = [
            "iss": GustoOAuth.issuer, "sub": "user", "aud": GustoOAuth.clientID,
            "project_id": GustoOAuth.projectID, "exp": 2000, "nonce": "expected",
        ]
        func token(_ fields: [String: Any]) throws -> String {
            "header.\(GustoOAuth.base64URL(try JSONSerialization.data(withJSONObject: fields))).signature"
        }
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(
            try GustoOAuth.claims(token(payload), nonce: "expected", now: now).sub, "user")
        for (key, value) in [
            ("aud", "other"), ("iss", "other"), ("project_id", "other"), ("nonce", "wrong"),
        ] {
            var invalid = payload
            invalid[key] = value
            XCTAssertThrowsError(
                try GustoOAuth.claims(token(invalid), nonce: "expected", now: now))
        }
        payload["aud"] = [GustoOAuth.clientID, "other"]
        XCTAssertThrowsError(try GustoOAuth.claims(token(payload), now: now))
        payload["azp"] = GustoOAuth.clientID
        XCTAssertNoThrow(try GustoOAuth.claims(token(payload), now: now))
        payload["exp"] = 999
        XCTAssertThrowsError(try GustoOAuth.claims(token(payload), now: now))
    }
}
