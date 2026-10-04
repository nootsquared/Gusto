import Foundation

public struct InventoryFood: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var variety: String
    public var category: String
    public var condition: String
    public var quantity: String
    public var storage: String
    public var photoBase64: String
    public var identification: String
    public var confidence: Double
    public var scannedAt: Double
    public var listingID: String
    public var deviceID: String
    public init(
        id: String = UUID().uuidString, name: String = "", variety: String = "",
        category: String = "Produce", condition: String = "Not assessed",
        quantity: String = "1 item",
        storage: String = "Counter", photoBase64: String = "",
        identification: String = "Manual review",
        confidence: Double = 0, scannedAt: Double = Date().timeIntervalSince1970 * 1000,
        listingID: String = "", deviceID: String = ""
    ) {
        self.id = id
        self.name = name
        self.variety = variety
        self.category = category
        self.condition = condition
        self.quantity = quantity
        self.storage = storage
        self.photoBase64 = photoBase64
        self.identification = identification
        self.confidence = confidence
        self.scannedAt = scannedAt
        self.listingID = listingID
        self.deviceID = deviceID
    }
    public var title: String { variety.isEmpty ? name : "\(variety) \(name)" }
    public var isListed: Bool { !listingID.isEmpty }
}

public struct StorageReading: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var itemID: String
    public var deviceID: String
    public var temperature: Double
    public var humidity: Double
    public var light: Double
    public var recordedAt: Double
    public init(
        id: String = UUID().uuidString, itemID: String, deviceID: String,
        temperature: Double, humidity: Double, light: Double, recordedAt: Double
    ) {
        self.id = id
        self.itemID = itemID
        self.deviceID = deviceID
        self.temperature = temperature
        self.humidity = humidity
        self.light = light
        self.recordedAt = recordedAt
    }
}

public struct StorageSummary: Equatable, Sendable {
    public let temperature: Double
    public let humidity: Double
    public let light: Double
    public let latest: Double
    public let count: Int
    public var isLive: Bool { Date().timeIntervalSince1970 * 1000 - latest < 300_000 }
    public static func recent(
        _ readings: [StorageReading], item: InventoryFood,
        now: Double = Date().timeIntervalSince1970 * 1000
    ) -> StorageSummary? {
        let valid = readings.filter {
            $0.itemID == item.id && $0.deviceID == item.deviceID && !item.deviceID.isEmpty
                && $0.recordedAt <= now && $0.recordedAt >= max(item.scannedAt, now - 259_200_000)
                && $0.temperature.isFinite && (-40...85).contains($0.temperature)
                && $0.humidity.isFinite && (0...100).contains($0.humidity)
                && $0.light.isFinite && (0...200_000).contains($0.light)
        }
        guard !valid.isEmpty else { return nil }
        let count = Double(valid.count)
        return StorageSummary(
            temperature: valid.reduce(0) { $0 + $1.temperature } / count,
            humidity: valid.reduce(0) { $0 + $1.humidity } / count,
            light: valid.reduce(0) { $0 + $1.light } / count,
            latest: valid.map(\.recordedAt).max()!, count: valid.count)
    }
}

public struct FoodStorageGuide: Sendable {
    public let temperature: String
    public let humidity: String
    public let note: String
    public let source: String
    public static func forFood(_ item: InventoryFood) -> FoodStorageGuide? {
        let name = item.name.lowercased()
        if name.contains("tomato") {
            guard ["Unripe", "Ripe"].contains(item.condition) else { return nil }
            let ripe = item.condition == "Ripe"
            return FoodStorageGuide(
                temperature: ripe ? "7–10°C" : "12.5–15°C", humidity: "90–95%",
                note: ripe
                    ? "Firm-ripe tomatoes: short-term storage, 3–5 days. This is a produce-handling reference, not a household expiry date."
                    : "Reference for mature-green tomatoes. Confirm ripeness; variety and condition change storage needs.",
                source: "https://postharvest.ucdavis.edu/produce-facts-sheets/tomato")
        }
        if name.contains("banana") {
            return FoodStorageGuide(
                temperature: "13–14°C", humidity: "90–95%",
                note:
                    "Cavendish storage reference; ripening uses 15–20°C. Other varieties can differ.",
                source: "https://postharvest.ucdavis.edu/produce-facts-sheets/banana")
        }
        return nil
    }
}
