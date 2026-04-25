import Foundation

public struct UsageSummary: Sendable, Codable {
    public struct Plan: Sendable, Codable {
        public let name: String?
        public let code: String?
    }
    public struct Credits: Sendable, Codable {
        public let totalAvailable: Double?
        public let perPeriodAllowance: Double?
        public let perPeriodUsed: Double?
        public let rolloverBalance: Double?
        public let rolloverExpiresAt: String?
    }
    public struct Builds: Sendable, Codable {
        public let countThisPeriod: Int?
        public let limit: Int?
    }
    public struct Storage: Sendable, Codable {
        public let bytesUsed: Int64?
        public let bytesLimit: Int64?
    }

    public let plan: Plan?
    public let credits: Credits?
    public let builds: Builds?
    public let storage: Storage?
}

public struct Usage: Sendable {
    let client: FloopFloop

    public func summary() async throws -> UsageSummary {
        try await client.request(method: "GET", path: "/api/v1/usage/summary")
    }
}
