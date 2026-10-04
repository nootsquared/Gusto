import XCTest

#if canImport(RescueCore)
    @testable import RescueCore
#else
    @testable import Rescue
#endif

@MainActor final class RescueCoreTests: XCTestCase {
    private func makeStore() -> AppStore { AppStore(service: DemoService(delayNanoseconds: 0)) }
    private func reserveDemo(_ store: AppStore) {
        for id in ["straw", "yog", "bread", "pasta"] { XCTAssertTrue(store.addToCart(id)) }
    }
    private func begin(_ store: AppStore) async {
        store.makePlan()
        await store.coordinate()
        store.acceptCounter()
        XCTAssertTrue(store.startRun())
    }

    func testExactSourceCatalogAndIntegerTotals() async {
        let store = makeStore()
        reserveDemo(store)
        XCTAssertEqual(store.catalog.count, 20)
        XCTAssertEqual(store.cartTotals.pay, 775)
        XCTAssertEqual(store.cartTotals.saved, 1463)
        XCTAssertEqual(store.cartTotals.pounds, 6.1, accuracy: 0.0001)
        XCTAssertEqual(Money.text(199), "$1.99")
    }
    func testReservationIsUniqueAndInvalidIDsAreRejected() async {
        let store = makeStore()
        XCTAssertTrue(store.addToCart("straw"))
        XCTAssertFalse(store.addToCart("straw"))
        XCTAssertFalse(store.addToCart("missing"))
        XCTAssertEqual(store.cart, ["straw"])
    }
    func testCartGroupsMultipleItemsPerSeller() async {
        let store = makeStore()
        store.addToCart("straw")
        store.addToCart("bana")
        store.addToCart("yog")
        store.makePlan()
        XCTAssertEqual(store.plan?.stops.count, 2)
        XCTAssertEqual(store.plan?.stops.first?.items.count, 2)
        XCTAssertEqual(store.plan?.totals.count, 3)
    }
    func testCannotStartBeforeSellerConfirmations() async {
        let store = makeStore()
        reserveDemo(store)
        store.makePlan()
        XCTAssertFalse(store.startRun())
        await store.coordinate()
        XCTAssertEqual(store.counterSellerID, "nina")
        XCTAssertFalse(store.startRun())
        store.acceptCounter()
        XCTAssertTrue(store.startRun())
    }
    func testCounterofferPropagatesDownstream() async {
        let store = makeStore()
        reserveDemo(store)
        store.makePlan()
        let before = store.plan!.stops.map(\.minute)
        await store.coordinate()
        store.acceptCounter()
        XCTAssertEqual(
            store.plan!.stops.map(\.minute), [before[0], before[1], before[2] + 9, before[3] + 9])
        XCTAssertEqual(store.plan?.stops[2].time, "4:45")
    }
    func testAlternativeIsDistinctFromAccept() async {
        let store = makeStore()
        reserveDemo(store)
        store.makePlan()
        await store.coordinate()
        store.acceptCounter(alternative: true)
        XCTAssertEqual(store.plan?.stops[2].time, "4:55")
        XCTAssertEqual(store.plan?.stops[3].time, "5:07")
    }
    func testRouteModesProduceDifferentPlans() async {
        let store = makeStore()
        for id in ["straw", "avo", "yog", "bread", "pasta"] { store.addToCart(id) }
        store.makePlan()
        let fastest = store.plan!
        store.makePlan(mode: .shortest)
        XCTAssertNotEqual(store.plan?.stops.map(\.id), fastest.stops.map(\.id))
        XCTAssertLessThan(store.plan!.distance, fastest.distance)
        store.makePlan(mode: .bestTiming)
        XCTAssertEqual(store.plan?.stops.first?.id, "nina")
    }
    func testCartMutationInvalidatesConfirmations() async {
        let store = makeStore()
        store.addToCart("straw")
        store.makePlan()
        await store.coordinate()
        XCTAssertEqual(store.plan?.allConfirmed, true)
        store.addToCart("yog")
        XCTAssertNil(store.plan)
        XCTAssertFalse(store.startRun())
        store.makePlan()
        store.remove("yog")
        XCTAssertNil(store.plan)
    }
    func testEmptyPlanCannotStart() async {
        let store = makeStore()
        store.makePlan()
        await store.coordinate()
        XCTAssertEqual(store.plan?.elapsed, 0)
        XCTAssertFalse(store.startRun())
        XCTAssertFalse(store.coordinating)
    }
    func testFullFourSellerDemoAndImpact() async {
        let store = makeStore()
        reserveDemo(store)
        await begin(store)
        for index in 0..<4 {
            XCTAssertEqual(store.stopIndex, index)
            XCTAssertEqual(store.phase, .enroute)
            store.arrive()
            XCTAssertEqual(store.phase, .arrived)
            await store.announceArrival()
            XCTAssertEqual(store.phase, .verifying)
            store.verify()
            XCTAssertEqual(store.phase, .payment)
            await store.pay()
            XCTAssertEqual(store.phase, .rescued)
            store.continueRun()
        }
        XCTAssertEqual(store.phase, .finished)
        XCTAssertEqual(store.runImpact.saved, 1463)
        XCTAssertEqual(store.impact.pay, 775)
        XCTAssertEqual(store.impact.pounds, 6.1, accuracy: 0.0001)
        XCTAssertEqual(store.receipts.count, 4)
        store.finishRun()
        XCTAssertEqual(store.phase, .idle)
        XCTAssertTrue(store.cart.isEmpty)
        XCTAssertEqual(store.impact.saved, 1463)
        XCTAssertFalse(store.addToCart("straw"))
    }
    func testDuplicatePayCannotDoubleCharge() async {
        let store = AppStore(service: DemoService(delayNanoseconds: 10_000_000))
        store.addToCart("straw")
        await begin(store)
        store.arrive()
        await store.announceArrival()
        store.verify()
        async let first: Void = store.pay()
        async let second: Void = store.pay()
        _ = await (first, second)
        XCTAssertEqual(store.receipts.count, 1)
        XCTAssertEqual(store.impact.pay, 250)
        await store.pay()
        XCTAssertEqual(store.receipts.count, 1)
    }
    func testIssueSkipsChargeAndImpact() async {
        let store = makeStore()
        store.addToCart("straw")
        await begin(store)
        store.arrive()
        await store.announceArrival()
        store.reportIssue()
        await store.pay()
        XCTAssertEqual(store.phase, .finished)
        XCTAssertEqual(store.receipts.count, 0)
        XCTAssertEqual(store.runImpact.saved, 0)
    }
    func testOutOfOrderPaymentAndVerificationAreRejected() async {
        let store = makeStore()
        store.addToCart("straw")
        await store.pay()
        store.verify()
        store.arrive()
        XCTAssertEqual(store.phase, .idle)
        XCTAssertTrue(store.receipts.isEmpty)
    }
    func testActiveRunLocksReservationsAndPlanEdits() async {
        let store = makeStore()
        reserveDemo(store)
        await begin(store)
        let ids = store.cart
        let stops = store.plan!.stops.map(\.id)
        XCTAssertFalse(store.addToCart("bana"))
        store.remove("straw")
        store.makePlan(mode: .shortest)
        XCTAssertEqual(store.cart, ids)
        XCTAssertEqual(store.plan?.stops.map(\.id), stops)
    }
    func testDelayMovesRemainingStopsOnly() async {
        let store = makeStore()
        reserveDemo(store)
        await begin(store)
        store.arrive()
        await store.announceArrival()
        store.verify()
        await store.pay()
        store.continueRun()
        let before = store.plan!.stops.map(\.minute)
        store.delayStop("alex")
        XCTAssertEqual(
            store.plan!.stops.map(\.minute),
            [before[0], before[1] + 10, before[2] + 10, before[3] + 10])
        store.delayStop("maya")
        XCTAssertEqual(store.plan?.stops[0].minute, before[0])
    }
    func testFiltersAndNaturalLanguageSearchApplyToActualResults() async {
        let store = makeStore()
        let results = store.visibleListings(query: "snacks under $2")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(
            results.allSatisfy { $0.category == "Snacks" && $0.price < 200 && $0.distance <= 0.8 })
        store.filters.categories = ["Bakery"]
        XCTAssertEqual(store.visibleListings(query: "").map(\.id), ["bread"])
        store.filters.distance = 0.2
        XCTAssertTrue(store.visibleListings(query: "").isEmpty)
    }
    func testDistanceFilterCanExpandWithoutHiddenShortcut() {
        let store = makeStore()
        XCTAssertFalse(store.visibleListings(query: "").contains { $0.id == "gran" })
        store.filters.distance = 1.2
        XCTAssertTrue(store.visibleListings(query: "").contains { $0.id == "gran" })
        store.filters.maxPrice = 250
        XCTAssertFalse(store.visibleListings(query: "").contains { $0.id == "gran" })
        XCTAssertTrue(store.visibleListings(query: "").contains { $0.id == "bread" })
        store.filters = Filters()
        XCTAssertEqual(store.filters.distance, 0.8)
    }
    func testFreshCheckAndChatStayWithCorrectSeller() async {
        let store = makeStore()
        XCTAssertTrue(store.listing("bread")!.stale)
        await store.freshCheck("bread")
        XCTAssertFalse(store.listing("bread")!.stale)
        XCTAssertEqual(store.listing("bread")?.updated, "just now")
        await store.send("I'm here", to: "sam")
        XCTAssertEqual(store.messages["sam"]?.last?.text, "Coming out now!")
        XCTAssertEqual(store.pinnedListing(for: "sam")?.sellerID, "sam")
        XCTAssertFalse(store.typingSellers.contains("sam"))
        let count = store.messages["sam"]!.count
        await store.send("  ", to: "sam")
        XCTAssertEqual(store.messages["sam"]?.count, count)
    }
    func testPublishingRequiresAllSafetyChecks() async {
        let store = makeStore()
        XCTAssertFalse(
            store.publish(
                name: "Granola", price: 300, freshness: .fresh, pickup: "Tonight", confirmations: 3)
        )
        XCTAssertFalse(
            store.publish(
                name: "", price: 300, freshness: .fresh, pickup: "Tonight", confirmations: 4))
        XCTAssertTrue(
            store.publish(
                name: "Granola", price: 300, freshness: .fresh, pickup: "Tonight", confirmations: 4)
        )
        XCTAssertEqual(store.listing("my-granola")?.price, 300)
        XCTAssertEqual(store.catalog.count, 21)
    }
    func testResetProducesCleanDemo() async {
        let store = makeStore()
        reserveDemo(store)
        await begin(store)
        store.resetDemo()
        XCTAssertEqual(store.phase, .idle)
        XCTAssertNil(store.plan)
        XCTAssertTrue(store.cart.isEmpty)
        XCTAssertEqual(store.catalog.count, 20)
    }
    func testResetDiscardsPendingChatAndFreshCheck() async throws {
        let store = AppStore(service: DemoService(delayNanoseconds: 40_000_000))
        let message = Task { await store.send("Hi Sam", to: "sam") }
        let freshCheck = Task { await store.freshCheck("bread") }
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(store.typingSellers.contains("sam"))
        XCTAssertTrue(store.checkingIDs.contains("bread"))
        store.resetDemo()
        await message.value
        await freshCheck.value
        XCTAssertNil(store.messages["sam"])
        XCTAssertTrue(store.typingSellers.isEmpty)
        XCTAssertTrue(store.checkingIDs.isEmpty)
        XCTAssertTrue(store.listing("bread")!.stale)
        XCTAssertNil(store.notice)
    }
    func testSameSellerAcrossRunsHasDistinctReceiptIDs() async {
        let store = makeStore()
        for id in ["straw", "bana"] {
            store.addToCart(id)
            await begin(store)
            store.arrive()
            await store.announceArrival()
            store.verify()
            await store.pay()
            store.continueRun()
            store.finishRun()
        }
        XCTAssertEqual(store.receipts.count, 2)
        XCTAssertEqual(Set(store.receipts.map(\.id)).count, 2)
        XCTAssertEqual(store.impact.pay, 325)
    }
}
