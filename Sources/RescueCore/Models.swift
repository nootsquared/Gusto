import Foundation

public enum Freshness: String, CaseIterable, Codable, Sendable {
    case fresh = "Fresh"
    case good = "Good"
    case useSoon = "Use Soon"
}

public struct Seller: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let rating: Double
    public let pickups: Int
    public let responds: String
    public let student: Bool
    public let area: String
    public let latitude: Double
    public let longitude: Double
    public var firstName: String { String(name.split(separator: " ").first ?? "Seller") }
    public var image: String { "seller-\(id)" }
}

public struct Listing: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var price: Int
    public let retail: Int
    public let distance: Double
    public var freshness: Freshness
    public let pickup: String
    public var updated: String
    public var stale: Bool
    public let sellerID: String
    public let category: String
    public let quantity: String
    public let weight: Double
    public let opened: Bool
    public let storage: String
    public let allergens: String
    public let purchased: String
    public let receipt: Bool
    public let vegetarian: Bool
    public let prepared: Bool
    public var available: Bool = true
    public var image: String { id == "my-granola" ? "gran" : id }
    public var savings: Int { max(0, retail - price) }
    public var discount: Int {
        retail > 0 ? Int((Double(savings) / Double(retail) * 100).rounded()) : 0
    }
}

public struct Totals: Equatable, Sendable {
    public var retail: Int = 0
    public var pay: Int = 0
    public var pounds: Double = 0
    public var count: Int = 0
    public var saved: Int { retail - pay }
    public init(_ listings: [Listing] = []) {
        retail = listings.reduce(0) { $0 + $1.retail }
        pay = listings.reduce(0) { $0 + $1.price }
        pounds = listings.reduce(0) { $0 + $1.weight }
        count = listings.count
    }
}

public enum RouteMode: String, CaseIterable, Sendable {
    case fastest = "Fastest"
    case shortest = "Shortest"
    case bestTiming = "Best timing"
}
public enum StopStatus: String, Sendable { case unconfirmed, waiting, confirmed, paid, skipped }
public struct PickupStop: Identifiable, Sendable {
    public let seller: Seller
    public let items: [Listing]
    public var minute: Int
    public var status: StopStatus = .unconfirmed
    public var id: String { seller.id }
    public var totals: Totals { Totals(items) }
    public var time: String {
        let hour = (minute / 60) % 12
        return "\(hour == 0 ? 12 : hour):\(String(format: "%02d", minute % 60))"
    }
}

public struct PickupPlan: Sendable {
    public var stops: [PickupStop]
    public var mode: RouteMode
    public var elapsed: Int
    public var distance: Double
    public var totals: Totals { Totals(stops.flatMap(\.items)) }
    public var allConfirmed: Bool { !stops.isEmpty && stops.allSatisfy { $0.status == .confirmed } }
}

public enum RunPhase: Sendable, Equatable {
    case idle, enroute, arrived, waiting, verifying, payment, paying, rescued, finished
}
public struct ChatMessage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let outgoing: Bool
    public init(_ text: String, outgoing: Bool = false) {
        id = UUID()
        self.text = text
        self.outgoing = outgoing
    }
}
public struct Receipt: Identifiable, Sendable {
    public let id: String
    public let seller: Seller
    public let items: [Listing]
    public let paid: Int
    public var totals: Totals { Totals(items) }
}

public struct Filters: Equatable, Sendable {
    public var distance: Double = 0.8
    public var maxPrice: Int = 1500
    public var freshness: Set<Freshness> = []
    public var categories: Set<String> = []
    public var vegetarian = false
    public var unopened = false
    public var availableNow = false
    public var tonight = false
    public var tomorrow = false
    public var minimumRating: Double = 0
    public init() {}
    public func accepts(_ item: Listing) -> Bool {
        guard item.available, item.distance <= distance, item.price <= maxPrice else {
            return false
        }
        if !freshness.isEmpty && !freshness.contains(item.freshness) { return false }
        if !categories.isEmpty && !categories.contains(item.category) { return false }
        if vegetarian && !item.vegetarian { return false }
        if unopened && item.opened { return false }
        let window = item.pickup.lowercased()
        if availableNow || tonight || tomorrow {
            let matches =
                (availableNow && window.contains("now"))
                || (tonight && (window.contains("tonight") || window.contains("pm")))
                || (tomorrow && window.contains("tomorrow"))
            if !matches { return false }
        }
        if minimumRating > 0
            && (MockCatalog.sellers.first { $0.id == item.sellerID }?.rating ?? 0) < minimumRating
        {
            return false
        }
        return true
    }
}

public enum Money {
    public static func text(_ cents: Int) -> String { String(format: "$%.2f", Double(cents) / 100) }
}
