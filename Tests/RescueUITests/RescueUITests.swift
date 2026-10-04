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
    func testGustoWelcomeMessage() {
        app.tabBars.buttons["Messages"].tap()
        tap("gusto-welcome")
        XCTAssertTrue(app.staticTexts["Hi! Welcome to Gusto 👋"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Save now, decide later"].exists)
        XCTAssertFalse(app.textFields["message-input"].exists)
        screenshot("Gusto welcome message")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["gusto-welcome"].waitForExistence(timeout: 5))
    }
    private func addViaSearch(_ phrase: String, id: String) {
        if app.buttons["Clear search"].exists { app.buttons["Clear search"].tap() }
        let field = app.textFields["search-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(phrase)
        tap("result-\(id)")
        tap("add-to-cart")
        tap("close-sheet")
    }
    func testDiscoverToFourSellerPickupAndImpact() {
        tap("listing-straw")
        screenshot("Listing sheet")
        tap("add-to-cart")
        tap("close-sheet")
        addViaSearch("yogurt", id: "yog")
        addViaSearch("sourdough", id: "bread")
        // Pasta is 0.8 mi away and remains inside the default Near Me filter.
        addViaSearch("rigatoni", id: "pasta")
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
        screenshot("Completed pickup trip")
        tap("impact-done")
        XCTAssertTrue(app.staticTexts["Priya S."].waitForExistence(timeout: 5))
        screenshot("Profile after pickup")
    }
    func testInteractiveMarketplaceMapAndLocationPicker() {
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.buttons["map-location"].waitForExistence(timeout: 8))
        screenshot("Apple Maps before pan")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.45))
        start.press(forDuration: 0.1, thenDragTo: end)
        tap("search-map-area")
        XCTAssertTrue(app.buttons["recenter-map"].exists)
        tap("map-location")
        XCTAssertTrue(app.textFields["map-address-search"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["map-use-current-location"].exists)
        XCTAssertFalse(app.navigationBars["Your location"].exists)
        screenshot("Map location dropdown")
        tap("map-location")
        XCTAssertFalse(app.textFields["map-address-search"].exists)
        screenshot("Interactive marketplace map")
    }

    func testMapAddressSearchPinsSelection() {
        app.tabBars.buttons["Map"].tap()
        tap("map-location")
        let field = app.textFields["map-address-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("University of Michigan Museum of Art")
        tap("map-address-result-0", timeout: 20)
        XCTAssertFalse(field.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "selected-location-pin")
            .firstMatch.waitForExistence(timeout: 8))
        screenshot("Selected address pin")
    }

    func testInlineDiscoverySearchAndClear() {
        let field = app.textFields["search-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertFalse(app.staticTexts["cheap breakfast"].exists)
        field.typeText("avocado")
        XCTAssertTrue(app.buttons["result-avo"].waitForExistence(timeout: 5))
        screenshot("Inline search results")
        app.buttons["Clear search"].tap()
        field.typeText("zzzznofood")
        XCTAssertTrue(app.staticTexts["No matches nearby"].waitForExistence(timeout: 5))
        tap("cancel-search")
        XCTAssertTrue(app.staticTexts["Picked for you"].waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Search food nearby")
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
    func testScanSavesPrivateItemAndShowsSellReview() {
        app.tabBars.buttons["Scan"].tap()
        XCTAssertTrue(app.staticTexts["Scan an item."].waitForExistence(timeout: 5))
        screenshot("Scan home")
        tap("scan-sensor")
        XCTAssertTrue(app.buttons["find-sensor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Not connected"].exists)
        screenshot("Bluetooth connection panel")
        tap("close-sheet")
        tap("scan-food")
        tap("save-scan")
        XCTAssertTrue(app.staticTexts["Roma Tomato"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Private collection"].exists)
        screenshot("Private food item")
        tap("sell-scanned-item")
        XCTAssertTrue(app.buttons["publish-scanned-item"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["publish-scanned-item"].isEnabled)
        screenshot("Scanned item listing review")
        tap("close-sheet")
        app.swipeUp()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'inventory-'")).firstMatch.waitForExistence(timeout: 5))
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
            app.staticTexts["No food in this area yet"].waitForExistence(timeout: 5))
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
    func testManualLocationPickerOpens() {
        app.buttons["browse-location"].tap()
        XCTAssertTrue(app.buttons["use-current-location"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["location-search"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["browse-location"].exists)
    }

    func testCloudLaunchRequiresSignIn() {
        app.terminate()
        app.launchArguments = ["--uitesting", "--backend", "--welcome-preview"]
        app.launch()
        XCTAssertTrue(app.buttons["google-sign-in"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Welcome to Gusto. Good food. Better prices."].exists)
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
        app.tabBars.buttons["Scan"].tap()
        tap("scan-food")
        let name = app.textFields["scan-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30))
        name.typeText("Connected Oats")
        let variety = app.textFields["scan-variety"]
        variety.tap()
        variety.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30))
        app.swipeUp()
        tap("save-scan")
        tap("sell-scanned-item")
        app.textFields["scan-sell-price"].tap()
        app.textFields["scan-sell-price"].typeText("2.50")
        app.textFields["scan-sell-allergens"].tap()
        app.textFields["scan-sell-allergens"].typeText("Oats")
        app.swipeUp()
        app.textFields["scan-pickup-address"].tap()
        app.textFields["scan-pickup-address"].typeText("University of Michigan Museum of Art")
        app.buttons["Find address"].tap()
        tap("pickup-place-0", timeout: 15)
        app.swipeUp()
        for title in ["Stored safely", "Condition is accurate", "No signs of spoilage", "Allergens are declared"] {
            let toggle = app.switches[title]
            for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
            toggle.tap()
        }
        tap("publish-scanned-item")
        XCTAssertTrue(app.buttons["scan-food"].waitForExistence(timeout: 15))
        app.terminate()
        app.launchArguments = ["--uitesting", "--backend", "--local-backend", "--account", "demo-buyer"]
        app.launch()
        app.tabBars.buttons["Discover"].tap()
        let query = app.textFields["search-input"]
        query.tap()
        query.typeText("connected oats")
        let result = app.staticTexts["Connected Oats"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        result.tap()
        tap("add-to-cart")
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
        XCTAssertTrue(app.staticTexts["Picked up"].waitForExistence(timeout: 20))
        screenshot("Connected database payment")
        tap("continue-run")
        tap("impact-done")
    }
}

extension XCUIElement {
    fileprivate func tapIfExists() { if exists && isHittable { tap() } }
}
