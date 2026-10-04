import CoreBluetooth
import Observation
import SwiftUI
import Vision

@MainActor @Observable final class FoodScanController {
    var draft = InventoryFood()
    var analyzing = false
    var error: String?
    var originalPhotoBase64 = ""
    var sensor = StorageSensorConnection()
    private var generation = UUID()
    @ObservationIgnored private var lastHistorySample = Date.distantPast
    @ObservationIgnored private var syncingHistory = false
    func bindStorageHistory(_ store: AppStore) {
        sensor.onSample = { [weak self, weak store] packet, device in
            guard let self, let store, !self.syncingHistory,
                store.inventory.contains(where: { $0.deviceID == device }),
                Date().timeIntervalSince(self.lastHistorySample) >= 60,
                let temperature = packet.temperatureCelsius, let humidity = packet.humidityPercent,
                let light = packet.lightRawCount else { return }
            self.lastHistorySample = .now
            self.syncingHistory = true
            Task {
                await store.ingestStorageSample(deviceID: device, temperature: temperature, humidity: humidity, light: Double(light))
                self.syncingHistory = false
            }
        }
    }
    func reset() {
        generation = UUID()
        draft = InventoryFood()
        analyzing = false
        error = nil
        originalPhotoBase64 = ""
        lastHistorySample = .distantPast
        sensor.stopSearch()
        sensor.disconnect()
        sensor.status = "Not connected"
    }

    func identify(_ image: UIImage, store: AppStore) async {
        generation = UUID()
        let current = generation
        analyzing = true
        error = nil
        let scale = 640 / max(1, max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        var photo = normalized.jpegData(compressionQuality: 0.5) ?? Data()
        if photo.count > 65_000 { photo = normalized.jpegData(compressionQuality: 0.2) ?? Data() }
        if photo.count > 65_000 {
            let small = UIGraphicsImageRenderer(
                size: CGSize(width: size.width / 2, height: size.height / 2), format: format
            )
            .image { _ in
                normalized.draw(
                    in: CGRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2))
            }
            photo = small.jpegData(compressionQuality: 0.35) ?? Data()
        }
        guard photo.count <= 65_000 else {
            error = "Try a smaller photo."
            analyzing = false
            return
        }
        draft = InventoryFood(photoBase64: photo.base64EncodedString())
        originalPhotoBase64 = draft.photoBase64
        if store.isBackend {
            do {
                let analysis = try await store.analyzeFoodPhoto(draft.photoBase64)
                guard current == generation else { return }
                draft.name = analysis.name
                draft.variety = InventoryFood.cleanVariety(analysis.variety, foodName: analysis.name)
                draft.category = analysis.category
                draft.condition = analysis.condition
                draft.quantity = analysis.quantity
                draft.storage = analysis.storage
                draft.confidence = analysis.confidence
                draft.identification = "Gemini"
                draft.analysis = String(decoding: try JSONEncoder().encode(analysis), as: UTF8.self)
                if analysis.confidence >= 0.7, analysis.box.count == 4, let cg = normalized.cgImage {
                    let box = analysis.box
                    let width = Double(cg.width), height = Double(cg.height)
                    let rect = CGRect(x: box[1] / 1000 * width, y: box[0] / 1000 * height, width: (box[3] - box[1]) / 1000 * width, height: (box[2] - box[0]) / 1000 * height)
                        .insetBy(dx: -width * 0.04, dy: -height * 0.04)
                        .intersection(CGRect(x: 0, y: 0, width: width, height: height))
                    if rect.width > width * 0.15, rect.height > height * 0.15,
                        let crop = cg.cropping(to: rect), let data = UIImage(cgImage: crop).jpegData(compressionQuality: 0.5), data.count <= 65_000 {
                        draft.photoBase64 = data.base64EncodedString()
                    }
                }
            } catch {
                guard current == generation else { return }
                self.error = "Couldn't analyze this photo with Gemini. \(error.localizedDescription). You can fill in the details or try again."
            }
            analyzing = false
            return
        }
        let result = await Task.detached(priority: .userInitiated) { () -> (String, Double)? in
            let request = VNClassifyImageRequest()
            do {
                try VNImageRequestHandler(data: photo).perform([request])
                let foods = [
                    "banana", "tomato", "apple", "orange", "avocado", "strawberry", "broccoli",
                    "carrot", "potato", "lemon", "pear", "grape", "pepper", "cucumber",
                ]
                for candidate in request.results ?? [] where candidate.confidence >= 0.2 {
                    if let food = foods.first(where: {
                        candidate.identifier.lowercased().contains($0)
                    }) {
                        return (food.capitalized, Double(candidate.confidence))
                    }
                }
            } catch { return nil }
            return nil
        }.value
        guard current == generation else { return }
        if let result {
            draft.name = result.0
            draft.confidence = result.1
            draft.identification = "Apple Vision"
        }
        analyzing = false
    }
}

/// Connects only to the Nano climate service; throttled samples feed the private history adapter.
@MainActor @Observable
final class StorageSensorConnection: NSObject, CBCentralManagerDelegate,
    CBPeripheralDelegate
{
    var devices: [CBPeripheral] = []
    var connected: CBPeripheral?
    var searching = false
    var connectingID: UUID?
    var status = "Not connected"
    var stream = ClimateStream()
    var stale = false
    var notificationsEnabled = false
    @ObservationIgnored var onSample: ((ClimatePacket, String) -> Void)?
    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var pending: CBPeripheral?
    @ObservationIgnored private var measurement: CBCharacteristic?
    @ObservationIgnored private var wantsScan = false
    @ObservationIgnored private var scanTimeout: Task<Void, Never>?
    @ObservationIgnored private var connectionTimeout: Task<Void, Never>?
    @ObservationIgnored private var staleTimeout: Task<Void, Never>?
    private let serviceID = CBUUID(string: ClimatePacket.serviceUUID)
    private let characteristicID = CBUUID(string: ClimatePacket.characteristicUUID)

    func search() {
        guard connected == nil, pending == nil else { return }
        stopSearch()
        wantsScan = true
        devices = []
        #if targetEnvironment(simulator)
            wantsScan = false
            status = "Use a physical iPhone to connect to your sensor"
            return
        #else
            if central == nil {
                central = CBCentralManager(delegate: self, queue: .main)
            } else {
                updateBluetoothState()
            }
        #endif
    }
    private func updateBluetoothState() {
        guard let central else { return }
        switch central.state {
        case .poweredOn: beginSearch()
        case .poweredOff, .unauthorized, .unsupported:
            stopSearch()
            clearConnection()
            switch central.state {
            case .poweredOff: status = "Turn on Bluetooth in Settings"
            case .unauthorized: status = "Allow Bluetooth for Gusto in Settings"
            default: status = "Bluetooth is unavailable on this device"
            }
        default:
            central.stopScan()
            scanTimeout?.cancel()
            scanTimeout = nil
            searching = false
            clearConnection()
            status = "Preparing Bluetooth…"
        }
    }
    private func beginSearch() {
        guard let central, central.state == .poweredOn, wantsScan, !searching else { return }
        searching = true
        status = "Looking for MHacks Climate…"
        central.scanForPeripherals(
            withServices: [serviceID],
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ])
        scanTimeout?.cancel()
        scanTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            self?.stopSearch()
        }
    }
    func stopSearch() {
        scanTimeout?.cancel()
        scanTimeout = nil
        central?.stopScan()
        let wasSearching = searching
        searching = false
        wantsScan = false
        if wasSearching && connected == nil && pending == nil {
            status =
                devices.isEmpty
                ? "No sensor found. Hold the blue button and try again." : "Choose your sensor"
        }
    }
    func connect(_ device: CBPeripheral) {
        guard central?.state == .poweredOn, connected == nil, pending == nil,
            devices.contains(where: { $0.identifier == device.identifier })
        else { return }
        stopSearch()
        stream = ClimateStream()
        stale = false
        pending = device
        connectingID = device.identifier
        status = "Connecting…"
        central?.connect(device)
        connectionTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self,
                self.pending != nil || (self.connected != nil && !self.notificationsEnabled)
            else { return }
            self.fail("Connection timed out. Hold the blue button and try again.")
        }
    }
    private func clearConnection() {
        connectionTimeout?.cancel()
        connectionTimeout = nil
        staleTimeout?.cancel()
        staleTimeout = nil
        connected?.delegate = nil
        pending?.delegate = nil
        pending = nil
        connected = nil
        connectingID = nil
        measurement = nil
        notificationsEnabled = false
        stream = ClimateStream()
        stale = false
    }
    func disconnect() {
        stopSearch()
        if let device = connected ?? pending {
            if let measurement, measurement.isNotifying {
                device.setNotifyValue(false, for: measurement)
            }
            central?.cancelPeripheralConnection(device)
        }
        clearConnection()
        status = "Disconnected"
    }
    private func fail(_ message: String) {
        disconnect()
        status = message
    }
    private func accept(_ data: Data) {
        guard stream.receive(data, at: .now) else { return }
        if let packet = stream.packet, let connected { onSample?(packet, connected.identifier.uuidString) }
        stale = false
        status = notificationsEnabled ? "Connected" : "Reading sensor…"
        staleTimeout?.cancel()
        staleTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard let self, self.connected != nil, !self.stream.isFresh(at: .now) else { return }
            self.stale = true
            self.status = "Readings paused · no new sample for 5 seconds"
        }
    }
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            guard self.central === central else { return }
            updateBluetoothState()
        }
    }
    nonisolated func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            guard self.central === central, searching else { return }
            if !devices.contains(where: { $0.identifier == peripheral.identifier }) {
                devices.append(peripheral)
            }
        }
    }
    nonisolated func centralManager(
        _ central: CBCentralManager, didConnect peripheral: CBPeripheral
    ) {
        Task { @MainActor in
            guard self.central === central, pending === peripheral else {
                central.cancelPeripheralConnection(peripheral)
                return
            }
            pending = nil
            connected = peripheral
            connectingID = nil
            peripheral.delegate = self
            status = "Discovering sensor service…"
            peripheral.discoverServices([serviceID])
        }
    }
    nonisolated func centralManager(
        _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
    ) {
        Task { @MainActor in
            guard self.central === central, pending === peripheral else { return }
            fail("Couldn't connect. Hold the blue button and try again.")
        }
    }
    nonisolated func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
    ) {
        Task { @MainActor in
            guard self.central === central, connected === peripheral || pending === peripheral
            else { return }
            clearConnection()
            status = "Disconnected. Hold the blue button to reconnect."
        }
    }
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard connected === peripheral else { return }
            guard error == nil,
                let service = peripheral.services?.first(where: { $0.uuid == serviceID })
            else {
                fail("This device doesn't provide the climate service.")
                return
            }
            status = "Preparing live readings…"
            peripheral.discoverCharacteristics([characteristicID], for: service)
        }
    }
    nonisolated func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
    ) {
        Task { @MainActor in
            guard connected === peripheral, service.uuid == serviceID else { return }
            guard error == nil,
                let characteristic = service.characteristics?.first(where: {
                    $0.uuid == characteristicID
                }),
                characteristic.properties.contains(.read),
                characteristic.properties.contains(.notify)
            else {
                fail("The climate reading characteristic is unavailable.")
                return
            }
            measurement = characteristic
            peripheral.readValue(for: characteristic)
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    nonisolated func peripheral(
        _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            guard connected === peripheral, measurement === characteristic else { return }
            guard error == nil, characteristic.isNotifying else {
                fail("Couldn't start live readings. Reconnect your sensor.")
                return
            }
            connectionTimeout?.cancel()
            connectionTimeout = nil
            notificationsEnabled = true
            status =
                stream.isFresh(at: .now)
                ? "Live · updating every second" : "Connected · waiting for a sample"
        }
    }
    nonisolated func peripheral(
        _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        // Copy the value at callback time; the characteristic is mutable between notifications.
        let data = characteristic.value
        Task { @MainActor in
            guard connected === peripheral, measurement === characteristic else { return }
            guard error == nil, let data else {
                fail("Couldn't read the sensor. Reconnect and try again.")
                return
            }
            accept(data)
        }
    }
}

struct FoodCameraCapture: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
        UINavigationControllerDelegate
    {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            completion(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
    }
}
