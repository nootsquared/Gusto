import Foundation
import Observation

/// One source of truth for the mock demo. Views own presentation; this owns product state.
@MainActor @Observable public final class AppStore {
    public var catalog: [Listing] = MockCatalog.listings
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

    public init(service: DemoService = DemoService()) { self.service = service }
    public var runActive: Bool { phase != .idle && phase != .finished }
    public var cartItems: [Listing] { cart.compactMap { id in catalog.first { $0.id == id } } }
    public var cartTotals: Totals { Totals(cartItems) }
    public var currentStop: PickupStop? {
        guard let plan, plan.stops.indices.contains(stopIndex) else { return nil }
        return plan.stops[stopIndex]
    }
    public var impact: Totals { Totals(receipts.flatMap(\.items)) }
    public var runImpact: Totals { Totals(runReceipts.flatMap(\.items)) }
    public func listing(_ id: String) -> Listing? { catalog.first { $0.id == id } }
    public func seller(_ id: String) -> Seller {
        MockCatalog.sellers.first { $0.id == id } ?? MockCatalog.sellers[0]
    }
    public func pinnedListing(for sellerID: String) -> Listing? {
        plan?.stops.first { $0.id == sellerID }?.items.first
            ?? cartItems.first { $0.sellerID == sellerID }
            ?? catalog.first { $0.sellerID == sellerID }
    }

    @discardableResult public func reserve(_ id: String) -> Bool {
        guard !runActive, let item = listing(id), item.available, !cart.contains(id) else {
            return false
        }
        cart.append(id)
        invalidatePlan()
        notice = "\(item.name) reserved · \(cart.count) items · one easy trip"
        return true
    }
    public func remove(_ id: String) {
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
        guard !runActive else { return }
        planGeneration = UUID()
        coordinating = false
        counterSellerID = nil
        plan = PickupPlanner.build(items: cartItems.filter(\.available), mode: mode)
    }
    public func coordinate() async {
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
        guard !runActive, phase == .idle, plan?.allConfirmed == true else { return false }
        runReceipts = []
        stopIndex = 0
        phase = .enroute
        return true
    }
    public func delayStop(_ sellerID: String) {
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
        guard phase == .enroute else { return }
        phase = .arrived
    }
    public func announceArrival() async {
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
        guard phase == .verifying else { return }
        phase = .payment
    }
    public func reportIssue() {
        guard phase == .verifying || phase == .arrived, let stop = currentStop else { return }
        plan?.stops[stopIndex].status = .skipped
        notice = "Issue recorded for \(stop.seller.firstName) · no demo charge"
        advance()
    }
    public func pay() async {
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
        guard phase == .finished else { return }
        phase = .idle
        cart = []
        invalidatePlan()
    }
    public func freshCheck(_ id: String) async {
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
        var results = catalog.filter(filters.accepts)
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
