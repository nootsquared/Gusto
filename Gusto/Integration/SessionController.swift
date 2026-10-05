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
    private(set) var needsSignIn = false
    private(set) var profileRevision = 0
    private let oauth = OAuthSignIn()
    private var refreshTask: Task<BackendSession, Error>?
    private var nextRefreshAttempt = Date.distantPast
    private var refreshToken: String?
    private var accessToken: String?
    private var expiresAt: Date = .distantPast
    private var subject: String?
    private var generation = UUID()
    private struct Stored: Codable {
        let accounts: [BackendSession]
        let selected: String
        var refreshToken: String?
        var accessToken: String?
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
            accessToken = stored.accessToken
            let claims = current.flatMap { try? GustoOAuth.claims($0.token) }
            expiresAt = stored.expiresAt ?? claims.map { Date(timeIntervalSince1970: $0.exp) } ?? .distantPast
            subject = stored.subject ?? claims?.sub
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
                accessToken: accessToken,
                expiresAt: expiresAt, subject: subject))
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: key,
        ]
        let updated = SecItemUpdate(query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw RepositoryError.server("keychain_unavailable") }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            throw RepositoryError.server("keychain_unavailable")
        }
    }
    func currentSession() async throws -> BackendSession {
        guard let current else { throw RepositoryError.server("unauthorized") }
        if signingIn && expiresAt <= Date() { throw RepositoryError.server("authentication_unavailable") }
        if !isLocalBackend && !signingIn && expiresAt.timeIntervalSinceNow < 90 {
            if let refreshTask { return try await refreshTask.value }
            if nextRefreshAttempt > Date() {
                if expiresAt > Date() { return current }
                throw RepositoryError.server(needsSignIn ? "sign_in_required" : "authentication_unavailable")
            }
            guard let refreshToken else {
                if expiresAt > Date() { return current }
                needsSignIn = true
                throw RepositoryError.server("sign_in_required")
            }
            let generation = generation
            let task = Task { @MainActor in
                let tokens = try await OAuthSignIn.exchange([
                    "grant_type": "refresh_token", "refresh_token": refreshToken,
                ])
                let claims = try GustoOAuth.claims(tokens.id_token)
                guard claims.sub == self.subject, generation == self.generation else {
                    throw RepositoryError.server("sign_in_required")
                }
                let session = BackendSession(userId: current.userId, token: tokens.id_token)
                self.current = session
                self.accounts = [session]
                self.refreshToken = tokens.refresh_token ?? refreshToken
                self.accessToken = tokens.access_token ?? self.accessToken
                self.expiresAt = Date(timeIntervalSince1970: claims.exp)
                try self.persist()
                self.needsSignIn = false
                self.authError = nil
                self.nextRefreshAttempt = .distantPast
                return session
            }
            refreshTask = task
            defer { if generation == self.generation { refreshTask = nil } }
            do { return try await task.value } catch {
                guard generation == self.generation else { throw error }
                nextRefreshAttempt = Date().addingTimeInterval(20)
                if expiresAt > Date() { return current }
                if case RepositoryError.server("sign_in_required") = error {
                    needsSignIn = true
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
        let activeGeneration = UUID()
        generation = activeGeneration
        refreshTask?.cancel()
        refreshTask = nil
        nextRefreshAttempt = .distantPast
        defer { signingIn = false }
        do {
            let tokens = try await oauth.signIn()
            let claims = try GustoOAuth.claims(tokens.id_token)
            let userID = try await registerProfile(token: tokens.id_token)
            guard activeGeneration == generation else { return }
            let session = BackendSession(userId: userID, token: tokens.id_token)
            refreshToken = tokens.refresh_token
            accessToken = tokens.access_token
            expiresAt = Date(timeIntervalSince1970: claims.exp)
            subject = claims.sub
            accounts = [session]
            current = session
            needsSignIn = false
            nextRefreshAttempt = .distantPast
            profileRevision += 1
            do { try persist() } catch {
                throw error
            }
            for observer in observers.values { observer.yield(session) }
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                authError = error.localizedDescription
            }
        }
    }
    func syncProfile() async throws {
        guard !isLocalBackend else { return }
        let session = try await currentSession()
        guard try await registerProfile(token: session.token) == session.userId else {
            throw RepositoryError.server("unauthorized")
        }
        guard let accessToken else { return }
        var request = URLRequest(url: URL(string: "https://auth.spacetimedb.com/oidc/me")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
            let profile = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            profile["sub"] as? String == subject,
            let picture = profile["picture"] as? String,
            URL(string: picture)?.scheme == "https", !picture.isEmpty else { return }
        _ = try await repository().request(APIRequest("profile_photo", text: picture, write: true))
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
        authError = nil
        needsSignIn = false
        nextRefreshAttempt = .distantPast
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        current = nil
        accounts = []
        refreshToken = nil
        accessToken = nil
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
            .appendingPathComponent("GustoCache", isDirectory: true)
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
