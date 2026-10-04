import Foundation
import Observation
import Security

@MainActor @Observable final class SessionController: SessionProvider {
    static let shared = SessionController()
    private(set) var accounts: [BackendSession] = []
    private(set) var current: BackendSession?
    private let service = "com.mhacks.rescue.demo-sessions"
    private let key = "sessions"
    private var observers: [UUID: AsyncStream<BackendSession>.Continuation] = [:]
    private struct Stored: Codable {
        let accounts: [BackendSession]
        let selected: String
    }
    init() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: key,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            let stored = try? JSONDecoder().decode(Stored.self, from: data)
        {
            accounts = stored.accounts
            current = accounts.first { $0.userId == stored.selected }
        }
    }
    func loadDemoAccounts() async throws {
        #if DEBUG
            let url = URL(string: "http://127.0.0.1:8081/dev/accounts")!
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw RepositoryError.server("service_unavailable")
            }
            struct Provisioned: Decodable {
                let database: String
                let accounts: [BackendSession]
            }
            let value = try JSONDecoder().decode(Provisioned.self, from: data)
            guard value.database == "mhacksdb", value.accounts.count == 12 else {
                throw RepositoryError.invalidResponse
            }
            accounts = value.accounts
            current = accounts.first { $0.userId == (current?.userId ?? "demo-buyer") }
            try persist()
        #else
            throw RepositoryError.server("service_unavailable")
        #endif
    }
    func select(_ id: String) throws {
        guard let session = accounts.first(where: { $0.userId == id }) else {
            throw RepositoryError.server("unauthorized")
        }
        current = session
        try persist()
        for observer in observers.values { observer.yield(session) }
    }
    private func persist() throws {
        let data = try JSONEncoder().encode(
            Stored(accounts: accounts, selected: current?.userId ?? ""))
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            throw RepositoryError.server("keychain_unavailable")
        }
    }
    func currentSession() async throws -> BackendSession {
        guard let current else { throw RepositoryError.server("unauthorized") }
        return current
    }
    func changes() async -> AsyncStream<BackendSession> {
        let id = UUID()
        return AsyncStream { continuation in
            observers[id] = continuation
            if let current { continuation.yield(current) }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.observers[id] = nil }
            }
        }
    }
    func repository() throws -> HTTPRepository {
        guard let current else { throw RepositoryError.server("unauthorized") }
        let cache = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RescueCache", isDirectory: true)
        return HTTPRepository(
            server: URL(string: "http://127.0.0.1:3000")!, database: "mhacksdb", session: current,
            cacheRoot: cache)
    }
}
