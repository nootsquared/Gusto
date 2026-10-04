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
