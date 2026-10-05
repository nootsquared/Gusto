import XCTest

#if canImport(GustoCore)
    @testable import GustoCore
#else
    @testable import Gusto
#endif

final class ClimateBluetoothTests: XCTestCase {
    private func record(
        sequence: UInt32 = 42, uptime: UInt32 = 123_456,
        temperature: Int16 = 725, humidity: UInt16 = 567,
        light: UInt16 = 4321, mask: UInt8 = 7
    ) -> Data {
        var bytes: [UInt8] = [0x30, 1]
        for value in [sequence, uptime] {
            bytes += (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
        }
        for value in [UInt16(bitPattern: temperature), humidity, light] {
            bytes += [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
        }
        bytes.append(mask)
        return Data(bytes)
    }
    func testDecodesFirmwareLayoutAndUnits() throws {
        let packet = try XCTUnwrap(ClimatePacket(data: record()))
        XCTAssertEqual(packet.sequence, 42)
        XCTAssertEqual(packet.uptimeMilliseconds, 123_456)
        XCTAssertEqual(packet.temperatureFahrenheit, 72.5)
        XCTAssertEqual(try XCTUnwrap(packet.temperatureCelsius), 22.5, accuracy: 0.0001)
        XCTAssertEqual(packet.humidityPercent, 56.7)
        XCTAssertEqual(packet.lightRawCount, 4321)
        XCTAssertEqual(ClimatePacket(data: record(temperature: -123))?.temperatureFahrenheit, -12.3)
        XCTAssertEqual(ClimatePacket(data: record(light: .max))?.lightRawCount, .max)
    }
    func testValidityBitsDoNotReuseMissingMeasurements() throws {
        let empty = try XCTUnwrap(
            ClimatePacket(data: record(temperature: .max, humidity: .max, mask: 0)))
        XCTAssertNil(empty.temperatureFahrenheit)
        XCTAssertNil(empty.humidityPercent)
        XCTAssertNil(empty.lightRawCount)
        for mask in UInt8(0)...7 {
            let packet = try XCTUnwrap(ClimatePacket(data: record(mask: mask)))
            XCTAssertEqual(packet.temperatureFahrenheit != nil, mask & 1 != 0)
            XCTAssertEqual(packet.humidityPercent != nil, mask & 2 != 0)
            XCTAssertEqual(packet.lightRawCount != nil, mask & 4 != 0)
        }
    }
    func testRejectsMalformedAndOutOfRangePackets() {
        XCTAssertNil(ClimatePacket(data: Data(record().dropLast())))
        XCTAssertNil(ClimatePacket(data: record() + Data([0])))
        for (offset, value) in [(0, UInt8(0x31)), (1, 2), (16, 8)] {
            var bad = record()
            bad[offset] = value
            XCTAssertNil(ClimatePacket(data: bad))
        }
        XCTAssertNil(ClimatePacket(data: record(temperature: 1851)))
        XCTAssertNil(ClimatePacket(data: record(temperature: -401)))
        XCTAssertNil(ClimatePacket(data: record(humidity: 1001)))
    }
    func testStaleDeadlineDuplicatesWrapAndReconnect() {
        let now = Date(timeIntervalSince1970: 10_000)
        var stream = ClimateStream()
        XCTAssertFalse(stream.isFresh(at: now))
        XCTAssertTrue(stream.receive(record(sequence: .max, uptime: .max), at: now))
        XCTAssertFalse(
            stream.receive(record(sequence: .max, uptime: .max), at: now.addingTimeInterval(4)))
        XCTAssertTrue(stream.isFresh(at: now.addingTimeInterval(4.999)))
        XCTAssertFalse(stream.isFresh(at: now.addingTimeInterval(5)))
        XCTAssertFalse(stream.receive(Data([1]), at: now.addingTimeInterval(5)))
        XCTAssertFalse(stream.isFresh(at: now.addingTimeInterval(5)))
        XCTAssertTrue(stream.receive(record(sequence: 0, uptime: 0), at: now.addingTimeInterval(6)))
        XCTAssertTrue(stream.isFresh(at: now.addingTimeInterval(6)))
        stream = ClimateStream()  // Disconnection clears state; rebooted sequences are accepted.
        XCTAssertNil(stream.packet)
        XCTAssertTrue(stream.receive(record(sequence: 0, uptime: 0, mask: 0), at: now))
        XCTAssertNil(stream.packet?.temperatureFahrenheit)
    }
}
