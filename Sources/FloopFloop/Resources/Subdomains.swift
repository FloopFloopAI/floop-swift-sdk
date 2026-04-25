import Foundation

public struct SubdomainCheckResult: Sendable, Codable {
    public let valid: Bool
    public let available: Bool
    public let error: String?
}

public struct SubdomainSuggestResult: Sendable, Codable {
    public let suggestions: [String]
}

public struct Subdomains: Sendable {
    let client: FloopFloop

    public func check(_ slug: String) async throws -> SubdomainCheckResult {
        try await client.request(method: "GET", path: "/api/v1/subdomains/check?slug=\(percentEncode(slug))")
    }

    public func suggest(_ prompt: String) async throws -> SubdomainSuggestResult {
        try await client.request(method: "GET", path: "/api/v1/subdomains/suggest?prompt=\(percentEncode(prompt))")
    }
}
