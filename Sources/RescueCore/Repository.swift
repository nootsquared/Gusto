import Foundation

public struct BackendSession: Codable, Equatable, Sendable {
    public let userId: String
    public let token: String
    public init(userId: String, token: String) {
        self.userId = userId
        self.token = token
    }
}

public struct APIRequest: Codable, Equatable, Sendable {
    public var action: String
    public var operationId = ""
    public var resourceId = ""
    public var text = ""
    public var version = 0
    public var value = 0
    public var enabled = false
    public var cursor = ""
    public init(_ action: String, resourceID: String = "", text: String = "", write: Bool = false) {
        self.action = action
        resourceId = resourceID
        self.text = text
        if write { operationId = UUID().uuidString }
    }
    public var cacheKey: String {
        "\(action):\(resourceId):\(text):\(cursor):\(value):\(version):\(enabled)"
    }
}

public struct APIResponse: Sendable {
    public let serverTime: Double
    public let payload: Data
}
public enum RepositoryError: Error, LocalizedError {
    case server(String)
    case offline, invalidResponse
    public var errorDescription: String? {
        switch self {
        case .server(let code):
            if code == "gemini_billing_required" { return "Gemini needs credits added to the project's billing account" }
            if code == "gemini_not_configured" { return "Gemini hasn't been configured on this server yet" }
            if code == "gemini_unavailable" { return "Gemini is unavailable right now" }
            if code == "invalid_analysis" { return "Gemini couldn't confidently read the food details" }
            return code.replacingOccurrences(of: "_", with: " ")
        case .offline: return "Offline. This action needs a server response."
        case .invalidResponse: return "The server returned an unsupported response."
        }
    }
}
public protocol RescueRepository: Sendable {
    var accountID: String { get }
    func request(_ request: APIRequest) async throws -> APIResponse
    func cached(_ key: String, maxAge: TimeInterval) async -> Data?
    func enqueue(_ request: APIRequest) async throws
    func pending() async -> [APIRequest]
    func failed() async -> [APIRequest]
    func synchronize() async throws
    func clearCache() async throws
}

public struct BackendUser: Codable, Sendable {
    public let id: String
    public let name: String
    public var avatar: String? = nil
}
public struct SellerPickupRequest: Codable, Identifiable, Sendable {
    public let id: String
    public let buyerId: String
    public let buyerName: String
    public let proposed: Double
    public let status: String
    public let phase: String
    public let items: [Listing]
}
public struct BackendPreferences: Codable, Sendable {
    public let vegetarian: Bool
    public let area: String
    public let smartAlerts: Bool
    public let version: Int
}
public struct MonthlyImpact: Codable, Sendable {
    public let month: String
    public let mode: String
    public let items: Int
    public let saved: Int
    public let grams: Int
    public let earnings: Int
}
public struct BackendConversation: Codable, Sendable {
    public let id: String
    public let buyerId: String
    public let sellerId: String
    public let summary: String
}
public struct BackendReceipt: Codable, Sendable {
    public let id: String
    public let seller: Seller
    public let paid: Int
    public let items: [Item]
    public struct Item: Codable, Sendable {
        public let id: String
        public let name: String
        public let price: Int
        public let retail: Int
        public let weight: Double
        public let imageURL: String
        public let sellerID: String
        public let category: String
        public var listing: Listing {
            Listing(
                id: id, name: name, price: price, retail: retail, distance: 0, freshness: .good,
                pickup: "Completed", updated: "", stale: false, sellerID: sellerID,
                category: category,
                quantity: "1 package", weight: weight, opened: false, storage: "", allergens: "",
                purchased: "", receipt: true, vegetarian: false, prepared: false, available: false,
                imageURL: imageURL)
        }
    }
    public var receipt: Receipt {
        Receipt(id: id, seller: seller, items: items.map(\.listing), paid: paid)
    }
}
public struct BackendHistoryPage: Codable, Sendable {
    public let receipts: [BackendReceipt]
    public let cursor: String
}
public struct BackendRun: Codable, Sendable {
    public let id: String
    public let mode: String
    public let phase: String
    public let currentStop: Int
    public let version: Int
    public let stops: [Stop]
    public struct Stop: Codable, Sendable {
        public let id: String
        public let seller: Seller
        public let items: [Listing]
        public let proposed: Double
        public let windowEnd: Double
        public let status: String
        public let locationId: String
        public var privateLocation: PrivatePickupLocation?
        public var stop: PickupStop {
            let date = Date(timeIntervalSince1970: proposed / 1000)
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            return PickupStop(
                seller: seller, items: items, minute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0),
                status: StopStatus(rawValue: status) ?? .unconfirmed, serverID: id,
                locationID: locationId, windowEnd: windowEnd, privateLocation: privateLocation)
        }
    }
    public var plan: PickupPlan {
        PickupPlan(
            serverID: id, version: version, stops: stops.map(\.stop),
            mode: RouteMode(rawValue: mode) ?? .fastest, elapsed: stops.count * 8, distance: 0)
    }
}
public struct BackendBootstrap: Codable, Sendable {
    public let user: BackendUser
    public let preferences: BackendPreferences
    public let cart: [String]
    public let cartListings: [Listing]
    public let savedListings: [Listing]
    public let favorites: [String]
    public let sellers: [Seller]
    public var run: BackendRun?
    public let receipts: [BackendReceipt]
    public let sales: [BackendReceipt]
    public let ownListings: [Listing]
    public let monthly: [MonthlyImpact]
    public let conversations: [BackendConversation]
    public let simulation: Bool
    public let follows: [BackendFollow]?
    public var pickupRequests: [SellerPickupRequest]? = nil
    public mutating func stripPrivateLocations(at time: Double) {
        if let current = run {
            // Exact pickup data is never persisted. Online projections alone can unlock it.
            run = BackendRun(
                id: current.id, mode: current.mode, phase: current.phase,
                currentStop: current.currentStop, version: current.version,
                stops: current.stops.map { s in
                    var copy = s
                    copy.privateLocation = nil
                    return copy
                })
        }
    }
}
public struct BackendPage: Codable, Sendable {
    public let listings: [Listing]
    public let sellers: [Seller]
    public let cursor: String
}
public struct BackendMessage: Codable, Sendable {
    public let id: String
    public let senderId: String
    public let text: String
    public let sequence: Int
    public let operationId: String
}
public struct BackendMessages: Codable, Sendable {
    public let messages: [BackendMessage]
    public let lastSequence: Int
    public let cursor: String
}

// External integrations must provide an authoritative result; unavailable adapters cannot succeed.
public protocol SessionProvider: Sendable {
    func currentSession() async throws -> BackendSession
    func changes() async -> AsyncStream<BackendSession>
}
public protocol MediaUploader: Sendable {
    func upload(_ data: Data, mimeType: String) async throws -> String
}
public protocol AnalysisProvider: Sendable {
    func requestAnalysis(listingID: String, mediaID: String) async throws -> String
}
public protocol PaymentProvider: Sendable {
    func requestPayment(stopID: String, operationID: String) async throws -> String
}
public protocol VerificationProvider: Sendable { func requestVerification() async throws -> String }
public protocol PushProvider: Sendable { func registerDevice() async throws }
public protocol DirectionsProvider: Sendable {
    func estimate(from: GeoPoint, to: GeoPoint) async throws -> Double
}
public struct GeoPoint: Codable, Sendable {
    public let latitude: Double
    public let longitude: Double
}

public enum SessionMode: String, Codable, Sendable { case localDemo, authenticated }
public struct DraftAsset: Codable, Sendable {
    public let localURL: URL
    public let mimeType: String
}
public protocol PhotoCaptureProvider: Sendable { func capture() async throws -> DraftAsset }
public protocol ReferralProvider: Sendable {
    func redeem(code: String, receiptID: String) async throws
}

public struct BackendFollow: Codable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let target: String
}
