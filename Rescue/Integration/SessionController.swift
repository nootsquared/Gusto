import AuthenticationServices
import Foundation
import Observation
import Security

@MainActor @Observable final class SessionController: SessionProvider {
    static let shared = SessionController()
    let isLocalBackend: Bool = {
        #if DEBUG
            return ProcessInfo.processInfo.arguments.contains("--local-backend")
        #else
            return false
        #endif
    }()
    private(set) var accounts: [BackendSession] = []
    private(set) var current: BackendSession?
    private var service: String {
        isLocalBackend
            ? "com.mhacks.rescue.demo-sessions"
            : "com.mhacks.rescue.cloud-sessions.mhacks-pranav-dev-975fp"
    }
    private let key = "sessions"
    private var observers: [UUID: AsyncStream<BackendSession>.Continuation] = [:]
    private(set) var signingIn = false
    private(set) var authError: String?
    private let oauth = OAuthSignIn()
    private var refreshTask: Task<BackendSession, Error>?
    private var refreshToken: String?
    private var expiresAt: Date = .distantPast
    private var subject: String?
    private var generation = UUID()
    private struct Stored: Codable {
        let accounts: [BackendSession]
        let selected: String
        var refreshToken: String?
        var expiresAt: Date?
        var subject: String?
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
            refreshToken = stored.refreshToken
            expiresAt = stored.expiresAt ?? .distantPast
            subject = stored.subject
        }
    }
    func loadDemoAccounts() async throws {
        // Local demo credentials must never be imported into a cloud session.
        guard isLocalBackend else { throw RepositoryError.server("unauthorized") }
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
            Stored(
                accounts: accounts, selected: current?.userId ?? "", refreshToken: refreshToken,
                expiresAt: expiresAt, subject: subject))
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
        if !isLocalBackend && expiresAt.timeIntervalSinceNow < 90 {
            if let refreshTask { return try await refreshTask.value }
            guard let refreshToken else {
                signOut()
                throw RepositoryError.server("sign_in_required")
            }
            let generation = generation
            let task = Task { @MainActor in
                let tokens = try await OAuthSignIn.exchange([
                    "grant_type": "refresh_token", "refresh_token": refreshToken,
                ])
                let claims = try RescueOAuth.claims(tokens.id_token)
                guard claims.sub == self.subject, generation == self.generation else {
                    throw RepositoryError.server("sign_in_required")
                }
                let session = BackendSession(userId: current.userId, token: tokens.id_token)
                self.current = session
                self.accounts = [session]
                self.refreshToken = tokens.refresh_token ?? refreshToken
                self.expiresAt = Date(timeIntervalSince1970: claims.exp)
                try self.persist()
                return session
            }
            refreshTask = task
            defer { refreshTask = nil }
            do { return try await task.value } catch {
                if case RepositoryError.server("sign_in_required") = error,
                    generation == self.generation
                {
                    signOut()
                    authError = "Your session expired. Please sign in again."
                }
                throw error
            }
        }
        return current
    }
    func signIn() async {
        guard !isLocalBackend, !signingIn else { return }
        signingIn = true
        authError = nil
        let activeGeneration = generation
        defer { signingIn = false }
        do {
            let tokens = try await oauth.signIn()
            let claims = try RescueOAuth.claims(tokens.id_token)
            let userID = try await registerProfile(token: tokens.id_token)
            guard activeGeneration == generation else { return }
            let session = BackendSession(userId: userID, token: tokens.id_token)
            refreshToken = tokens.refresh_token
            expiresAt = Date(timeIntervalSince1970: claims.exp)
            subject = claims.sub
            accounts = [session]
            current = session
            do { try persist() } catch {
                signOut()
                throw error
            }
            for observer in observers.values { observer.yield(session) }
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                authError = error.localizedDescription
            }
        }
    }
    private func registerProfile(token: String) async throws -> String {
        var request = URLRequest(
            url: URL(
                string:
                    "https://maincloud.spacetimedb.com/v1/database/mhacks-pranav-dev-975fp/call/register_profile"
            )!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([token])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
            let wire = try JSONSerialization.jsonObject(with: data) as? [Any], wire.count == 4,
            wire[0] as? Int == 1,
            let error = wire[2] as? String, error.isEmpty,
            let payload = wire[3] as? String,
            let body = try JSONSerialization.jsonObject(with: Data(payload.utf8))
                as? [String: String],
            let userID = body["userId"], !userID.isEmpty
        else { throw RepositoryError.server("registration_failed") }
        return userID
    }
    func signOut() {
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        current = nil
        accounts = []
        refreshToken = nil
        subject = nil
        expiresAt = .distantPast
        SecItemDelete(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: key,
            ] as CFDictionary)
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
        let provider: (@Sendable () async throws -> BackendSession)?
        if isLocalBackend {
            provider = nil
        } else {
            provider = { [weak self] in
                guard let self else { throw RepositoryError.server("sign_in_required") }
                return try await self.currentSession()
            }
        }
        return HTTPRepository(
            server: URL(
                string: isLocalBackend
                    ? "http://127.0.0.1:3000" : "https://maincloud.spacetimedb.com")!,
            database: isLocalBackend ? "mhacksdb" : "mhacks-pranav-dev-975fp", session: current,
            cacheRoot: cache,
            sessionProvider: provider)
    }
}
