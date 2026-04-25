import Foundation

public struct User: Sendable, Codable {
    public let id: String
    public let email: String?
    public let name: String?
    public let role: String?
    public let source: String?
}

public struct UserAPI: Sendable {
    let client: FloopFloop

    public func me() async throws -> User {
        try await client.request(method: "GET", path: "/api/v1/user/me")
    }
}
