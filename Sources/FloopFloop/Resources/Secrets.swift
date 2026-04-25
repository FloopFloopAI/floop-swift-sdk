import Foundation

public struct SecretSummary: Sendable, Codable {
    public let key: String
    public let createdAt: String
    public let updatedAt: String
}

public struct Secrets: Sendable {
    let client: FloopFloop

    public func list(_ ref: String) async throws -> [SecretSummary] {
        try await client.request(method: "GET", path: "/api/v1/projects/\(percentEncode(ref))/secrets")
    }

    public func set(_ ref: String, key: String, value: String) async throws {
        struct Body: Encodable { let key: String; let value: String }
        try await client.requestEmpty(
            method: "POST",
            path: "/api/v1/projects/\(percentEncode(ref))/secrets",
            body: Body(key: key, value: value)
        )
    }

    public func remove(_ ref: String, key: String) async throws {
        try await client.requestEmpty(
            method: "DELETE",
            path: "/api/v1/projects/\(percentEncode(ref))/secrets/\(percentEncode(key))"
        )
    }
}
