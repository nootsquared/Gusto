import XCTest

final class RescueUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }
    private func tap(_ id: String, timeout: TimeInterval = 8) {
        let element = app.buttons[id]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing button: \(id)")
        for _ in 0..<4 where !element.isHittable { app.swipeUp() }
        element.tap()
    }
    private func reserveViaSearch(_ phrase: String, id: String) {
        tap("search")
        let field = app.textFields["search-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(phrase)
        tap("result-\(id)")
        tap("reserve")
        tap("close-sheet")
    }
    func testDiscoverToFourSellerPickupAndImpact() {
        tap("listing-straw")
        screenshot("Listing sheet")
        tap("reserve")
        tap("close-sheet")
        reserveViaSearch("yogurt", id: "yog")
        reserveViaSearch("sourdough", id: "bread")
        // Pasta is 0.8 mi away and remains inside the default Near Me filter.
        reserveViaSearch("rigatoni", id: "pasta")
        tap("cart")
        screenshot("Cart")
        tap("plan-pickups")
        screenshot("Smart pickup plan")
        tap("coordinate")
        tap("accept-time")
        screenshot("Coordinated plan")
        tap("start-run")
        tap("active-run")
        for index in 0..<4 {
            tap("arrive")
            if index == 0 { screenshot("Arrival") }
            tap("im-here")
            if index == 0 { screenshot("Verify pickup") }
            tap("verify-pickup")
            if index == 0 { screenshot("Demo payment") }
            tap("pay")
            tap("continue-run")
        }
        XCTAssertTrue(app.staticTexts["impact-saved"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["impact-saved"].label, "$14.63")
        XCTAssertEqual(app.staticTexts["impact-pounds"].label, "6.1 lb")
        screenshot("Completed rescue run")
        tap("impact-done")
        XCTAssertTrue(app.staticTexts["Priya S."].waitForExistence(timeout: 5))
        screenshot("Profile after rescue")
    }
    func testChatComposerAndCorrectPinnedItem() {
        app.tabBars.buttons["Messages"].tap()
        screenshot("Messages")
        tap("chat-sam")
        XCTAssertTrue(app.staticTexts["Hass Avocados"].waitForExistence(timeout: 5))
        let field =
            app.textViews["message-input"].exists
            ? app.textViews["message-input"] : app.textFields["message-input"]
        field.tap()
        field.typeText("Hi Sam")
        tap("send-message")
        XCTAssertTrue(app.staticTexts["Hi Sam"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Sounds good! See you at pickup."].waitForExistence(timeout: 5))
        screenshot("Chat")
    }
    func testSellRequiresSafetyThenPublishes() {
        app.tabBars.buttons["Sell"].tap()
        tap("take-photo")
        XCTAssertTrue(app.buttons["publish-listing"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["publish-listing"].isEnabled)
        screenshot("Sell editor")
        for _ in 0..<4 where !app.buttons["confirm-safety"].isHittable { app.swipeUp() }
        tap("confirm-safety")
        tap("publish-listing")
        XCTAssertTrue(app.staticTexts["published"].waitForExistence(timeout: 5))
        screenshot("Published mock listing")
    }
    func testDiscoveryScreenshotAndEmptyFilterResults() {
        screenshot("Discover")
        app.tabBars.buttons["Map"].tap()
        screenshot("Map with listings")
        app.tabBars.buttons["You"].tap()
        screenshot("Profile baseline")
        app.tabBars.buttons["Discover"].tap()
        app.buttons["Filters"].tap()
        screenshot("Filters before selection")
        let tomorrow = app.switches["filter-tomorrow"]
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 5))
        for _ in 0..<4 where !tomorrow.isHittable { app.swipeUp() }
        // SwiftUI exposes the entire Form row as the switch; tap its trailing control.
        tomorrow.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        screenshot("Tomorrow filter")
        XCTAssertEqual(tomorrow.value as? String, "1")
        tap("apply-filters")
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(
            app.staticTexts["No matches · change your filters"].waitForExistence(timeout: 5))
        screenshot("Map empty results")
    }
    private func screenshot(_ name: String) {
        // UIKit sheet transitions can still be drawing after XCTest considers the app idle.
        Thread.sleep(forTimeInterval: 0.6)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension RescueUITests {
    func testCloudLaunchRequiresSignIn() {
        app.terminate()
        app.launchArguments = ["--uitesting", "--backend"]
        app.launch()
        XCTAssertTrue(app.buttons["google-sign-in"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Welcome to Rescue"].exists)
        XCTAssertFalse(app.buttons["account-demo-buyer"].exists)
        screenshot("Cloud sign-in")
    }
    /// Requires MHacksDB, media service and the separate simulator; fixture tests remain independent.
    func testConnectedSellerPublishesBuyerReservesAndPays() throws {
        guard ProcessInfo.processInfo.environment["RESCUE_CONNECTED_TESTS"] == "1" else {
            throw XCTSkip("Enable RESCUE_CONNECTED_TESTS with local services running")
        }
        app.terminate()
        app.launchArguments = ["--uitesting", "--backend", "--local-backend", "--account", "riley"]
        app.launch()
        app.tabBars.buttons["Sell"].tap()
        if app.buttons["take-photo"].waitForExistence(timeout: 2) { tap("take-photo") }
        let name = app.textFields["sell-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        name.typeText("Connected Oats")
        app.buttons["Done"].firstMatch.tapIfExists()
        app.swipeUp()
        app.swipeUp()
        tap("confirm-safety")
        tap("publish-listing")
        if !app.staticTexts["published"].waitForExistence(timeout: 15) {
            screenshot("Connected publish failure")
            print(app.debugDescription)
            XCTFail("Connected publish failed")
            return
        }
        app.terminate()
        app.launchArguments = ["--uitesting", "--backend", "--local-backend", "--account", "demo-buyer"]
        app.launch()
        app.tabBars.buttons["Discover"].tap()
        tap("search")
        let query = app.textFields["search-input"]
        query.tap()
        query.typeText("connected oats")
        let result = app.staticTexts["Connected Oats"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        result.tap()
        tap("reserve")
        tap("close-sheet")
        tap("cart")
        XCTAssertTrue(app.staticTexts["Connected Oats"].firstMatch.waitForExistence(timeout: 15))
        tap("plan-pickups")
        tap("coordinate", timeout: 15)
        tap("start-run", timeout: 20)
        tap("active-run", timeout: 15)
        tap("arrive", timeout: 15)
        tap("im-here", timeout: 15)
        tap("verify-pickup", timeout: 20)
        tap("pay", timeout: 15)
        XCTAssertTrue(app.staticTexts["Rescued"].waitForExistence(timeout: 20))
        screenshot("Connected database payment")
        tap("continue-run")
        tap("impact-done")
    }
}

extension XCUIElement {
    fileprivate func tapIfExists() { if exists && isHittable { tap() } }
}
