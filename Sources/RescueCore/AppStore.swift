import Foundation
import Observation

/// One presentation store for connected and fixture modes. Views own transient input.
@MainActor @Observable public final class AppStore {
    public var catalog: [Listing] = MockCatalog.listings
    public private(set) var sellers: [Seller] = MockCatalog.sellers
    public private(set) var isBackend = false
    public private(set) var online = false
    public private(set) var accountID = "fixture"
    public private(set) var profileName = "Priya S."
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
    @ObservationIgnored private var repository: (any RescueRepository)?
    @ObservationIgnored private var searchGeneration = UUID()
    @ObservationIgnored private var lastRefresh = Date.distantPast
    @ObservationIgnored private var lastFeedRefresh = Date.distantPast
    @ObservationIgnored private var serverOffset: Double = 0
    @ObservationIgnored private var feedLoading = false
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
    public var currentStop: PickupStop? {
        guard let plan, plan.stops.indices.contains(stopIndex) else { return nil }
        return plan.stops[stopIndex]
    }
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

    @discardableResult public func reserve(_ id: String) -> Bool {
        if isBackend {
            if listing(id) != nil { launchWrite("reserve", id: id) }
            return false
        }
        guard !runActive, let item = listing(id), item.available, !cart.contains(id) else {
            return false
        }
        cart.append(id)
        invalidatePlan()
        notice = "\(item.name) reserved · \(cart.count) items · one easy trip"
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
    public func makePlan(mode: RouteMode = .fastest) {
        if isBackend {
            launchWrite("plan", text: mode.rawValue)
            return
        }
        guard !runActive else { return }
        planGeneration = UUID()
        coordinating = false
        counterSellerID = nil
        plan = PickupPlanner.build(items: cartItems.filter(\.available), mode: mode)
    }
    public func coordinate() async {
        if isBackend {
            if let id = plan?.serverID { await backendWrite("coordinate", id: id) }
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
            if let id = currentStop?.serverID { await backendWrite("payment", id: id) }
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
            await backendWrite("freshness", id: id)
            notice = "Fresh Check requested · waiting for seller"
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
    public func visibleListings(query text: String? = nil) -> [Listing] {
        if isBackend, let text, !text.isEmpty {
            return searchResults.filter { filters.accepts($0, sellers: sellers) }
        }
        var results = catalog.filter { filters.accepts($0, sellers: sellers) }
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
    public func connect(_ newRepository: any RescueRepository) async {
        sessionGeneration = UUID()
        let generation = sessionGeneration
        repository = newRepository
        isBackend = true
        online = false
        backendBusy = false
        accountID = newRepository.accountID
        profileName = "Loading account…"
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
        await loadNextPage(first: true)
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
    }
    private func apply(_ snapshot: BackendBootstrap) {
        profileName = snapshot.user.name
        preferences = snapshot.preferences
        cart = snapshot.cart
        savedIDs = Set(snapshot.favorites)
        merge(snapshot.cartListings + snapshot.savedListings + snapshot.ownListings)
        sellers = snapshot.sellers
        ownListings = snapshot.ownListings
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
            lastRefresh = Date()
            await restorePendingMessages()
        } catch {
            guard generation == sessionGeneration else { return }
            #if DEBUG
                NSLog("Rescue bootstrap failed: %@", String(describing: error))
            #endif
            online = false
            notice =
                catalog.isEmpty
                ? "Offline · connect the local services to load food"
                : "Offline · showing cached food"
            for i in plan?.stops.indices ?? 0..<0 { plan?.stops[i].privateLocation = nil }
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
            let spec: [String: Any] = [
                "query": text, "maxPrice": filters.maxPrice, "distance": filters.distance,
                "vegetarian": filters.vegetarian, "unopened": filters.unopened,
                "freshness": filters.freshness.map(\.rawValue),
                "categories": Array(filters.categories), "minimumRating": filters.minimumRating,
                "tonight": filters.tonight, "tomorrow": filters.tomorrow,
            ]
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
            }
        } catch {}
    }
    private func launchWrite(_ action: String, id: String = "", text: String = "") {
        guard !backendBusy else { return }
        Task { await backendWrite(action, id: id, text: text) }
    }
    private func backendWrite(_ action: String, id: String = "", text: String = "") async {
        guard let repository, !backendBusy else { return }
        let generation = sessionGeneration
        backendBusy = true
        defer { if generation == sessionGeneration { backendBusy = false } }
        do {
            _ = try await repository.request(
                APIRequest(action, resourceID: id, text: text, write: true))
            guard generation == sessionGeneration else { return }
            online = true
            await refreshBackend(force: true)
            if action == "reserve" { notice = "Reserved for 30 minutes · server confirmed" }
        } catch { if generation == sessionGeneration { notice = error.localizedDescription } }
    }
    public func publishListing(
        name: String, price: Int, freshness: Freshness, pickup: String, confirmations: Int
    ) async -> Bool {
        if !isBackend {
            return publish(
                name: name, price: price, freshness: freshness, pickup: pickup,
                confirmations: confirmations)
        }
        guard let repository, confirmations == 4, !backendBusy else {
            notice = "Connect an account before publishing"
            print(
                "Rescue publish rejected before HTTP:", repository == nil, confirmations,
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
                "safeStorage": true, "accurateCondition": true,
                "noSpoilage": true, "allergensDeclared": true, "pickupStart": floor(window.start),
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
            NSLog("Rescue publish failed: %@", String(describing: error))
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
        while !Task.isCancelled {
            let wait: Double =
                online
                ? (activeChat == nil ? (runActive || plan != nil ? 3 : 30) : 5)
                : min(60, pow(2, Double(min(failures + 1, 6))))
            do {
                try await Task.sleep(
                    nanoseconds: UInt64((wait + Double.random(in: 0...0.25)) * 1_000_000_000))
            } catch { return }
            await refreshBackend(force: runActive || plan != nil || !online)
            if online && Date().timeIntervalSince(lastFeedRefresh) > 60 {
                await loadNextPage(first: true)
            }
            if let activeChat { await loadMessages(activeChat) }
            failures = online ? 0 : failures + 1
        }
    }
    public var messageSellers: [Seller] {
        if !isBackend { return sellers }
        let ids = Set(conversations.map { $0.buyerId == accountID ? $0.sellerId : $0.buyerId })
        return sellers.filter { ids.contains($0.id) }
    }
    public var personalizedListings: [Listing] {
        if !isBackend { return ["straw", "avo", "gran", "yog", "eggs"].compactMap(listing) }
        let followed = Set(follows.filter { $0.kind == "category" }.map(\.target))
        let purchased = Set(receipts.flatMap { $0.items.map(\.category) })
        let eligible = catalog.filter {
            $0.available && (!(preferences?.vegetarian ?? false) || $0.vegetarian)
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
