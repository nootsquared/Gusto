import Foundation
import Observation

/// One presentation store for connected and fixture modes. Views own transient input.
@MainActor @Observable public final class AppStore {
    private var browseOrigin: (latitude: Double, longitude: Double)?
    public var catalog: [Listing] = MockCatalog.listings
    public private(set) var sellers: [Seller] = MockCatalog.sellers
    public private(set) var isBackend = false
    public private(set) var online = false
    public private(set) var accountID = "fixture"
    public private(set) var inventory: [InventoryFood] = []
    public private(set) var storageReadings: [StorageReading] = []
    public private(set) var inventoryLoading = false
    public private(set) var profileName = "Priya S."
    public private(set) var profileAvatar: String?
    public private(set) var pickupRequests: [SellerPickupRequest] = []
    public private(set) var ownListings: [Listing] = []
    public private(set) var sales: [Receipt] = []
    public private(set) var morePurchases = false
    public private(set) var moreSales = false
    public private(set) var historyLoading = false
    public private(set) var monthly: [MonthlyImpact] = []
    public private(set) var preferences: BackendPreferences?
    public private(set) var follows: [BackendFollow] = []
    public private(set) var conversations: [BackendConversation] = []
    public private(set) var feedCursor = ""
    public private(set) var searchResults: [Listing] = []
    public private(set) var searchCursor = ""
    @ObservationIgnored private var searchSpec = ""
    @ObservationIgnored private var searchPaging = false
    public private(set) var backendBusy = false
    public var activeChat: String?
    @ObservationIgnored private var repository: (any GustoRepository)?
    @ObservationIgnored private var searchGeneration = UUID()
    @ObservationIgnored private var lastRefresh = Date.distantPast
    @ObservationIgnored private var lastFeedRefresh = Date.distantPast
    @ObservationIgnored private var serverOffset: Double = 0
    public private(set) var feedLoading = false
    @ObservationIgnored private var messageSequences: [String: Int] = [:]
    public private(set) var cart: [String] = []
    public var filters = Filters()
    public var query = ""
    public var savedIDs: Set<String> = []
    public private(set) var checkingIDs: Set<String> = []
    public private(set) var plan: PickupPlan?
    public private(set) var coordinating = false
    public private(set) var counterSellerID: String?
    public private(set) var phase: RunPhase = .idle
    public private(set) var stopIndex = 0
    public private(set) var receipts: [Receipt] = []
    public private(set) var runReceipts: [Receipt] = []
    private static var initialMessages: [String: [ChatMessage]] {
        [
            "maya": [
                ChatMessage("Hi! Still available?", outgoing: true),
                ChatMessage("Yes! Picked them Thursday, kept cold."),
                ChatMessage("Porch is open, see you at 4:15!"),
            ]
        ]
    }
    public private(set) var messages: [String: [ChatMessage]] = AppStore.initialMessages
    public private(set) var typingSellers: Set<String> = []
    public struct IncomingNotification: Identifiable, Sendable {
        public let id: String
        public let senderID: String
        public let title: String
        public let body: String
    }
    public private(set) var incomingNotifications: [IncomingNotification] = []
    @ObservationIgnored private var notificationAccount = ""
    @ObservationIgnored private var notificationBaselineLoaded = false
    @ObservationIgnored private var observedSequences: [String: Int] = [:]
    public var incomingNotification: IncomingNotification? { incomingNotifications.first }
    public func dismissIncomingNotification() {
        if !incomingNotifications.isEmpty { incomingNotifications.removeFirst() }
    }
    public var unreadMessageCount: Int { conversations.reduce(0) { $0 + ($1.unreadCount ?? 0) } }
    @ObservationIgnored private var inventoryRevision = 0
    public var notice: String?
    @ObservationIgnored public let service: DemoService
    @ObservationIgnored private var planGeneration = UUID()
    @ObservationIgnored private var sessionGeneration = UUID()
    @ObservationIgnored private var sendCounts: [String: Int] = [:]

    public init(service: DemoService = DemoService(), fixtureMode: Bool = true) {
        self.service = service
        if !fixtureMode { enterBackendMode() }
    }
    public var runActive: Bool { phase != .idle && phase != .finished }
    public var cartItems: [Listing] { cart.compactMap { id in catalog.first { $0.id == id } } }
    public var cartTotals: Totals { Totals(cartItems) }
    public var cartGroups: [PickupStop] {
        if !isBackend { return PickupPlanner.build(items: cartItems).stops }
        let groups = Dictionary(grouping: cartItems, by: \.sellerID)
        return groups.keys.sorted().map { id in
            PickupStop(seller: seller(id), items: groups[id] ?? [], minute: 0)
        }
    }
    public var currentStop: PickupStop? {
        guard let plan, plan.stops.indices.contains(stopIndex) else { return nil }
        return plan.stops[stopIndex]
    }
    public var earnings: Int { monthly.reduce(0) { $0 + $1.earnings } }
    public var impact: Totals {
        if !isBackend { return Totals(receipts.flatMap(\.items)) }
        let rows = monthly.filter { $0.mode == "demo" }
        var totals = Totals()
        totals.count = rows.reduce(0) { $0 + $1.items }
        totals.pounds = Double(rows.reduce(0) { $0 + $1.grams }) / 453.59237
        totals.pay = receipts.reduce(0) { $0 + $1.paid }
        totals.retail = totals.pay + rows.reduce(0) { $0 + $1.saved }
        return totals
    }
    public var runImpact: Totals { Totals(runReceipts.flatMap(\.items)) }
    public func listing(_ id: String) -> Listing? { catalog.first { $0.id == id } }
    public func seller(_ id: String) -> Seller {
        sellers.first { $0.id == id }
            ?? Seller(
                id: id, name: "Unknown seller", rating: 0, pickups: 0, responds: "", student: false,
                area: "", latitude: 42.28, longitude: -83.74)
    }
    public func pinnedListing(for sellerID: String) -> Listing? {
        plan?.stops.first { $0.id == sellerID }?.items.first
            ?? cartItems.first { $0.sellerID == sellerID }
            ?? catalog.first { $0.sellerID == sellerID }
    }

    @discardableResult public func addToCart(_ id: String) -> Bool {
        if isBackend {
            if listing(id) != nil { launchWrite("add_cart", id: id) }
            return false
        }
        guard !runActive, let item = listing(id), item.available, !cart.contains(id) else {
            return false
        }
        cart.append(id)
        invalidatePlan()
        notice = "\(item.name) added to cart"
        return true
    }
    public func remove(_ id: String) {
        if isBackend {
            launchWrite("release", id: id)
            return
        }
        guard !runActive else { return }
        cart.removeAll { $0 == id }
        invalidatePlan()
    }
    private func invalidatePlan() {
        planGeneration = UUID()
        plan = nil
        coordinating = false
        counterSellerID = nil
    }
    public func confirmCartAndPlan() async -> Bool {
        if !runActive, let plan, plan.stops.contains(where: { $0.status == .confirmed }) {
            return true
        }
        guard !runActive, !cart.isEmpty else { return false }
        if isBackend {
            let confirmed = await backendWrite("plan", text: pickupPlanSpec())
            return confirmed && plan != nil
        }
        makePlan()
        return plan != nil
    }
    private func pickupPlanSpec(order: [String]? = nil) -> String {
        var values: [String: Any] = ["mode": "Fastest"]
        if let origin = browseOrigin {
            values["latitude"] = origin.latitude
            values["longitude"] = origin.longitude
        }
        if let order { values["order"] = order }
        return (try? JSONSerialization.data(withJSONObject: values)).map {
            String(decoding: $0, as: UTF8.self)
        } ?? "{}"
    }
    public func movePickupStop(_ id: String, by offset: Int) async {
        guard let current = plan, current.stops.allSatisfy({ $0.status == .unconfirmed }),
            let index = current.stops.firstIndex(where: { $0.id == id }),
            current.stops.indices.contains(index + offset), !backendBusy
        else { return }
        var stops = current.stops
        stops.swapAt(index, index + offset)
        if isBackend, let runID = current.serverID {
            await backendWrite(
                "reorder_plan", id: runID, text: pickupPlanSpec(order: stops.map(\.id)))
        } else {
            let times = current.stops.map(\.minute)
            for i in stops.indices { stops[i].minute = times[i] }
            plan?.stops = stops
        }
    }
    public func confirmSellerPickup(_ id: String) async {
        await backendWrite("confirm", id: id)
    }
    public func completeSellerHandoff(_ id: String) async {
        await backendWrite("handoff", id: id)
    }
    public func beginPickups() async -> Bool {
        if isBackend {
            guard let id = plan?.serverID, plan?.allConfirmed == true else { return false }
            return await backendWrite("start", id: id) && phase == .enroute
        }
        return startRun()
    }
    public func makePlan(mode: RouteMode = .fastest) {
        if isBackend {
            launchWrite("plan", text: pickupPlanSpec())
            return
        }
        guard !runActive else { return }
        planGeneration = UUID()
        coordinating = false
        counterSellerID = nil
        plan = PickupPlanner.build(items: cartItems.filter(\.available), mode: mode)
    }
    public func cancelPickupRequests() async -> Bool {
        guard phase == .idle, let existing = plan else { return false }
        if isBackend {
            guard let id = existing.serverID else { return false }
            return await backendWrite("cancel_pickup_requests", id: id)
        }
        planGeneration = UUID()
        coordinating = false
        counterSellerID = nil
        let itemIDs = Set(existing.stops.flatMap { $0.items.map(\.id) })
        cart.removeAll { itemIDs.contains($0) }
        plan = nil
        return true
    }
    public func coordinate() async {
        if isBackend {
            guard !coordinating, let id = plan?.serverID,
                plan?.stops.contains(where: { $0.status == .unconfirmed }) == true
            else { return }
            coordinating = true
            defer { coordinating = false }
            await backendWrite("coordinate", id: id)
            return
        }
        guard !coordinating, !runActive, let existing = plan, !existing.stops.isEmpty,
            !existing.allConfirmed
        else { return }
        coordinating = true
        let generation = planGeneration
        for stop in existing.stops {
            do { try await service.pause() } catch {
                if generation == planGeneration { coordinating = false }
                return
            }
            guard generation == planGeneration,
                let i = plan?.stops.firstIndex(where: { $0.id == stop.id })
            else { return }
            if stop.id == "nina" {
                plan?.stops[i].status = .waiting
                counterSellerID = stop.id
            } else {
                plan?.stops[i].status = .confirmed
            }
            messages[stop.id, default: []].append(
                ChatMessage(
                    stop.id == "nina"
                        ? "Could you come at \(laterTime(stop.minute, by: 9)) instead?"
                        : "Confirmed for \(stop.time). See you soon!"))
        }
        coordinating = false
    }
    private func laterTime(_ minute: Int, by delay: Int) -> String {
        let value = minute + delay
        return "\((value / 60) % 12):\(String(format: "%02d", value % 60))"
    }
    public func acceptCounter(alternative: Bool = false) {
        if isBackend {
            notice = "Schedule changes need the other participant’s approval."
            return
        }
        guard !runActive, let sellerID = counterSellerID, var updated = plan,
            let i = updated.stops.firstIndex(where: { $0.id == sellerID })
        else { return }
        PickupPlanner.shift(&updated, sellerID: sellerID, by: alternative ? 19 : 9)
        updated.stops[i].status = .confirmed
        plan = updated
        counterSellerID = nil
        messages[sellerID, default: []].append(
            ChatMessage("Confirmed for \(updated.stops[i].time).", outgoing: true))
    }
    @discardableResult public func startRun() -> Bool {
        if isBackend {
            if let id = plan?.serverID { launchWrite("start", id: id) }
            return false
        }
        guard !runActive, phase == .idle, plan?.allConfirmed == true else { return false }
        runReceipts = []
        stopIndex = 0
        phase = .enroute
        return true
    }
    public func delayStop(_ sellerID: String) {
        if isBackend {
            notice = "Send a schedule proposal in chat; seller approval is required."
            return
        }
        guard runActive, var updated = plan,
            let i = updated.stops.firstIndex(where: { $0.id == sellerID }), i >= stopIndex
        else { return }
        PickupPlanner.shift(&updated, sellerID: sellerID, by: 10)
        plan = updated
        messages[sellerID, default: []].append(
            ChatMessage(
                "Running 10 minutes late. See you at \(updated.stops[i].time).", outgoing: true))
        notice = "\(seller(sellerID).firstName) got your new time · route updated"
    }
    public func markArrival() async {
        guard phase == .enroute else { return }
        if isBackend {
            guard let id = currentStop?.serverID, await backendWrite("arrive", id: id) else { return }
            await backendWrite("announce", id: id)
        } else {
            arrive()
            await announceArrival()
        }
    }
    public func arrive() {
        if isBackend {
            if let id = currentStop?.serverID { launchWrite("arrive", id: id) }
            return
        }
        guard phase == .enroute else { return }
        phase = .arrived
    }
    public func announceArrival() async {
        if isBackend {
            if let id = currentStop?.serverID { await backendWrite("announce", id: id) }
            return
        }
        guard phase == .arrived, let stop = currentStop else { return }
        let generation = sessionGeneration
        phase = .waiting
        messages[stop.id, default: []].append(ChatMessage("I'm here", outgoing: true))
        do { try await service.pause() } catch {
            if generation == sessionGeneration { phase = .arrived }
            return
        }
        guard generation == sessionGeneration, phase == .waiting else { return }
        messages[stop.id, default: []].append(ChatMessage("Coming out now!"))
        phase = .verifying
    }
    public func verify() {
        if isBackend {
            if let id = currentStop?.serverID { launchWrite("verify", id: id) }
            return
        }
        guard phase == .verifying else { return }
        phase = .payment
    }
    public func reportIssue() {
        if isBackend {
            if let id = currentStop?.serverID {
                launchWrite("issue", id: id, text: "Condition issue")
            }
            return
        }
        guard phase == .verifying || phase == .arrived, let stop = currentStop else { return }
        plan?.stops[stopIndex].status = .skipped
        notice = "Issue recorded for \(stop.seller.firstName) · no demo charge"
        advance()
    }
    public func pay() async {
        if isBackend {
            if let id = currentStop?.serverID { await backendWrite("demo_payment", id: id) }
            return
        }
        guard phase == .payment, let stop = currentStop,
            !runReceipts.contains(where: { $0.seller.id == stop.id })
        else { return }
        let generation = sessionGeneration
        phase = .paying
        do { try await service.pause() } catch {
            if generation == sessionGeneration { phase = .payment }
            return
        }
        guard generation == sessionGeneration, phase == .paying else { return }
        let receipt = Receipt(
            id: UUID().uuidString, seller: stop.seller, items: stop.items, paid: stop.totals.pay)
        runReceipts.append(receipt)
        receipts.append(receipt)
        plan?.stops[stopIndex].status = .paid
        for item in stop.items {
            if let i = catalog.firstIndex(where: { $0.id == item.id }) {
                catalog[i].available = false
            }
            cart.removeAll { $0 == item.id }
        }
        phase = .rescued
    }
    public func continueRun() {
        if isBackend {
            if let id = currentStop?.serverID { launchWrite("advance", id: id) }
            return
        }
        guard phase == .rescued else { return }
        advance()
    }
    private func advance() {
        if stopIndex + 1 < (plan?.stops.count ?? 0) {
            stopIndex += 1
            phase = .enroute
        } else {
            phase = .finished
        }
    }
    public func finishRun() {
        if isBackend {
            if let id = plan?.serverID { launchWrite("finish", id: id) }
            return
        }
        guard phase == .finished else { return }
        phase = .idle
        cart = []
        invalidatePlan()
    }
    public func freshCheck(_ id: String) async {
        if isBackend {
            if await backendWrite("freshness", id: id) {
                notice = "Fresh Check requested · message sent to seller"
            }
            return
        }
        guard !checkingIDs.contains(id), let item = listing(id), item.available else { return }
        let generation = sessionGeneration
        checkingIDs.insert(id)
        defer { if generation == sessionGeneration { checkingIDs.remove(id) } }
        do { try await service.pause() } catch { return }
        guard generation == sessionGeneration else { return }
        if let i = catalog.firstIndex(where: { $0.id == id }) {
            catalog[i].updated = "just now"
            catalog[i].stale = false
            notice = "\(seller(item.sellerID).firstName) reconfirmed condition · mock Fresh Check"
        }
    }
    public func send(_ text: String, to sellerID: String) async {
        if isBackend {
            await queueMessage(text, to: sellerID)
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let generation = sessionGeneration
        messages[sellerID, default: []].append(ChatMessage(trimmed, outgoing: true))
        sendCounts[sellerID, default: 0] += 1
        typingSellers.insert(sellerID)
        defer {
            if generation == sessionGeneration {
                sendCounts[sellerID, default: 1] -= 1
                if sendCounts[sellerID] == 0 { typingSellers.remove(sellerID) }
            }
        }
        do { try await service.pause() } catch { return }
        guard generation == sessionGeneration else { return }
        messages[sellerID, default: []].append(ChatMessage(service.reply(to: trimmed)))
    }
    /// The seeded catalog contains numbered copies of the same bundled products.
    /// Choose the closest sample offer per photo; never collapse genuine user listings.
    public func distinctSampleListings(_ items: [Listing]) -> [Listing] {
        let samplePhotos = Set(MockCatalog.listings.map(\.id))
        var best: [String: Listing] = [:]
        var keys: [String] = []
        for item in items {
            let sample = item.id.hasPrefix("listing-") || samplePhotos.contains(item.id)
            let key = sample && samplePhotos.contains(item.image) ? "sample:\(item.image)" : item.id
            if best[key] == nil { keys.append(key) }
            if let previous = best[key],
                previous.distance < item.distance
                    || (previous.distance == item.distance && previous.price <= item.price)
            {
                continue
            }
            var display = item
            if sample {
                display.name = item.name.replacingOccurrences(
                    of: #" · package \d+$"#, with: "", options: .regularExpression)
            }
            best[key] = display
        }
        return keys.compactMap { best[$0] }
    }
    public func visibleListings(query text: String? = nil) -> [Listing] {
        if isBackend, let text, !text.isEmpty {
            return searchResults.filter {
                $0.sellerID != accountID && filters.accepts($0, sellers: sellers)
            }
        }
        var results = catalog.filter {
            $0.sellerID != accountID && filters.accepts($0, sellers: sellers)
        }
        let q = (text ?? query).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return results }
        var recognized = false
        if q.contains("snack") {
            results = results.filter { $0.category == "Snacks" }
            recognized = true
        }
        if q.contains("breakfast") {
            results = results.filter {
                ["Breakfast", "Dairy"].contains($0.category) || $0.id == "bana"
            }
            recognized = true
        }
        if q.contains("dinner") {
            results = results.filter { $0.category == "Prepared" }
            recognized = true
        }
        if q.contains("veg") {
            results = results.filter(\.vegetarian)
            recognized = true
        }
        if q.contains("unopened") {
            results = results.filter { !$0.opened }
            recognized = true
        }
        if q.contains("north campus") {
            results = results.filter { $0.sellerID == "nina" }
            recognized = true
        }
        if q.contains("dairy") {
            results = results.filter { $0.category == "Dairy" }
            recognized = true
        }
        if q.contains("tonight") {
            results = results.filter {
                $0.pickup.lowercased().contains("tonight") || $0.pickup.lowercased().contains("pm")
            }
            recognized = true
        }
        if let range = q.range(of: #"under\s*\$?\d+(\.\d+)?"#, options: .regularExpression) {
            let number = q[range].filter { $0.isNumber || $0 == "." }
            if let cap = Double(number) {
                results = results.filter { $0.price < Int((cap * 100).rounded()) }
                recognized = true
            }
        } else if q.contains("cheap") {
            results = results.filter { $0.price < 300 }
            recognized = true
        }
        if !recognized {
            results = results.filter {
                $0.name.lowercased().contains(q) || $0.category.lowercased().contains(q)
            }
        }
        return results
    }

    @discardableResult public func publish(
        name: String, price: Int, freshness: Freshness, pickup: String, confirmations: Int
    ) -> Bool {
        if isBackend { return false }
        guard confirmations == 4, price > 0, price < 899,
            !name.trimmingCharacters(in: .whitespaces).isEmpty,
            let base = catalog.first(where: { $0.id == "gran" })
        else { return false }
        var item = Listing(
            id: "my-granola", name: name, price: price, retail: 899, distance: 0.1,
            freshness: freshness, pickup: pickup, updated: "just now", stale: false,
            sellerID: "nina", category: "Breakfast", quantity: base.quantity, weight: base.weight,
            opened: false, storage: "Pantry", allergens: "Oats, almonds", purchased: "Today",
            receipt: false, vegetarian: true, prepared: false)
        item.available = true
        catalog.removeAll { $0.id == item.id }
        catalog.insert(item, at: 0)
        return true
    }
    public func resetDemo() {
        if isBackend {
            Task {
                guard let repository else { return }
                try? await repository.clearCache()
                await connect(repository)
            }
            return
        }
        sessionGeneration = UUID()
        planGeneration = UUID()
        catalog = MockCatalog.listings
        inventory = []
        storageReadings = []
        ownListings = []
        cart = []
        filters = Filters()
        query = ""
        plan = nil
        phase = .idle
        stopIndex = 0
        receipts = []
        runReceipts = []
        counterSellerID = nil
        coordinating = false
        savedIDs = []
        notice = nil
        messages = Self.initialMessages
        checkingIDs = []
        typingSellers = []
        sendCounts = [:]
    }
}

extension AppStore {
    /// Switches clear all account data synchronously before the first await.
    public func connect(_ newRepository: any GustoRepository) async {
        sessionGeneration = UUID()
        let generation = sessionGeneration
        repository = newRepository
        isBackend = true
        online = false
        backendBusy = false
        inventory = []
        storageReadings = []
        inventoryLoading = false
        accountID = newRepository.accountID
        profileName = "Loading account…"
        profileAvatar = nil
        pickupRequests = []
        catalog = []
        sellers = []
        cart = []
        savedIDs = []
        messages = [:]
        receipts = []
        sales = []
        morePurchases = false
        moreSales = false
        historyLoading = false
        monthly = []
        ownListings = []
        conversations = []
        incomingNotifications = []
        observedSequences = [:]
        notificationBaselineLoaded = false
        follows = []
        preferences = nil
        runReceipts = []
        plan = nil
        phase = .idle
        stopIndex = 0
        feedCursor = ""
        activeChat = nil
        messageSequences = [:]
        lastFeedRefresh = .distantPast
        searchResults = []
        checkingIDs = []
        typingSellers = []
        notice = nil
        feedLoading = false
        searchGeneration = UUID()
        lastRefresh = .distantPast
        if let data = await newRepository.cached(
            APIRequest("bootstrap").cacheKey, maxAge: .infinity),
            generation == sessionGeneration,
            let snapshot = try? JSONDecoder().decode(BackendBootstrap.self, from: data),
            snapshot.user.id == accountID
        {
            apply(snapshot)
        }
        let feed = APIRequest("feed", text: "{}")
        if let data = await newRepository.cached(feed.cacheKey, maxAge: .infinity),
            generation == sessionGeneration,
            let page = try? JSONDecoder().decode(BackendPage.self, from: data)
        {
            merge(page.listings)
            mergeSellers(page.sellers)
            feedCursor = page.cursor
        }
        guard generation == sessionGeneration else { return }
        await refreshBackend(force: true)
        // Maintain the canonical first-page cache used by account-scoped offline launch.
        await loadNextPage(first: true)
        await refreshMarketplace()
    }
    public func disconnectBackend() {
        sessionGeneration = UUID()
        planGeneration = UUID()
        repository = nil
        inventory = []
        storageReadings = []
        inventoryLoading = false
        accountID = ""
        isBackend = true
        online = false
        backendBusy = false
        catalog = []
        sellers = []
        cart = []
        savedIDs = []
        messages = [:]
        receipts = []
        sales = []
        morePurchases = false
        moreSales = false
        historyLoading = false
        monthly = []
        ownListings = []
        conversations = []
        incomingNotifications = []
        observedSequences = [:]
        notificationBaselineLoaded = false
        follows = []
        preferences = nil
        runReceipts = []
        plan = nil
        phase = .idle
        stopIndex = 0
        feedCursor = ""
        activeChat = nil
        messageSequences = [:]
        lastFeedRefresh = .distantPast
        searchResults = []
        checkingIDs = []
        typingSellers = []
        notice = nil
        feedLoading = false
        searchGeneration = UUID()
        lastRefresh = .distantPast
        profileName = "Sign in to Gusto"
        profileAvatar = nil
        pickupRequests = []
    }
    public func enterBackendMode() {
        // First launch without a provisioned session must never display fixture product data.
        isBackend = true
        catalog = []
        sellers = []
        messages = [:]
        cart = []
        receipts = []
        profileName = "Connect local demo"
        online = false
    }
    /// Offer a wider local area only when it can reveal food matching the other filters.
    public var suggestedBrowseRadius: Double? {
        guard visibleListings(query: "").isEmpty else { return nil }
        for radius in [1.5, 3.0] where radius > filters.distance {
            var expanded = filters
            expanded.distance = radius
            if catalog.contains(where: { expanded.accepts($0, sellers: sellers) }) {
                return radius
            }
        }
        return nil
    }
    public func updateBrowseLocation(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite,
            (-90...90).contains(latitude), (-180...180).contains(longitude)
        else { return }
        browseOrigin = (latitude, longitude)
        recalculateBrowseDistances()
    }
    private func recalculateBrowseDistances() {
        guard let origin = browseOrigin else { return }
        func adjusted(_ item: Listing) -> Listing {
            guard let seller = sellers.first(where: { $0.id == item.sellerID }) else { return item }
            var result = item
            let rad = Double.pi / 180
            let latitude = item.latitude ?? seller.latitude
            let longitude = item.longitude ?? seller.longitude
            let dLat = (latitude - origin.latitude) * rad
            let dLon = (longitude - origin.longitude) * rad
            let a =
                pow(sin(dLat / 2), 2)
                + cos(origin.latitude * rad) * cos(latitude * rad) * pow(sin(dLon / 2), 2)
            result.distance = 3958.7613 * 2 * asin(sqrt(min(1, max(0, a))))
            return result
        }
        catalog = catalog.map(adjusted)
        searchResults = searchResults.map(adjusted)
    }
    private func merge(_ items: [Listing]) {
        for item in items {
            if let i = catalog.firstIndex(where: { $0.id == item.id }) {
                if (item.version ?? 0) >= (catalog[i].version ?? 0) { catalog[i] = item }
            } else {
                catalog.append(item)
            }
        }
    }
    private func mergeSellers(_ items: [Seller]) {
        for item in items {
            if let i = sellers.firstIndex(where: { $0.id == item.id }) {
                sellers[i] = item
            } else {
                sellers.append(item)
            }
        }
        recalculateBrowseDistances()
    }
    private func apply(_ snapshot: BackendBootstrap) {
        profileName = snapshot.user.name
        profileAvatar = snapshot.user.avatar
        pickupRequests = snapshot.pickupRequests ?? []
        preferences = snapshot.preferences
        cart = snapshot.cart
        savedIDs = Set(snapshot.favorites)
        merge(snapshot.cartListings + snapshot.savedListings + snapshot.ownListings)
        sellers = snapshot.sellers
        ownListings = snapshot.ownListings
        if notificationAccount != accountID {
            notificationAccount = accountID
            observedSequences = [:]
            notificationBaselineLoaded = false
            incomingNotifications = []
        }
        for conversation in snapshot.conversations {
            let other =
                conversation.buyerId == accountID ? conversation.sellerId : conversation.buyerId
            let sequence = conversation.sequence ?? 0
            // Baseline old conversations on login; only announce new incoming activity.
            if let previous = observedSequences[conversation.id], sequence > previous,
                conversation.lastSenderId != accountID, (conversation.unreadCount ?? 0) > 0,
                activeChat != other
            {
                incomingNotifications.append(
                    IncomingNotification(
                        id: "\(conversation.id):\(sequence)", senderID: other,
                        title: snapshot.sellers.first { $0.id == other }?.name ?? "New message",
                        body: conversation.summary))
            } else if observedSequences[conversation.id] == nil && notificationBaselineLoaded,
                conversation.lastSenderId != accountID, (conversation.unreadCount ?? 0) > 0,
                activeChat != other
            {
                incomingNotifications.append(
                    IncomingNotification(
                        id: "\(conversation.id):\(sequence)", senderID: other,
                        title: snapshot.sellers.first { $0.id == other }?.name ?? "New message",
                        body: conversation.summary))
            }
            observedSequences[conversation.id] = max(
                observedSequences[conversation.id] ?? 0, sequence)
        }
        notificationBaselineLoaded = true
        conversations = snapshot.conversations
        follows = snapshot.follows ?? []
        let latestPurchases = snapshot.receipts.map(\.receipt)
        let latestSales = snapshot.sales.map(\.receipt)
        receipts =
            latestPurchases
            + receipts.filter { old in !latestPurchases.contains { $0.id == old.id } }
        sales = latestSales + sales.filter { old in !latestSales.contains { $0.id == old.id } }
        morePurchases = snapshot.receipts.count == 30
        moreSales = snapshot.sales.count == 30
        monthly = snapshot.monthly
        plan = snapshot.run?.plan
        stopIndex = snapshot.run?.currentStop ?? 0
        phase = RunPhase(rawValue: snapshot.run?.phase ?? "idle") ?? .idle
        if let run = snapshot.run {
            let paidIDs = Set(
                run.stops.filter { $0.status == "paid" }.flatMap { $0.items.map(\.id) })
            runReceipts = receipts.filter { $0.items.contains { paidIDs.contains($0.id) } }
        } else {
            runReceipts = []
        }
        recalculateBrowseDistances()
    }
    public func loadHistory(selling: Bool) async {
        guard let repository, !historyLoading else { return }
        historyLoading = true
        let generation = sessionGeneration
        defer { if generation == sessionGeneration { historyLoading = false } }
        var request = APIRequest("history")
        request.enabled = selling
        request.cursor = String(selling ? sales.count : receipts.count)
        do {
            let response = try await repository.request(request)
            let page = try JSONDecoder().decode(BackendHistoryPage.self, from: response.payload)
            guard generation == sessionGeneration else { return }
            let items = page.receipts.map(\.receipt)
            if selling {
                sales += items.filter { item in !sales.contains { $0.id == item.id } }
                moreSales = !page.cursor.isEmpty
            } else {
                receipts += items.filter { item in !receipts.contains { $0.id == item.id } }
                morePurchases = !page.cursor.isEmpty
            }
        } catch {
            guard generation == sessionGeneration else { return }
            notice = error.localizedDescription
        }
    }
    public func refreshBackend(force: Bool = false) async {
        guard let repository, force || Date().timeIntervalSince(lastRefresh) > 30 else { return }
        let generation = sessionGeneration
        do {
            try await repository.synchronize()
            let response = try await repository.request(APIRequest("bootstrap"))
            let snapshot = try JSONDecoder().decode(BackendBootstrap.self, from: response.payload)
            guard snapshot.user.id == accountID else {
                throw RepositoryError.server("unauthorized")
            }
            guard generation == sessionGeneration else { return }
            serverOffset = response.serverTime - Date().timeIntervalSince1970 * 1000
            apply(snapshot)
            online = true
            if notice?.hasPrefix("Offline ·") == true { notice = nil }
            lastRefresh = Date()
            await restorePendingMessages()
        } catch {
            guard generation == sessionGeneration else { return }
            #if DEBUG
                NSLog("Gusto bootstrap failed: %@", String(describing: error))
            #endif
            online = false
            notice =
                catalog.isEmpty
                ? "Offline · check your connection to load food"
                : "Offline · showing cached food"
            for i in plan?.stops.indices ?? 0..<0 { plan?.stops[i].privateLocation = nil }
        }
    }
    /// Commit a complete snapshot so later pages, deletions and another seller's new posts appear.
    public func refreshMarketplace() async {
        guard let repository, !feedLoading else { return }
        let generation = sessionGeneration
        feedLoading = true
        defer { if generation == sessionGeneration { feedLoading = false } }
        var request = APIRequest("feed", text: "{}")
        if let origin = browseOrigin {
            guard
                let spec = try? JSONSerialization.data(
                    withJSONObject: [
                        "latitude": origin.latitude, "longitude": origin.longitude, "distance": 100,
                    ], options: .sortedKeys)
            else { return }
            request.text = String(decoding: spec, as: UTF8.self)
        }
        request.value = 50
        var listings: [Listing] = []
        var pageSellers: [Seller] = []
        var cursors: Set<String> = []
        do {
            repeat {
                try Task.checkCancellation()
                let response = try await repository.request(request)
                guard generation == sessionGeneration else { return }
                let page = try JSONDecoder().decode(BackendPage.self, from: response.payload)
                listings += page.listings
                pageSellers += page.sellers
                request.cursor = page.cursor
                if !page.cursor.isEmpty && !cursors.insert(page.cursor).inserted {
                    throw RepositoryError.invalidResponse
                }
            } while !request.cursor.isEmpty
            // Keep cart/detail context, but an absent listing must stop appearing as purchasable.
            let publishedIDs = Set(listings.map(\.id))
            let ownIDs = Set(ownListings.map(\.id))
            let retained = catalog.filter {
                !publishedIDs.contains($0.id)
                    && (cart.contains($0.id) || ownIDs.contains($0.id))
            }.map { item in
                var unavailable = item
                unavailable.available = false
                return unavailable
            }
            catalog = retained
            merge(listings)
            mergeSellers(pageSellers)
            feedCursor = ""
            online = true
            lastFeedRefresh = Date()
            if notice == "Couldn't refresh food. Pull down to try again." { notice = nil }
        } catch is CancellationError {
            return
        } catch {
            if generation == sessionGeneration {
                online = false
                notice = "Couldn't refresh food. Pull down to try again."
            }
        }
    }
    public func loadNextPage(first: Bool = false) async {
        guard let repository, !feedLoading, first || !feedCursor.isEmpty else { return }
        feedLoading = true
        let generation = sessionGeneration
        defer { if generation == sessionGeneration { feedLoading = false } }
        var request = APIRequest("feed", text: "{}")
        request.cursor = first ? "" : feedCursor
        do {
            let response = try await repository.request(request)
            let page = try JSONDecoder().decode(BackendPage.self, from: response.payload)
            guard generation == sessionGeneration else { return }
            merge(page.listings)
            mergeSellers(page.sellers)
            feedCursor = page.cursor
            online = true
            lastFeedRefresh = Date()
        } catch { if generation == sessionGeneration { online = false } }
    }
    public func loadMapArea(latitude: Double, longitude: Double, radiusMiles: Double) async throws {
        guard let repository else { return }
        guard latitude.isFinite, longitude.isFinite, radiusMiles.isFinite,
            (-90...90).contains(latitude), (-180...180).contains(longitude), radiusMiles > 0
        else { return }
        let generation = sessionGeneration
        let spec: [String: Any] = [
            "query": "", "latitude": latitude, "longitude": longitude,
            "distance": radiusMiles, "maxPrice": filters.maxPrice,
            "vegetarian": filters.vegetarian, "unopened": filters.unopened,
            "freshness": filters.freshness.map(\.rawValue),
            "categories": Array(filters.categories), "minimumRating": filters.minimumRating,
            "tonight": filters.tonight, "tomorrow": filters.tomorrow,
        ]
        let data = try JSONSerialization.data(withJSONObject: spec, options: .sortedKeys)
        var request = APIRequest("search", text: String(decoding: data, as: UTF8.self))
        var seenCursors: Set<String> = []
        repeat {
            try Task.checkCancellation()
            let response = try await repository.request(request)
            guard generation == sessionGeneration else { throw CancellationError() }
            let page = try JSONDecoder().decode(BackendPage.self, from: response.payload)
            merge(page.listings)
            mergeSellers(page.sellers)
            request.cursor = page.cursor
        } while !request.cursor.isEmpty && seenCursors.insert(request.cursor).inserted
    }

    public func searchBackend(_ text: String) async {
        guard let repository else { return }
        searchGeneration = UUID()
        searchCursor = ""
        searchResults = []
        searchPaging = false
        let search = searchGeneration
        let generation = sessionGeneration
        do {
            try await Task.sleep(nanoseconds: 300_000_000)
            try Task.checkCancellation()
            var spec: [String: Any] = [
                "query": text, "maxPrice": filters.maxPrice, "distance": filters.distance,
                "vegetarian": filters.vegetarian, "unopened": filters.unopened,
                "freshness": filters.freshness.map(\.rawValue),
                "categories": Array(filters.categories), "minimumRating": filters.minimumRating,
                "tonight": filters.tonight, "tomorrow": filters.tomorrow,
            ]
            if let origin = browseOrigin {
                spec["latitude"] = origin.latitude
                spec["longitude"] = origin.longitude
            }
            let data = try JSONSerialization.data(withJSONObject: spec, options: .sortedKeys)
            let request = APIRequest("search", text: String(decoding: data, as: UTF8.self))
            if let cached = await repository.cached(request.cacheKey, maxAge: .infinity),
                search == searchGeneration, generation == sessionGeneration,
                let page = try? JSONDecoder().decode(BackendPage.self, from: cached)
            {
                searchResults = page.listings
            }
            let response = try await repository.request(request)
            try Task.checkCancellation()
            let page = try JSONDecoder().decode(BackendPage.self, from: response.payload)
            guard search == searchGeneration, generation == sessionGeneration else { return }
            searchResults = page.listings
            searchCursor = page.cursor
            searchSpec = request.text
            merge(page.listings)
            mergeSellers(page.sellers)
        } catch {
            if !(error is CancellationError), generation == sessionGeneration { online = false }
        }
    }
    public func loadSearchPage() async {
        guard let repository, !searchPaging, !searchCursor.isEmpty else { return }
        let generation = sessionGeneration
        let search = searchGeneration
        searchPaging = true
        defer { if search == searchGeneration { searchPaging = false } }
        var request = APIRequest("search", text: searchSpec)
        request.cursor = searchCursor
        do {
            let response = try await repository.request(request)
            let page = try JSONDecoder().decode(BackendPage.self, from: response.payload)
            guard generation == sessionGeneration, search == searchGeneration else { return }
            let ids = Set(searchResults.map(\.id))
            searchResults.append(contentsOf: page.listings.filter { !ids.contains($0.id) })
            searchCursor = page.cursor
            merge(page.listings)
            mergeSellers(page.sellers)
        } catch { if generation == sessionGeneration { notice = error.localizedDescription } }
    }
    public func loadDetail(_ id: String) async {
        guard let repository else { return }
        let generation = sessionGeneration
        struct Detail: Decodable {
            let listing: Listing
            let seller: Seller
        }
        do {
            let response = try await repository.request(APIRequest("detail", resourceID: id))
            let detail = try JSONDecoder().decode(Detail.self, from: response.payload)
            if generation == sessionGeneration {
                merge([detail.listing])
                mergeSellers([detail.seller])
                recalculateBrowseDistances()
            }
        } catch {}
    }
    private func launchWrite(_ action: String, id: String = "", text: String = "") {
        guard !backendBusy else { return }
        Task { await backendWrite(action, id: id, text: text) }
    }
    @discardableResult
    private func backendWrite(_ action: String, id: String = "", text: String = "") async -> Bool {
        guard let repository, !backendBusy else { return false }
        let generation = sessionGeneration
        backendBusy = true
        defer { if generation == sessionGeneration { backendBusy = false } }
        do {
            _ = try await repository.request(
                APIRequest(action, resourceID: id, text: text, write: true))
            guard generation == sessionGeneration else { return false }
            online = true
            await refreshBackend(force: true)
            if action == "add_cart" { notice = "Added to cart" }
            return generation == sessionGeneration
        } catch {
            if generation == sessionGeneration { notice = error.localizedDescription }
            return false
        }
    }
    public func publishListing(
        name: String, price: Int, freshness: Freshness, pickup: String, confirmations: Int
    ) async -> Bool {
        if !isBackend {
            return publish(
                name: name, price: price, freshness: freshness, pickup: pickup,
                confirmations: confirmations)
        }
        guard let repository, !backendBusy else {
            notice = "Connect an account before publishing"
            print(
                "Gusto publish rejected before HTTP:", repository == nil, confirmations,
                backendBusy)
            return false
        }
        let generation = sessionGeneration
        backendBusy = true
        defer { if generation == sessionGeneration { backendBusy = false } }
        struct Draft: Decodable {
            let id: String
            let version: Int
        }
        do {
            let response = try await repository.request(APIRequest("draft", write: true))
            let draft = try JSONDecoder().decode(Draft.self, from: response.payload)
            let data = try JSONSerialization.data(withJSONObject: [
                "title": name, "price": price, "freshness": freshness.rawValue,
            ])
            var edit = APIRequest(
                "edit", resourceID: draft.id, text: String(decoding: data, as: UTF8.self),
                write: true)
            edit.version = draft.version
            let edited = try await repository.request(edit)
            let updated = try JSONDecoder().decode(Draft.self, from: edited.payload)
            _ = try await repository.request(
                APIRequest("attach_demo_media", resourceID: draft.id, write: true))
            _ = try await repository.request(
                APIRequest("analysis", resourceID: draft.id, write: true))
            let window = ListingPublishPolicy.window(
                pickup,
                now: Date(
                    timeIntervalSince1970: (Date().timeIntervalSince1970 * 1000 + serverOffset)
                        / 1000))
            let safety = try JSONSerialization.data(withJSONObject: [
                "pickupStart": floor(window.start),
                "pickupEnd": floor(window.end),
            ])
            var publish = APIRequest(
                "publish", resourceID: draft.id, text: String(decoding: safety, as: UTF8.self),
                write: true)
            publish.version = updated.version
            _ = try await repository.request(publish)
            guard generation == sessionGeneration else { return false }
            await refreshBackend(force: true)
            return true
        } catch {
            NSLog("Gusto publish failed: %@", String(describing: error))
            if generation == sessionGeneration { notice = error.localizedDescription }
            return false
        }
    }
    public func toggleSaved(_ id: String) {
        let desired = !savedIDs.contains(id)
        if desired { savedIDs.insert(id) } else { savedIDs.remove(id) }
        guard let repository else { return }
        let generation = sessionGeneration
        var request = APIRequest("favorite", resourceID: id, write: true)
        request.enabled = desired
        Task {
            do {
                try await repository.enqueue(request)
                try await repository.synchronize()
            } catch {
                if generation == sessionGeneration {
                    notice = "Saved change pending synchronization"
                }
            }
        }
    }
    private func queueMessage(_ text: String, to sellerID: String) async {
        guard let repository, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let generation = sessionGeneration
        let request = APIRequest("send", resourceID: sellerID, text: text, write: true)
        do {
            try await repository.enqueue(request)
            guard generation == sessionGeneration else { return }
            messages[sellerID, default: []].append(
                ChatMessage(
                    text, outgoing: true, id: UUID(uuidString: request.operationId)!,
                    delivery: "pending"))
            try await repository.synchronize()
            await refreshBackend(force: true)
            await loadMessages(sellerID)
        } catch {
            if generation == sessionGeneration { notice = "Message pending · reconnect to send" }
        }
    }
    private func restorePendingMessages() async {
        guard let repository else { return }
        let generation = sessionGeneration
        let pending = await repository.pending()
        let failures = await repository.failed()
        guard generation == sessionGeneration else { return }
        for request in pending where request.action == "send" {
            guard let id = UUID(uuidString: request.operationId),
                !(messages[request.resourceId] ?? []).contains(where: { $0.id == id })
            else { continue }
            messages[request.resourceId, default: []].append(
                ChatMessage(request.text, outgoing: true, id: id, delivery: "pending"))
        }
        for request in failures where request.action == "send" {
            guard let id = UUID(uuidString: request.operationId) else { continue }
            if let index = messages[request.resourceId]?.firstIndex(where: { $0.id == id }) {
                messages[request.resourceId]?[index].delivery = "failed"
            } else {
                messages[request.resourceId, default: []].append(
                    ChatMessage(request.text, outgoing: true, id: id, delivery: "failed"))
            }
        }
        for request in pending where request.action == "favorite" {
            if request.enabled {
                savedIDs.insert(request.resourceId)
            } else {
                savedIDs.remove(request.resourceId)
            }
        }
    }
    public func loadMessages(_ otherID: String) async {
        guard let repository else { return }
        let generation = sessionGeneration
        let id = [accountID, otherID].sorted().joined(separator: ":")
        var request = APIRequest("messages", resourceID: id)
        request.cursor = messageSequences[otherID].map(String.init) ?? ""
        if let data = await repository.cached(request.cacheKey, maxAge: .infinity),
            generation == sessionGeneration,
            let page = try? JSONDecoder().decode(BackendMessages.self, from: data)
        {
            applyMessages(page, otherID: otherID)
        }
        do {
            let response = try await repository.request(request)
            let page = try JSONDecoder().decode(BackendMessages.self, from: response.payload)
            guard generation == sessionGeneration else { return }
            applyMessages(page, otherID: otherID)
            if activeChat == otherID
                && page.lastSequence > (conversation(with: otherID)?.lastRead ?? 0)
            {
                var read = APIRequest("mark_read", resourceID: id, write: true)
                read.value = page.lastSequence
                _ = try await repository.request(read)
                guard generation == sessionGeneration else { return }
                if let index = conversations.firstIndex(where: { $0.id == id }) {
                    conversations[index].lastRead = page.lastSequence
                    conversations[index].unreadCount = 0
                }
                incomingNotifications.removeAll { $0.senderID == otherID }
            }
        } catch {}
    }
    private static func messageUUID(_ id: String) -> UUID {
        if let uuid = UUID(uuidString: id) { return uuid }
        var first: UInt64 = 14_695_981_039_346_656_037
        var second: UInt64 = 1_099_511_628_211
        for byte in id.utf8 {
            first = (first ^ UInt64(byte)) &* 1_099_511_628_211
            second = (second ^ UInt64(byte)) &* 14_695_981_039_346_656_037
        }
        let hex = String(format: "%016llx%016llx", first, second)
        let chars = Array(hex)
        let formatted =
            String(chars[0..<8]) + "-" + String(chars[8..<12]) + "-" + String(chars[12..<16]) + "-"
            + String(chars[16..<20]) + "-" + String(chars[20..<32])
        return UUID(uuidString: formatted)!
    }
    private func applyMessages(_ page: BackendMessages, otherID: String) {
        let pending = (messages[otherID] ?? []).filter {
            $0.delivery == "pending" || $0.delivery == "failed"
        }
        messageSequences[otherID] = max(messageSequences[otherID] ?? 0, page.lastSequence)
        let incoming = page.messages.map {
            ChatMessage(
                $0.text, outgoing: $0.senderId == accountID,
                id: UUID(uuidString: $0.operationId) ?? Self.messageUUID($0.id))
        }
        let incomingIDs = Set(incoming.map(\.id))
        let previous = (messages[otherID] ?? []).filter {
            !incomingIDs.contains($0.id) && $0.delivery != "pending" && $0.delivery != "failed"
        }
        messages[otherID] = previous + incoming
        let committed = Set(messages[otherID, default: []].map(\.id))
        messages[otherID, default: []].append(
            contentsOf: pending.filter { !committed.contains($0.id) })
    }
    public func pollBackend() async {
        guard isBackend else { return }
        var failures = 0
        let generation = sessionGeneration
        while !Task.isCancelled && generation == sessionGeneration {
            let wait: Double =
                online
                ? 3
                : min(60, pow(2, Double(min(failures + 1, 6))))
            do {
                try await Task.sleep(
                    nanoseconds: UInt64((wait + Double.random(in: 0...0.25)) * 1_000_000_000))
            } catch { return }
            await refreshBackend(force: true)
            guard generation == sessionGeneration else { return }
            if online && Date().timeIntervalSince(lastFeedRefresh) >= 10 {
                await refreshMarketplace()
            }
            if let activeChat { await loadMessages(activeChat) }
            failures = online ? 0 : failures + 1
        }
    }
    public var messageSellers: [Seller] {
        if !isBackend { return sellers }
        return conversations.sorted { ($0.lastMessageAt ?? 0) > ($1.lastMessageAt ?? 0) }
            .compactMap { conversation in
                let id =
                    conversation.buyerId == accountID ? conversation.sellerId : conversation.buyerId
                return sellers.first { $0.id == id }
            }
    }
    public func conversation(with otherID: String) -> BackendConversation? {
        conversations.first { $0.buyerId == otherID || $0.sellerId == otherID }
    }
    public func messagePreview(for otherID: String) -> String {
        if let latest = messages[otherID]?.last, latest.delivery != nil { return latest.text }
        return conversation(with: otherID)?.summary ?? messages[otherID]?.last?.text
            ?? "Start a conversation"
    }
    public var personalizedListings: [Listing] {
        if !isBackend { return ["straw", "avo", "gran", "yog", "eggs"].compactMap(listing) }
        let followed = Set(follows.filter { $0.kind == "category" }.map(\.target))
        let purchased = Set(receipts.flatMap { $0.items.map(\.category) })
        let eligible = catalog.filter {
            filters.accepts($0, sellers: sellers)
                && (!(preferences?.vegetarian ?? false) || $0.vegetarian)
        }
        return Array(
            eligible.sorted { a, b in
                let scoreA =
                    (followed.contains(a.category) ? 2 : 0)
                    + (purchased.contains(a.category) ? 1 : 0)
                let scoreB =
                    (followed.contains(b.category) ? 2 : 0)
                    + (purchased.contains(b.category) ? 1 : 0)
                return scoreA == scoreB ? a.id < b.id : scoreA > scoreB
            }.prefix(10))
    }
    public var buyAgainListings: [Listing] {
        if !isBackend { return ["straw", "bana", "yog", "gran"].compactMap(listing) }
        let categories = Set(receipts.flatMap { $0.items.map(\.category) })
        return Array(catalog.filter { $0.available && categories.contains($0.category) }.prefix(10))
    }
}

extension AppStore {
    public func updateSmartAlerts(_ enabled: Bool) {
        guard let repository, let preferences else { return }
        var request = APIRequest("preferences", write: true)
        request.version = preferences.version
        request.enabled = enabled
        request.value = preferences.vegetarian ? 1 : 0
        let generation = sessionGeneration
        Task {
            do {
                _ = try await repository.request(request)
                if generation == sessionGeneration { await refreshBackend(force: true) }
            } catch { if generation == sessionGeneration { notice = error.localizedDescription } }
        }
    }
}

extension AppStore {
    public func setFollow(kind: String, target: String, enabled: Bool) {
        guard let repository else { return }
        var request = APIRequest("follow", resourceID: target, text: kind, write: true)
        request.enabled = enabled
        let generation = sessionGeneration
        Task {
            do {
                _ = try await repository.request(request)
                if generation == sessionGeneration { await refreshBackend(force: true) }
            } catch { if generation == sessionGeneration { notice = error.localizedDescription } }
        }
    }
}

extension AppStore {
    public func loadInventory() async {
        guard let repository, !inventoryLoading else { return }
        let generation = sessionGeneration
        inventoryLoading = true
        let revision = inventoryRevision
        defer { if generation == sessionGeneration { inventoryLoading = false } }
        do {
            let response = try await repository.request(APIRequest("inventory"))
            struct Snapshot: Decodable {
                let items: [InventoryFood]
                let readings: [StorageReading]
            }
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: response.payload)
            guard generation == sessionGeneration else { return }
            guard revision == inventoryRevision else { return }
            inventory = snapshot.items
            storageReadings = snapshot.readings
        } catch { if generation == sessionGeneration { notice = error.localizedDescription } }
    }
    public func analyzeFoodPhoto(_ photo: String) async throws -> FoodAnalysis {
        guard let repository else { throw RepositoryError.server("unauthorized") }
        let generation = sessionGeneration
        let response = try await repository.request(APIRequest("scan_analyze", text: photo))
        guard generation == sessionGeneration else { throw CancellationError() }
        return try JSONDecoder().decode(FoodAnalysis.self, from: response.payload)
    }
    public func trackInventoryFood(_ id: String, deviceID: String) async {
        if !isBackend {
            if let index = inventory.firstIndex(where: { $0.id == id }) {
                inventory[index].deviceID = deviceID
            }
            return
        }
        if await backendWrite("inventory_track", id: id, text: deviceID) { await loadInventory() }
    }
    public func ingestStorageSample(
        deviceID: String, temperature: Double, humidity: Double, light: Double
    ) async {
        guard let repository, temperature.isFinite, humidity.isFinite, light.isFinite else {
            return
        }
        let generation = sessionGeneration
        for item in inventory where item.deviceID == deviceID {
            guard generation == sessionGeneration else { return }
            do {
                let data = try JSONSerialization.data(withJSONObject: [
                    "deviceID": deviceID, "temperature": temperature, "humidity": humidity,
                    "light": light, "lightUnit": "raw",
                ])
                _ = try await repository.request(
                    APIRequest(
                        "sensor_reading", resourceID: item.id,
                        text: String(decoding: data, as: UTF8.self), write: true))
            } catch {
                // A stale measurement must not be replayed later with a new server timestamp.
                if generation == sessionGeneration {
                    notice = "Sensor history couldn't sync. Live readings are still on this phone."
                }
                return
            }
        }
        if generation == sessionGeneration { await loadInventory() }
    }
    public func saveInventoryFood(_ item: InventoryFood) async -> Bool {
        guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if !isBackend {
            inventory.removeAll { $0.id == item.id }
            inventory.insert(item, at: 0)
            return true
        }
        guard let repository, !backendBusy else { return false }
        let generation = sessionGeneration
        backendBusy = true
        defer { if generation == sessionGeneration { backendBusy = false } }
        do {
            let data = try JSONEncoder().encode(item)
            _ = try await repository.request(
                APIRequest(
                    "inventory_save", resourceID: item.id,
                    text: String(decoding: data, as: UTF8.self), write: true))
            guard generation == sessionGeneration else { return false }
            await loadInventory()
            return true
        } catch {
            if generation == sessionGeneration { notice = error.localizedDescription }
            return false
        }
    }
    @discardableResult
    public func unlistInventoryFood(_ id: String) async -> Bool {
        guard let index = inventory.firstIndex(where: { $0.id == id }) else { return false }
        let listingID = inventory[index].listingID
        if isBackend {
            guard !backendBusy else {
                notice = "Another change is saving. Try again in a moment."
                return false
            }
            guard await backendWrite("inventory_unlist", id: id) else {
                if notice == "unavailable" {
                    notice =
                        "This item has an active pickup or has already been sold. Resolve the pickup before removing it."
                }
                return false
            }
        } else if cart.contains(listingID) {
            notice = "This listing has a pickup reservation"
            return false
        }
        inventoryRevision += 1
        // Apply successful writes immediately, even if an older inventory read is still in flight.
        if let current = inventory.firstIndex(where: { $0.id == id }) {
            inventory[current].listingID = ""
        }
        catalog.removeAll { $0.id == listingID }
        ownListings.removeAll { $0.id == listingID }
        return true
    }
    @discardableResult
    public func removeInventoryFood(_ id: String) async -> Bool {
        guard let item = inventory.first(where: { $0.id == id }) else { return false }
        if isBackend {
            guard !backendBusy else {
                notice = "Another change is saving. Try again in a moment."
                return false
            }
            guard await backendWrite("inventory_remove", id: id) else {
                if notice == "unavailable" {
                    notice =
                        "This item has an active pickup or has already been sold. Resolve the pickup before removing it."
                }
                return false
            }
        } else if !item.listingID.isEmpty {
            guard await unlistInventoryFood(id) else { return false }
        }
        inventoryRevision += 1
        inventory.removeAll { $0.id == id }
        catalog.removeAll { $0.id == item.listingID }
        ownListings.removeAll { $0.id == item.listingID }
        return true
    }
    public func sellInventoryFood(
        _ item: InventoryFood, price: Int, allergens: String,
        pickupAddress: String, latitude: Double, longitude: Double,
        start: Date, end: Date, retail: Int? = nil,
        weightPounds: Double? = nil
    ) async -> Bool {
        guard price > 0, end > start, end > Date() else { return false }
        if !isBackend {
            guard !item.isListed, let index = inventory.firstIndex(where: { $0.id == item.id })
            else { return false }
            let id = "inventory-\(item.id)"
            var listing = Listing(
                id: id, name: item.title, price: price, retail: retail ?? price,
                distance: 0, freshness: item.condition == "Use soon" ? .useSoon : .good,
                pickup: "Scheduled pickup", updated: "just now", stale: false,
                sellerID: "nina", category: item.category, quantity: item.quantity,
                weight: weightPounds ?? 0,
                opened: false, storage: item.storage, allergens: allergens,
                purchased: "Seller supplied",
                receipt: false, vegetarian: true, prepared: false)
            listing.imageURL = "data:image/jpeg;base64," + item.photoBase64
            catalog.insert(listing, at: 0)
            ownListings.insert(listing, at: 0)
            inventory[index].listingID = id
            return true
        }
        guard let repository, !backendBusy else { return false }
        let generation = sessionGeneration
        backendBusy = true
        defer { if generation == sessionGeneration { backendBusy = false } }
        do {
            let data = try JSONSerialization.data(withJSONObject: [
                "price": price, "retail": retail ?? price,
                "grams": Int(((weightPounds ?? 0) * 453.592).rounded()), "allergens": allergens,
                "pickupAddress": pickupAddress,
                "latitude": latitude, "longitude": longitude,
                "start": floor(start.timeIntervalSince1970 * 1000),
                "end": floor(end.timeIntervalSince1970 * 1000),
            ])
            _ = try await repository.request(
                APIRequest(
                    "inventory_publish", resourceID: item.id,
                    text: String(decoding: data, as: UTF8.self), write: true))
            guard generation == sessionGeneration else { return false }
            await loadInventory()
            await refreshBackend(force: true)
            await refreshMarketplace()
            return true
        } catch {
            if generation == sessionGeneration { notice = error.localizedDescription }
            return false
        }
    }
}
