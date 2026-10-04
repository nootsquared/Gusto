import Foundation

public enum Freshness: String, CaseIterable, Codable, Sendable {
    case fresh = "Fresh"
    case good = "Good"
    case useSoon = "Use Soon"
}

public struct Seller: Identifiable, Hashable, Codable, Sendable {
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
    public var avatarURL: String? = nil
    public var image: String { avatarURL.flatMap { $0.isEmpty ? nil : $0 } ?? "seller-\(id)" }
}

public struct Listing: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public var price: Int
    public let retail: Int
    public var distance: Double
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
    public var imageURL: String? = nil
    public var version: Int? = nil
    public var windows: [PickupWindow]? = nil
    public var image: String {
        if let imageURL { return imageURL.isEmpty ? "unavailable-photo" : imageURL }
        return id == "my-granola" ? "gran" : id
    }
    public var savings: Int { max(0, retail - price) }
    public var discount: Int {
        retail > 0 ? Int((Double(savings) / Double(retail) * 100).rounded()) : 0
    }
}

public struct Totals: Equatable, Codable, Sendable {
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

public enum RouteMode: String, CaseIterable, Codable, Sendable {
    case fastest = "Fastest"
    case shortest = "Shortest"
    case bestTiming = "Best timing"
}
public enum StopStatus: String, Codable, Sendable {
    case unconfirmed, waiting, confirmed, paid, skipped
}
public struct PickupStop: Identifiable, Codable, Sendable {
    public let seller: Seller
    public let items: [Listing]
    public var minute: Int
    public var status: StopStatus = .unconfirmed
    public var serverID: String? = nil
    public var locationID: String? = nil
    public var windowEnd: Double? = nil
    public var privateLocation: PrivatePickupLocation? = nil
    public var id: String { serverID ?? seller.id }
    public var totals: Totals { Totals(items) }
    public var time: String {
        let hour = (minute / 60) % 12
        return "\(hour == 0 ? 12 : hour):\(String(format: "%02d", minute % 60))"
    }
}

public struct PickupPlan: Codable, Sendable {
    public var serverID: String? = nil
    public var version: Int? = nil
    public var stops: [PickupStop]
    public var mode: RouteMode
    public var elapsed: Int
    public var distance: Double
    public var totals: Totals { Totals(stops.flatMap(\.items)) }
    public var allConfirmed: Bool { !stops.isEmpty && stops.allSatisfy { $0.status == .confirmed } }
}

public enum RunPhase: String, Codable, Sendable, Equatable {
    case idle, enroute, arrived, waiting, verifying, payment, paying, rescued, finished
}
public struct ChatMessage: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let text: String
    public let outgoing: Bool
    public var delivery: String? = nil
    public init(_ text: String, outgoing: Bool = false, id: UUID = UUID(), delivery: String? = nil)
    {
        self.id = id
        self.delivery = delivery
        self.text = text
        self.outgoing = outgoing
    }
}
public struct Receipt: Identifiable, Codable, Sendable {
    public let id: String
    public let seller: Seller
    public let items: [Listing]
    public let paid: Int
    public var totals: Totals { Totals(items) }
}

public struct Filters: Equatable, Codable, Sendable {
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
    public func accepts(_ item: Listing) -> Bool { accepts(item, sellers: MockCatalog.sellers) }
    public func accepts(_ item: Listing, sellers: [Seller]) -> Bool {
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
            && (sellers.first { $0.id == item.sellerID }?.rating ?? 0) < minimumRating
        {
            return false
        }
        return true
    }
}

public enum Money {
    public static func text(_ cents: Int) -> String { String(format: "$%.2f", Double(cents) / 100) }
}

public struct PickupWindow: Hashable, Codable, Sendable {
    public let id: String
    public let locationID: String
    public let start: Double
    public let end: Double
    public let timezone: String
}

public struct PrivatePickupLocation: Codable, Sendable {
    public let address: String
    public let instructions: String
    public let latitude: Double
    public let longitude: Double
    public let cacheUntil: Double
}

public enum ListingPublishPolicy {
    public static func window(_ label: String, now: Date) -> (start: Double, end: Double) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Detroit")!
        var day = calendar.startOfDay(for: now)
        if label.hasPrefix("Tomorrow") { day = calendar.date(byAdding: .day, value: 1, to: day)! }
        let startHour = label == "Tonight 6–9" ? 18 : label == "Tomorrow AM" ? 8 : 14
        let endHour = label == "Tonight 6–9" ? 21 : label == "Tomorrow AM" ? 12 : 20
        let start =
            label == "Now–8 PM" ? now : calendar.date(byAdding: .hour, value: startHour, to: day)!
        let end = calendar.date(byAdding: .hour, value: endHour, to: day)!
        return (start.timeIntervalSince1970 * 1000, end.timeIntervalSince1970 * 1000)
    }
}
