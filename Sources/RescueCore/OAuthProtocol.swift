import CryptoKit
import Foundation

public enum RescueOAuth {
    public static let issuer = "https://auth.spacetimedb.com/oidc"
    public static let clientID = "client_034Zwg7ImCF86DX87V53K8"
    public static let projectID = "project_034Zwg7HzgCGNFHV6q3NX5"
    public static let redirect = "com.mhacks.rescue://oauth/callback"

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    public static func challenge(_ verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
    public static func callbackCode(_ url: URL, state: String) throws -> String {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.scheme == "com.mhacks.rescue", parts.host == "oauth", parts.path == "/callback"
        else { throw RepositoryError.server("invalid_auth_callback") }
        let items = parts.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1,
            items.first(where: { $0.name == "state" })?.value == state,
            items.first(where: { $0.name == "iss" })?.value.map({ $0 == issuer }) ?? true,
            !items.contains(where: { $0.name == "error" }),
            items.filter({ $0.name == "code" }).count == 1,
            let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty
        else { throw RepositoryError.server("invalid_auth_callback") }
        return code
    }
    public struct Claims: Decodable, Sendable {
        public let iss: String
        public let sub: String
        public let aud: Audience
        public let exp: Double
        public let nonce: String?
        public let azp: String?
        public let project_id: String
    }
    public enum Audience: Decodable, Sendable {
        case one(String), many([String])
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let one = try? container.decode(String.self) {
                self = .one(one)
            } else {
                self = .many(try container.decode([String].self))
            }
        }
        var matches: Bool {
            switch self {
            case .one(let value): return value == clientID
            case .many(let values): return values.contains(clientID)
            }
        }
        var requiresAuthorizedParty: Bool {
            if case .many(let values) = self { return values.count > 1 }
            return false
        }
    }
    // These checks bind the response to this flow. Server registration verifies the signature
    // and the authenticated caller before any profile or session is accepted.
    public static func claims(_ token: String, nonce: String? = nil, now: Date = Date()) throws
        -> Claims
    {
        let pieces = token.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3 else { throw RepositoryError.invalidResponse }
        var payload = String(pieces[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { throw RepositoryError.invalidResponse }
        let value = try JSONDecoder().decode(Claims.self, from: data)
        guard value.iss == issuer, value.project_id == projectID, value.aud.matches,
            !value.sub.isEmpty, value.exp > now.timeIntervalSince1970,
            !value.aud.requiresAuthorizedParty || value.azp == clientID,
            nonce == nil || value.nonce == nonce
        else { throw RepositoryError.server("invalid_auth_token") }
        return value
    }
}
