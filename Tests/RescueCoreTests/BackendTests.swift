import XCTest

#if canImport(RescueCore)
    @testable import RescueCore
#else
    @testable import Rescue
#endif

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.notConnectedToInternet) }
            let bytes = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: bytes)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
@MainActor final class BackendTests: XCTestCase {
    private var folder: URL!
    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        StubURLProtocol.handler = nil
    }
    private func repository(_ user: String) -> HTTPRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return HTTPRepository(
            server: URL(string: "http://localhost:3000")!, database: "test",
            session: BackendSession(userId: user, token: "private-token-\(user)"),
            cacheRoot: folder,
            network: URLSession(configuration: configuration))
    }
    private func bootstrap(_ user: String) throws -> Data {
        let value: [String: Any] = [
            "user": ["id": user, "name": user],
            "preferences": [
                "vegetarian": false, "area": "Linden Park", "smartAlerts": false, "version": 1,
            ],
            "cart": [], "cartListings": [], "savedListings": [], "favorites": [], "sellers": [],
            "receipts": [], "sales": [], "ownListings": [], "monthly": [], "conversations": [],
            "simulation": true,
        ]
        return try JSONSerialization.data(withJSONObject: value)
    }
    private func wire(_ payload: Data, error: String = "") throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            1, Date().timeIntervalSince1970 * 1000, error, String(decoding: payload, as: UTF8.self),
        ])
    }
    func testRealSellerCartAndIncomingInboxUpdates() async throws {
        var snapshot = try JSONSerialization.jsonObject(with: bootstrap("buyer")) as! [String: Any]
        let seller = Seller(
            id: "actual-seller", name: "Real Seller", rating: 5, pickups: 0,
            responds: "Soon", student: false, area: "Pickup location", latitude: 42.28,
            longitude: -83.74)
        var itemJSON =
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(MockCatalog.listings[0]))
            as! [String: Any]
        itemJSON["sellerID"] = seller.id
        let item = try JSONDecoder().decode(
            Listing.self, from: JSONSerialization.data(withJSONObject: itemJSON))
        snapshot["sellers"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([seller]))
        snapshot["cart"] = [item.id]
        snapshot["cartListings"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode([item]))
        var payload = try JSONSerialization.data(withJSONObject: snapshot)
        StubURLProtocol.handler = { _ in try self.wire(payload) }
        let store = AppStore()
        await store.connect(repository("buyer"))
        XCTAssertEqual(store.cartGroups.count, 1)
        XCTAssertEqual(store.cartGroups.first?.seller.id, seller.id)
        XCTAssertEqual(store.cartGroups.first?.items.first?.id, item.id)
        XCTAssertEqual(store.cartTotals.saved, item.retail - item.price)
        XCTAssertEqual(store.cartTotals.pounds, item.weight)
        XCTAssertNil(store.incomingNotification)

        snapshot["conversations"] = [
            [
                "id": "actual-seller:buyer", "buyerId": "buyer",
                "sellerId": seller.id, "summary": "I'd like a pickup", "sequence": 1,
                "lastRead": 0, "unreadCount": 1, "lastSenderId": seller.id, "lastMessageAt": 1000,
            ]
        ]
        payload = try JSONSerialization.data(withJSONObject: snapshot)
        await store.refreshBackend(force: true)
        XCTAssertEqual(store.unreadMessageCount, 1)
        XCTAssertEqual(store.incomingNotification?.senderID, seller.id)
        XCTAssertEqual(store.messagePreview(for: seller.id), "I'd like a pickup")
        XCTAssertEqual(store.messageSellers.first?.id, seller.id)
        await store.refreshBackend(force: true)
        XCTAssertEqual(store.incomingNotifications.count, 1)
        store.dismissIncomingNotification()
        await store.refreshBackend(force: true)
        XCTAssertNil(store.incomingNotification)
    }

    func testInventoryWritesImmediatelyUpdateCollectionAndReportReservation() async throws {
        let payload = try bootstrap("seller")
        let food = InventoryFood(id: "food", name: "Banana", listingID: "listing")
        let inventoryPayload = try JSONSerialization.data(withJSONObject: [
            "items": try JSONSerialization.jsonObject(with: JSONEncoder().encode([food])),
            "readings": [],
        ])
        var blocked = true
        StubURLProtocol.handler = { request in
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            let args = try JSONSerialization.jsonObject(with: body) as! [[String: Any]]
            let command = args[0]
            switch command["action"] as? String {
            case "bootstrap": return try self.wire(payload)
            case "inventory": return try self.wire(inventoryPayload)
            case "inventory_unlist", "inventory_remove":
                return try self.wire(Data("{}".utf8), error: blocked ? "unavailable" : "")
            default: return try self.wire(Data("{}".utf8))
            }
        }
        let store = AppStore()
        await store.connect(repository("seller"))
        await store.loadInventory()
        let rejected = await store.unlistInventoryFood(food.id)
        XCTAssertFalse(rejected)
        XCTAssertEqual(store.inventory.first?.listingID, food.listingID)
        XCTAssertTrue(store.notice?.contains("active pickup") ?? false)
        blocked = false
        let unlisted = await store.unlistInventoryFood(food.id)
        XCTAssertTrue(unlisted)
        XCTAssertEqual(store.inventory.first?.listingID, "")
        let removed = await store.removeInventoryFood(food.id)
        XCTAssertTrue(removed)
        XCTAssertTrue(store.inventory.isEmpty)
    }

    func testLiveSwiftBootstrap() async throws {
        guard ProcessInfo.processInfo.environment["RESCUE_LIVE_BACKEND"] == "1" else {
            throw XCTSkip("Local integration opt-in")
        }
        let (data, _) = try await URLSession.shared.data(
            from: URL(string: "http://127.0.0.1:8081/dev/accounts")!)
        struct Provisioned: Decodable { let accounts: [BackendSession] }
        let sessions = try JSONDecoder().decode(Provisioned.self, from: data)
        let user = sessions.accounts.first { $0.userId == "riley" }!
        let repo = HTTPRepository(
            server: URL(string: "http://127.0.0.1:3000")!, database: "mhacksdb", session: user,
            cacheRoot: folder)
        let response = try await repo.request(APIRequest("bootstrap"))
        let snapshot = try JSONDecoder().decode(BackendBootstrap.self, from: response.payload)
        XCTAssertEqual(snapshot.user.id, "riley")
        let page = try await repo.request(APIRequest("feed", text: "{}"))
        XCTAssertEqual(
            try JSONDecoder().decode(BackendPage.self, from: page.payload).listings.count, 30)
    }
    func testSwiftHTTPSerializationAndStableErrors() async throws {
        let payload = try bootstrap("a")
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/database/test/call/api")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"), "Bearer private-token-a")
            let body = request.httpBody ?? Data()
            if !body.isEmpty {
                let values = try JSONSerialization.jsonObject(with: body) as! [[String: Any]]
                XCTAssertNotNil(values[0]["operation_id"])
                XCTAssertNil(values[0]["operationId"])
            }
            return try self.wire(payload)
        }
        let repo = repository("a")
        let response = try await repo.request(APIRequest("bootstrap"))
        XCTAssertEqual(
            try JSONDecoder().decode(BackendBootstrap.self, from: response.payload).user.id, "a")
        StubURLProtocol.handler = { _ in try self.wire(Data("{}".utf8), error: "unavailable") }
        do {
            _ = try await repo.request(APIRequest("reserve", resourceID: "straw", write: true))
            XCTFail("Must reject")
        } catch RepositoryError.server(let code) { XCTAssertEqual(code, "unavailable") }
    }
    func testSessionProviderRefreshAndAccountBoundary() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let payload = try bootstrap("a")
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer refreshed")
            return try self.wire(payload)
        }
        let repo = HTTPRepository(
            server: URL(string: "https://example.com")!, database: "test",
            session: BackendSession(userId: "a", token: "expired"), cacheRoot: folder,
            network: URLSession(configuration: configuration),
            sessionProvider: { BackendSession(userId: "a", token: "refreshed") })
        _ = try await repo.request(APIRequest("bootstrap"))
        let wrong = HTTPRepository(
            server: URL(string: "https://example.com")!, database: "test",
            session: BackendSession(userId: "a", token: "expired"), cacheRoot: folder,
            network: URLSession(configuration: configuration),
            sessionProvider: { BackendSession(userId: "b", token: "other") })
        do {
            _ = try await wrong.request(APIRequest("bootstrap"))
            XCTFail("Cross-account session must not be sent")
        } catch RepositoryError.server(let code) { XCTAssertEqual(code, "unauthorized") }
        let store = AppStore(service: DemoService(delayNanoseconds: 0), fixtureMode: false)
        await store.connect(repo)
        store.disconnectBackend()
        XCTAssertTrue(store.accountID.isEmpty)
        XCTAssertTrue(store.catalog.isEmpty)
        XCTAssertTrue(store.receipts.isEmpty)
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertFalse(store.online)
    }
    func testAccountScopedCachesAndOutboxes() async throws {
        let a = repository("a")
        let b = repository("b")
        let payload = try bootstrap("a")
        StubURLProtocol.handler = { _ in try self.wire(payload) }
        _ = try await a.request(APIRequest("bootstrap"))
        let data = await b.cached(APIRequest("bootstrap").cacheKey, maxAge: .infinity)
        XCTAssertNil(data)
        let pending = APIRequest("send", resourceID: "maya", text: "hello", write: true)
        try await a.enqueue(pending)
        try await a.enqueue(pending)
        let queueA = await a.pending()
        let queueB = await b.pending()
        XCTAssertEqual(queueA.count, 1)
        XCTAssertEqual(queueB.count, 0)
        let restarted = repository("a")
        let restartedQueue = await restarted.pending()
        XCTAssertEqual(restartedQueue[0].operationId, pending.operationId)
        try await a.clearCache()
        let clearedA = await a.pending()
        let unchangedB = await b.pending()
        XCTAssertEqual(clearedA.count, 0)
        XCTAssertTrue(unchangedB.isEmpty)
    }
    func testOutboxRetriesKeepOperationIDAndDoNotDuplicate() async throws {
        let repo = repository("a")
        let pending = APIRequest("send", resourceID: "maya", text: "hello", write: true)
        try await repo.enqueue(pending)
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            try await repo.synchronize()
            XCTFail("Offline must fail")
        } catch {}
        let retryQueue = await repo.pending()
        XCTAssertEqual(retryQueue.first?.operationId, pending.operationId)
        StubURLProtocol.handler = { _ in try self.wire(Data("{}".utf8)) }
        try await repo.synchronize()
        try await repo.synchronize()
        let completedQueue = await repo.pending()
        let requestCount = await repo.requestCount
        XCTAssertTrue(completedQueue.isEmpty)
        XCTAssertEqual(requestCount, 2)
    }
    func testRejectedOutboxMessageDoesNotBlockFavorites() async throws {
        let repo = repository("a")
        try await repo.enqueue(APIRequest("send", resourceID: "maya", text: "hello", write: true))
        try await repo.enqueue(APIRequest("favorite", resourceID: "straw", write: true))
        var calls = 0
        StubURLProtocol.handler = { _ in
            calls += 1
            return try self.wire(Data("{}".utf8), error: calls == 1 ? "not_found" : "")
        }
        try await repo.synchronize()
        let pending = await repo.pending()
        let failed = await repo.failed()
        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(failed.count, 1)
        XCTAssertEqual(calls, 2)
    }
    func testMetadataBudgetEvictsOversizedSnapshots() async throws {
        let repo = repository("a")
        let large = Data(repeating: 32, count: 21 * 1024 * 1024)
        StubURLProtocol.handler = { _ in try self.wire(large) }
        _ = try await repo.request(APIRequest("feed"))
        let cached = await repo.cached(APIRequest("feed").cacheKey, maxAge: .infinity)
        XCTAssertNil(cached)
    }
    func testBackendOfflineLaunchDoesNotFallBackToFixtures() async throws {
        let store = AppStore(service: DemoService(delayNanoseconds: 0))
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await store.connect(repository("a"))
        XCTAssertTrue(store.isBackend)
        XCTAssertFalse(store.online)
        XCTAssertTrue(store.catalog.isEmpty)
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertFalse(store.addToCart("straw"))
        XCTAssertTrue(store.cart.isEmpty)
    }
    func testMarketplaceRefreshFindsLaterPagesAndRemovesWithdrawnListings() async throws {
        let initial = try bootstrap("a")
        var updated = false
        var failLaterPage = false
        let encoder = JSONEncoder()
        StubURLProtocol.handler = { request in
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count < 0 { throw URLError(.cannotDecodeContentData) }
                    if count == 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            let body = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
            let query = body[0]
            if query["action"] as? String == "bootstrap" { return try self.wire(initial) }
            XCTAssertEqual(query["action"] as? String, "feed")
            let first = (query["cursor"] as? String ?? "").isEmpty
            if !first && failLaterPage { throw URLError(.notConnectedToInternet) }
            let id = first ? (updated ? "bread" : "straw") : (updated ? "gran" : "bread")
            let page = BackendPage(
                listings: MockCatalog.listings.filter { $0.id == id },
                sellers: MockCatalog.sellers, cursor: first ? "next" : "")
            return try self.wire(encoder.encode(page))
        }
        let store = AppStore(service: DemoService(delayNanoseconds: 0))
        await store.connect(repository("a"))
        XCTAssertEqual(Set(store.catalog.map(\.id)), ["straw", "bread"])
        updated = true
        await store.refreshMarketplace()
        XCTAssertEqual(Set(store.catalog.map(\.id)), ["bread", "gran"])
        XCTAssertTrue(store.online)
        XCTAssertTrue(store.feedCursor.isEmpty)
        updated = false
        failLaterPage = true
        await store.refreshMarketplace()
        XCTAssertEqual(Set(store.catalog.map(\.id)), ["bread", "gran"])
        XCTAssertFalse(store.online)
    }
    func testSwitchImmediatelyClearsPreviousPrivateState() async throws {
        let store = AppStore(service: DemoService(delayNanoseconds: 0))
        store.addToCart("straw")
        store.savedIDs.insert("straw")
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await store.connect(repository("b"))
        XCTAssertEqual(store.accountID, "b")
        XCTAssertTrue(store.cart.isEmpty)
        XCTAssertTrue(store.savedIDs.isEmpty)
        XCTAssertTrue(store.receipts.isEmpty)
        XCTAssertTrue(store.messages.isEmpty)
    }
    func testPlannerIncludesUnfamiliarSellersAndMultipleLocations() {
        let original = MockCatalog.listings[0]
        func item(_ id: String, _ location: String) -> Listing {
            Listing(
                id: id, name: original.name, price: 250, retail: 649, distance: 1,
                freshness: .fresh,
                pickup: "Tonight", updated: "", stale: false, sellerID: "unfamiliar",
                category: "Produce", quantity: "1 package",
                weight: 1, opened: false, storage: "Cold", allergens: "None", purchased: "Today",
                receipt: false, vegetarian: true, prepared: false,
                windows: [
                    PickupWindow(
                        id: id, locationID: location, start: 0, end: 9_999_999_999_999,
                        timezone: "UTC")
                ])
        }
        let seller = Seller(
            id: "unfamiliar", name: "New Seller", rating: 0, pickups: 0, responds: "",
            student: false, area: "Linden Park", latitude: 42.281, longitude: -83.741)
        let items = [item("1", "a"), item("2", "a"), item("3", "b")]
        let plan = PickupPlanner.build(
            items: items, sellers: [seller], origin: GeoPoint(latitude: 42.28, longitude: -83.74),
            start: 1000)
        XCTAssertEqual(plan.stops.count, 2)
        XCTAssertEqual(plan.totals.count, 3)
        XCTAssertEqual(plan.stops.map(\.id), ["unfamiliar:a", "unfamiliar:b"])
    }
}
