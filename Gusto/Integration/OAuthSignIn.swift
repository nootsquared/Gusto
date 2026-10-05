import AuthenticationServices
import Foundation
import Security
import UIKit

@MainActor final class OAuthSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var browserSession: ASWebAuthenticationSession?
    struct Tokens: Decodable {
        let id_token: String
        let refresh_token: String?
        let access_token: String?
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    private func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw RepositoryError.server("authentication_unavailable")
        }
        return GustoOAuth.base64URL(Data(bytes))
    }
    func signIn() async throws -> Tokens {
        let verifier = try random()
        let state = try random()
        let nonce = try random()
        var parts = URLComponents(string: "\(GustoOAuth.issuer)/auth")!
        parts.queryItems = [
            URLQueryItem(name: "client_id", value: GustoOAuth.clientID),
            URLQueryItem(name: "redirect_uri", value: GustoOAuth.redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid profile email offline_access"),
            URLQueryItem(name: "state", value: state), URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: GustoOAuth.challenge(verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        defer { browserSession = nil }
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: parts.url!, callbackURLScheme: "com.mhacks.rescue"
            ) {
                url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: RepositoryError.invalidResponse)
                }
            }
            session.presentationContextProvider = self
            browserSession = session
            if !session.start() {
                continuation.resume(throwing: RepositoryError.server("authentication_unavailable"))
            }
        }
        let code = try GustoOAuth.callbackCode(callback, state: state)
        let tokens = try await Self.exchange([
            "grant_type": "authorization_code", "code": code, "code_verifier": verifier,
            "redirect_uri": GustoOAuth.redirect,
        ])
        _ = try GustoOAuth.claims(tokens.id_token, nonce: nonce)
        return tokens
    }
    static func exchange(_ fields: [String: String]) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "\(GustoOAuth.issuer)/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(
            (fields.merging(["client_id": GustoOAuth.clientID]) { _, new in new })
                .sorted { $0.key < $1.key }.map {
                    "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
                }.joined(separator: "&").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RepositoryError.invalidResponse }
        guard http.statusCode == 200 else {
            struct Failure: Decodable { let error: String }
            let code =
                (try? JSONDecoder().decode(Failure.self, from: data).error)
                ?? "authentication_unavailable"
            throw RepositoryError.server(
                code == "invalid_grant" ? "sign_in_required" : "authentication_unavailable")
        }
        return try JSONDecoder().decode(Tokens.self, from: data)
    }
}
