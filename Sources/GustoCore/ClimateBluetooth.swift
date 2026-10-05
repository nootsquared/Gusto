import Foundation

/// Matches GustoHardware/BLE_PROTOCOL.md and the Nano's publishBle encoder byte for byte.
public struct ClimatePacket: Equatable, Sendable {
    public static let serviceUUID = "ef05ba28-5c0a-4c52-9d3a-a643c142ba10"
    public static let characteristicUUID = "ef05ba28-5c0a-4c52-9d3a-a643c142ba11"
    public let sequence: UInt32
    public let uptimeMilliseconds: UInt32
    public let temperatureFahrenheit: Double?
    public let humidityPercent: Double?
    public let lightRawCount: UInt16?
    public var temperatureCelsius: Double? { temperatureFahrenheit.map { ($0 - 32) * 5 / 9 } }

    public init?(data: Data) {
        let bytes = Array(data)
        guard bytes.count == 17, bytes[0] == 0x30, bytes[1] == 1, bytes[16] <= 7 else {
            return nil
        }
        func u16(_ offset: Int) -> UInt16 {
            UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        }
        func u32(_ offset: Int) -> UInt32 {
            (0..<4).reduce(0) { $0 | (UInt32(bytes[offset + $1]) << ($1 * 8)) }
        }
        sequence = u32(2)
        uptimeMilliseconds = u32(6)
        let mask = bytes[16]
        let temperature = Double(Int16(bitPattern: u16(10))) / 10
        let humidity = Double(u16(12)) / 10
        // These are the ranges accepted by the firmware before setting its validity bits.
        guard mask & 1 == 0 || (-40...185).contains(temperature),
            mask & 2 == 0 || (0...100).contains(humidity)
        else { return nil }
        temperatureFahrenheit = mask & 1 != 0 ? temperature : nil
        humidityPercent = mask & 2 != 0 ? humidity : nil
        lightRawCount = mask & 4 != 0 ? u16(14) : nil
    }
}

/// A repeated initial read/notification must not make an old measurement look fresh.
public struct ClimateStream: Sendable {
    public private(set) var packet: ClimatePacket?
    public private(set) var receivedAt: Date?
    public init() {}
    @discardableResult public mutating func receive(_ data: Data, at date: Date) -> Bool {
        guard let next = ClimatePacket(data: data) else { return false }
        if let packet, packet.sequence == next.sequence,
            packet.uptimeMilliseconds == next.uptimeMilliseconds
        {
            return false
        }
        packet = next
        receivedAt = date
        return true
    }
    public func isFresh(at date: Date) -> Bool {
        guard let receivedAt else { return false }
        let age = date.timeIntervalSince(receivedAt)
        return age >= 0 && age < 5
    }
}
