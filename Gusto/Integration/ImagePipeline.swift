import CryptoKit
import Foundation
import UIKit

/// Immutable image URLs share downloads across views, with four network slots and bounded LRU caches.
actor ImagePipeline {
    static let shared = ImagePipeline()
    private var memory: [String: UIImage] = [:]
    private var memoryOrder: [String] = []
    private var memoryBytes = 0
    private var tasks: [String: Task<UIImage, Error>] = [:]
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let folder: URL
    private(set) var downloads = 0
    private(set) var bytes = 0
    init() {
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GustoImages")
    }
    private func acquire() async {
        if active < 4 {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if waiters.isEmpty { active -= 1 } else { waiters.removeFirst().resume() }
    }
    func image(_ reference: String) async throws -> UIImage {
        let url =
            reference.hasPrefix("/")
            ? URL(string: "http://127.0.0.1:8081\(reference)")! : URL(string: reference)!
        let key = url.absoluteString
        if let image = memory[key] {
            memoryOrder.removeAll { $0 == key }
            memoryOrder.append(key)
            return image
        }
        if let task = tasks[key] { return try await task.value }
        let filename = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = folder.appendingPathComponent(filename)
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            remember(image, key: key)
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()], ofItemAtPath: file.path)
            return image
        }
        let task = Task<UIImage, Error> {
            await self.acquire()
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                    let image = UIImage(data: data)
                else { throw RepositoryError.invalidResponse }
                self.downloads += 1
                self.bytes += data.count
                try FileManager.default.createDirectory(
                    at: self.folder, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
                try self.evict()
                self.release()
                return image
            } catch {
                self.release()
                throw error
            }
        }
        tasks[key] = task
        defer { tasks[key] = nil }
        let image = try await task.value
        remember(image, key: key)
        return image
    }
    private func remember(_ image: UIImage, key: String) {
        let cost = decodedCost(image)
        guard cost <= 50 * 1024 * 1024 else { return }
        if let old = memory.removeValue(forKey: key) { memoryBytes -= decodedCost(old) }
        memoryOrder.removeAll { $0 == key }
        while memoryBytes + cost > 50 * 1024 * 1024, !memoryOrder.isEmpty {
            let oldest = memoryOrder.removeFirst()
            if let old = memory.removeValue(forKey: oldest) { memoryBytes -= decodedCost(old) }
        }
        memory[key] = image
        memoryOrder.append(key)
        memoryBytes += cost
    }
    private func decodedCost(_ image: UIImage) -> Int {
        (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
    }
    private func evict() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        let sorted = files.sorted {
            (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
                < (try? $1.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
        }
        var total = sorted.reduce(0) {
            $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        for file in sorted where total > 200 * 1024 * 1024 {
            total -= (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try FileManager.default.removeItem(at: file)
        }
    }
}
