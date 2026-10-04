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
    public var analysis: String? = nil
    public var scanAnalysis: FoodAnalysis? {
        guard let analysis, let data = analysis.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FoodAnalysis.self, from: data)
    }
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
    public var lightUnit: String? = nil
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

public struct FoodAnalysis: Codable, Equatable, Sendable {
    public let name: String
    public let variety: String
    public let category: String
    public let condition: String
    public let quantity: String
    public let storage: String
    public let description: String
    public let allergens: String
    public let confidence: Double
    public let opened: Bool
    public let vegetarian: Bool
    public let prepared: Bool
    public let referenceTemperature: Double
    public let idealTemperatureMin: Double
    public let idealTemperatureMax: Double
    public let idealHumidityMin: Double
    public let idealHumidityMax: Double
    public let qualityDaysMin: Double
    public let qualityDaysMax: Double
    public let box: [Double]
}

/// Prototype quality estimate, not a food-safety expiration or a calibrated biological model.
public struct FoodQualityEstimate: Sendable {
    public let daysMin: Double
    public let daysMax: Double
    public let temperature: Double
    public let humidity: Double
    public let samples: Int
    public static func estimate(_ item: InventoryFood, readings: [StorageReading], now: Double = Date().timeIntervalSince1970 * 1000) -> Self? {
        guard let a = item.scanAnalysis, a.qualityDaysMax > 0,
            ["Unripe", "Ripe", "Use soon"].contains(item.condition),
            a.condition == item.condition, a.name == item.name, a.variety == item.variety,
            a.storage == item.storage,
            let summary = StorageSummary.recent(readings, item: item, now: now),
            now >= item.scannedAt, a.referenceTemperature.isFinite,
            a.qualityDaysMin.isFinite, a.qualityDaysMax.isFinite,
            a.qualityDaysMin >= 0, a.qualityDaysMax >= a.qualityDaysMin, a.qualityDaysMax <= 60
        else { return nil }
        // Q10=2 is an explicit demo assumption. Cooling below the reference never promises a longer life.
        let temperatureFactor = min(8, max(1, pow(2, (summary.temperature - a.referenceTemperature) / 10)))
        let humidityFactor = summary.humidity < a.idealHumidityMin ? 1.15 : 1.0
        let rate = temperatureFactor * humidityFactor
        let elapsed = (now - item.scannedAt) / 86_400_000
        return Self(daysMin: max(0, a.qualityDaysMin / rate - elapsed), daysMax: max(0, a.qualityDaysMax / rate - elapsed), temperature: summary.temperature, humidity: summary.humidity, samples: summary.count)
    }
    public var label: String {
        daysMax < 1 ? "Check today" : "About \(max(1, Int(floor(daysMin))))–\(max(1, Int(ceil(daysMax)))) days"
    }
}

public struct StorageSummary: Equatable, Sendable {
    public let temperature: Double
    public let humidity: Double
    public let light: Double
    public let lightUnit: String
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
        let lightUnit = valid.contains { $0.lightUnit == "raw" } ? "raw" : "lux"
        let lightSamples = valid.filter { ($0.lightUnit ?? "lux") == lightUnit }
        return StorageSummary(
            temperature: valid.reduce(0) { $0 + $1.temperature } / count,
            humidity: valid.reduce(0) { $0 + $1.humidity } / count,
            light: lightSamples.reduce(0) { $0 + $1.light } / Double(lightSamples.count), lightUnit: lightUnit,
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
