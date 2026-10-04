import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Account-scoped transport, metadata cache and durable retry outbox. UI never constructs HTTP.
public actor HTTPRepository: RescueRepository {
    public nonisolated let accountID: String
    private let session: BackendSession
    private let sessionProvider: (@Sendable () async throws -> BackendSession)?
    private let server: URL
    private let database: String
    private let folder: URL
    private let network: URLSession
    private var inFlight: [String: Task<APIResponse, Error>] = [:]
    private var inFlightRequests: [String: APIRequest] = [:]
    private var replaying = false
    public private(set) var requestCount = 0
    public private(set) var transferredBytes = 0
    public private(set) var cacheHits = 0
    public private(set) var responseMilliseconds: Double = 0
    private struct CacheEntry: Codable {
        let key: String
        let updated: Date
        let payload: Data
    }

    public init(
        server: URL, database: String, session: BackendSession, cacheRoot: URL,
        network: URLSession = .shared,
        sessionProvider: (@Sendable () async throws -> BackendSession)? = nil
    ) {
        self.server = server
        self.database = database
        self.session = session
        self.sessionProvider = sessionProvider
        self.network = network
        accountID = session.userId
        let namespace = Data("\(server.absoluteString)/\(database)/\(session.userId)".utf8)
            .base64EncodedString().replacingOccurrences(of: "/", with: "_")
        folder = cacheRoot.appendingPathComponent(namespace, isDirectory: true)
    }
    private func prepareFolder() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: folder.path)
        #endif
    }
    private func cacheURL(_ key: String) -> URL {
        // Stable filename independent of randomized Swift Hasher. Full key is validated on read.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return folder.appendingPathComponent("\(hash).json")
    }
    public func cached(_ key: String, maxAge: TimeInterval = .infinity) -> Data? {
        guard let bytes = try? Data(contentsOf: cacheURL(key)),
            let entry = try? JSONDecoder().decode(CacheEntry.self, from: bytes), entry.key == key,
            Date().timeIntervalSince(entry.updated) <= maxAge
        else { return nil }
        cacheHits += 1
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: cacheURL(key).path)
        return entry.payload
    }
    private func persist(_ response: APIResponse, request: APIRequest) throws {
        try prepareFolder()
        var payload = response.payload
        if request.action == "bootstrap",
            var snapshot = try? JSONDecoder().decode(BackendBootstrap.self, from: payload)
        {
            guard snapshot.user.id == accountID else {
                throw RepositoryError.server("unauthorized")
            }
            snapshot.stripPrivateLocations(at: response.serverTime)
            payload = try JSONEncoder().encode(snapshot)
        }
        if request.action == "messages",
            let page = try? JSONDecoder().decode(BackendMessages.self, from: payload)
        {
            var base = request
            base.cursor = ""
            let previousData = cached(base.cacheKey, maxAge: .infinity)
            let previous = previousData.flatMap {
                try? JSONDecoder().decode(BackendMessages.self, from: $0)
            }
            let ids = Set(page.messages.map(\.id))
            let merged =
                ((previous?.messages ?? []).filter { !ids.contains($0.id) } + page.messages).sorted
            { $0.sequence < $1.sequence }
            let summary = BackendMessages(
                messages: Array(merged.suffix(300)),
                lastSequence: max(page.lastSequence, previous?.lastSequence ?? 0),
                cursor: page.cursor)
            let latest = CacheEntry(
                key: base.cacheKey, updated: Date(), payload: try JSONEncoder().encode(summary))
            try JSONEncoder().encode(latest).write(to: cacheURL(base.cacheKey), options: .atomic)
        }
        let entry = CacheEntry(key: request.cacheKey, updated: Date(), payload: payload)
        if request.action != "messages" || !request.cursor.isEmpty {
            try JSONEncoder().encode(entry).write(to: cacheURL(request.cacheKey), options: .atomic)
        }
        try evict()
    }
    private func evict() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )
        .filter { $0.lastPathComponent != "outbox.json" }
        let sorted = files.sorted {
            (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
                < (try? $1.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
        }
        var size = sorted.reduce(0) {
            $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        for file in sorted where size > 20 * 1024 * 1024 {
            size -= (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try FileManager.default.removeItem(at: file)
        }
    }
    public func request(_ request: APIRequest) async throws -> APIResponse {
        let key = request.operationId.isEmpty ? request.cacheKey : request.operationId
        if let task = inFlight[key] {
            guard inFlightRequests[key] == request else {
                throw RepositoryError.server("stale_version")
            }
            return try await task.value
        }
        let endpoint = server.appendingPathComponent("v1/database/\(database)/call/api")
        let activeSession = try await sessionProvider?() ?? session
        guard activeSession.userId == accountID else {
            throw RepositoryError.server("unauthorized")
        }
        // The session provider may refresh asynchronously; another request can start meanwhile.
        if let task = inFlight[key] {
            guard inFlightRequests[key] == request else {
                throw RepositoryError.server("stale_version")
            }
            return try await task.value
        }
        let token = activeSession.token
        let network = network
        let task = Task<APIResponse, Error> {
            var http = URLRequest(url: endpoint)
            http.httpMethod = "POST"
            http.timeoutInterval = request.action == "scan_analyze" ? 55 : 15
            http.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            http.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            http.httpBody = try encoder.encode([request])
            let (bytes, response) = try await network.data(for: http)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RepositoryError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                throw RepositoryError.server(
                    httpResponse.statusCode == 401 ? "unauthorized" : "service_unavailable")
            }
            let wire = try JSONSerialization.jsonObject(with: bytes)
            let apiVersion: Int
            let time: Double
            let error: String
            let payload: String
            if let values = wire as? [Any], values.count == 4,
                let version = values[0] as? Int, let stamp = values[1] as? Double,
                let code = values[2] as? String, let data = values[3] as? String
            {
                apiVersion = version
                time = stamp
                error = code
                payload = data
            } else if let values = wire as? [String: Any],
                let version = values["api_version"] as? Int,
                let stamp = values["server_time"] as? Double, let code = values["error"] as? String,
                let data = values["payload"] as? String
            {
                apiVersion = version
                time = stamp
                error = code
                payload = data
            } else {
                throw RepositoryError.invalidResponse
            }
            guard apiVersion == 1 else { throw RepositoryError.invalidResponse }
            guard error.isEmpty else { throw RepositoryError.server(error) }
            return APIResponse(serverTime: time, payload: Data(payload.utf8))
        }
        inFlight[key] = task
        inFlightRequests[key] = request
        requestCount += 1
        let started = Date()
        defer {
            inFlight[key] = nil
            inFlightRequests[key] = nil
        }
        let response = try await task.value
        transferredBytes += response.payload.count
        responseMilliseconds = Date().timeIntervalSince(started) * 1000
        if request.operationId.isEmpty && request.action != "scan_analyze" { try persist(response, request: request) }
        return response
    }
    public func pending() -> [APIRequest] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("outbox.json")) else {
            return []
        }
        return (try? JSONDecoder().decode([APIRequest].self, from: data)) ?? []
    }
    public func failed() -> [APIRequest] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("failed.json")) else {
            return []
        }
        return (try? JSONDecoder().decode([APIRequest].self, from: data)) ?? []
    }
    private func saveOutbox(_ values: [APIRequest]) throws {
        try prepareFolder()
        try JSONEncoder().encode(values).write(
            to: folder.appendingPathComponent("outbox.json"), options: .atomic)
    }
    public func enqueue(_ request: APIRequest) throws {
        guard ["send", "favorite"].contains(request.action), !request.operationId.isEmpty else {
            throw RepositoryError.server("invalid_transition")
        }
        var queue = pending()
        guard queue.count < 1000 else { throw RepositoryError.server("rate_limited") }
        if !queue.contains(where: { $0.operationId == request.operationId }) {
            queue.append(request)
        }
        try saveOutbox(queue)
    }
    public func synchronize() async throws {
        guard !replaying else { return }
        replaying = true
        defer { replaying = false }
        for next in pending().prefix(20) {
            do { _ = try await request(next) } catch RepositoryError.server(let code)
                where ["not_found", "unauthorized", "stale_version", "invalid_transition"].contains(
                    code)
            {
                // Preserve permanent failures for presentation while allowing unrelated operations to proceed.
                var failures = failed()
                failures.append(next)
                try JSONEncoder().encode(failures).write(
                    to: folder.appendingPathComponent("failed.json"), options: .atomic)
            }
            var queue = pending()
            queue.removeAll { $0.operationId == next.operationId }
            try saveOutbox(queue)
        }
    }
    public func clearCache() throws {
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }
}
