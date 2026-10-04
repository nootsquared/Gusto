import XCTest

#if canImport(RescueCore)
    @testable import RescueCore
#else
    @testable import Rescue
#endif

final class OAuthTests: XCTestCase {
    func testPKCEStandardVector() {
        XCTAssertEqual(
            RescueOAuth.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
    func testCallbackRejectsWrongStateDestinationAndDuplicates() throws {
        XCTAssertEqual(
            try RescueOAuth.callbackCode(
                URL(string: "\(RescueOAuth.redirect)?state=expected&code=valid")!, state: "expected"
            ), "valid")
        for url in [
            "\(RescueOAuth.redirect)?state=wrong&code=valid",
            "com.other.app://oauth/callback?state=expected&code=valid",
            "\(RescueOAuth.redirect)?state=expected&code=one&code=two",
            "\(RescueOAuth.redirect)?state=expected&error=access_denied",
            "\(RescueOAuth.redirect)?state=expected&code=valid&iss=https://other.example",
        ] {
            XCTAssertThrowsError(try RescueOAuth.callbackCode(URL(string: url)!, state: "expected"))
        }
    }
    func testTokenResponseBinding() throws {
        var payload: [String: Any] = [
            "iss": RescueOAuth.issuer, "sub": "user", "aud": RescueOAuth.clientID,
            "project_id": RescueOAuth.projectID, "exp": 2000, "nonce": "expected",
        ]
        func token(_ fields: [String: Any]) throws -> String {
            "header.\(RescueOAuth.base64URL(try JSONSerialization.data(withJSONObject: fields))).signature"
        }
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(
            try RescueOAuth.claims(token(payload), nonce: "expected", now: now).sub, "user")
        for (key, value) in [
            ("aud", "other"), ("iss", "other"), ("project_id", "other"), ("nonce", "wrong"),
        ] {
            var invalid = payload
            invalid[key] = value
            XCTAssertThrowsError(
                try RescueOAuth.claims(token(invalid), nonce: "expected", now: now))
        }
        payload["aud"] = [RescueOAuth.clientID, "other"]
        XCTAssertThrowsError(try RescueOAuth.claims(token(payload), now: now))
        payload["azp"] = RescueOAuth.clientID
        XCTAssertNoThrow(try RescueOAuth.claims(token(payload), now: now))
        payload["exp"] = 999
        XCTAssertThrowsError(try RescueOAuth.claims(token(payload), now: now))
    }
}
