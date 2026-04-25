import Foundation

public struct ApiKeySummary: Sendable, Codable {
    public let id: String
    public let name: String
    public let keyPrefix: String
    public let lastUsedAt: String?
    public let createdAt: String
}

public struct IssuedApiKey: Sendable, Codable {
    public let id: String
    public let rawKey: String
    public let keyPrefix: String
}

public struct ApiKeys: Sendable {
    let client: FloopFloop

    private struct ListEnvelope: Decodable {
        let keys: [ApiKeySummary]
    }

    public func list() async throws -> [ApiKeySummary] {
        let env: ListEnvelope = try await client.request(method: "GET", path: "/api/v1/api-keys")
        return env.keys
    }

    /// Mint a new API key. The returned `IssuedApiKey.rawKey` is the
    /// **only** time the full secret is exposed — surface it once and
    /// never persist it.
    public func create(name: String) async throws -> IssuedApiKey {
        struct Body: Encodable { let name: String }
        return try await client.request(method: "POST", path: "/api/v1/api-keys", body: Body(name: name))
    }

    /// Revoke an API key by id or human-readable name. Lists first to
    /// accept either form, then DELETEs by id.
    public func remove(_ idOrName: String) async throws {
        let all = try await list()
        guard let match = all.first(where: { $0.id == idOrName || $0.name == idOrName }) else {
            throw FloopError(code: .notFound, status: 404, message: "API key not found: \(idOrName)")
        }
        try await client.requestEmpty(method: "DELETE", path: "/api/v1/api-keys/\(percentEncode(match.id))")
    }
}
