import CoreBluetooth
import Observation
import SwiftUI
import Vision

@MainActor @Observable final class FoodScanController {
    var draft = InventoryFood()
    var analyzing = false
    var error: String?
    var sensor = StorageSensorConnection()
    private var generation = UUID()
    func reset() {
        generation = UUID()
        draft = InventoryFood()
        analyzing = false
        error = nil
        sensor.stopSearch()
        sensor.disconnect()
    }

    func identify(_ image: UIImage) async {
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

/// Bluetooth pairing works independently from the future firmware's measurement protocol.
/// No characteristic payload is treated as food data until its UUID and units are configured.
@MainActor @Observable final class StorageSensorConnection: NSObject, CBCentralManagerDelegate {
    var devices: [CBPeripheral] = []
    var connected: CBPeripheral?
    var searching = false
    var connectingID: UUID?
    var status = "Not connected"
    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var wantsScan = false
    func search() {
        wantsScan = true
        devices = []
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            beginSearch()
        }
    }
    private func beginSearch() {
        guard let central, central.state == .poweredOn, wantsScan else { return }
        searching = true
        status = "Looking for nearby devices…"
        central.scanForPeripherals(
            withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        Task {
            try? await Task.sleep(for: .seconds(12))
            stopSearch()
        }
    }
    func stopSearch() {
        central?.stopScan()
        searching = false
        wantsScan = false
        if connected == nil && connectingID == nil {
            status = devices.isEmpty ? "No devices found" : "Choose your sensor"
        }
    }
    func connect(_ device: CBPeripheral) {
        stopSearch()
        connectingID = device.identifier
        status = "Connecting…"
        central?.connect(device)
    }
    func disconnect() { if let connected { central?.cancelPeripheralConnection(connected) } }
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn: beginSearch()
            case .poweredOff:
                searching = false
                status = "Turn on Bluetooth in Settings"
            case .unauthorized:
                searching = false
                status = "Allow Bluetooth in Settings"
            case .unsupported:
                searching = false
                status = "Bluetooth is unavailable on this device"
            default: status = "Preparing Bluetooth…"
            }
        }
    }
    nonisolated func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            guard let name = peripheral.name, !name.isEmpty else { return }
            if !devices.contains(where: { $0.identifier == peripheral.identifier }) {
                devices.append(peripheral)
            }
        }
    }
    nonisolated func centralManager(
        _ central: CBCentralManager, didConnect peripheral: CBPeripheral
    ) {
        Task { @MainActor in
            connected = peripheral
            connectingID = nil
            status = "Bluetooth connected"
        }
    }
    nonisolated func centralManager(
        _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
    ) {
        Task { @MainActor in
            connectingID = nil
            status = "Couldn't connect. Try again."
        }
    }
    nonisolated func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
    ) {
        Task { @MainActor in
            connected = nil
            connectingID = nil
            status = "Disconnected"
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
