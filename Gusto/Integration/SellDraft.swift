import Foundation

struct SellDraft: Codable, Equatable {
    var name: String
    var price: Int
    var freshness: Freshness
    var pickup: String
    var confirmations: Set<String>
    var hasPhoto: Bool
    static func file(account: String) -> URL {
        let namespace = Data(account.utf8).base64EncodedString().replacingOccurrences(
            of: "/", with: "_")
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SellDraft-\(namespace).json")
    }
    static func load(account: String) -> SellDraft? {
        guard let data = try? Data(contentsOf: file(account: account)) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    func save(account: String) {
        let file = Self.file(account: account)
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(
            to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func clear(account: String) {
        try? FileManager.default.removeItem(at: file(account: account))
    }
}
