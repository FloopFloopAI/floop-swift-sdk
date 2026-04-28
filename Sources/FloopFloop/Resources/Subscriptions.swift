import Foundation

/// Plan + billing snapshot for the authenticated user. Returned by
/// `subscriptions.current()`. Sensitive fields (Stripe customer /
/// subscription IDs, invoice metadata) are deliberately omitted from
/// the wire shape on the backend.
public struct SubscriptionPlan: Sendable, Codable {
    public let status: String
    public let billingPeriod: String?
    public let currentPeriodStart: String
    public let currentPeriodEnd: String
    public let canceledAt: String?
    public let planName: String
    public let planDisplayName: String
    public let priceMonthly: Int
    public let priceAnnual: Int
    public let monthlyCredits: Int
    public let maxProjects: Int
    public let maxStorageMb: Int
    public let maxBandwidthMb: Int
    public let creditRolloverMonths: Int
    /// Free-form feature-flag bag, modelled as `[String: AnyCodableValue]` so
    /// callers can inspect new flags without us cutting a release each
    /// time the backend grows a key.
    public let features: [String: AnyCodableValue]
}

/// Credit-balance snapshot — second half of the
/// `/api/v1/subscriptions/current` response.
public struct SubscriptionCredits: Sendable, Codable {
    public let current: Int
    public let rolledOver: Int
    public let total: Int
    public let rolloverExpiresAt: String?
    public let lifetimeUsed: Int
}

/// Response envelope for `Subscriptions.current()`. Both fields are
/// independently nullable: a user may exist without an active
/// subscription (mid-signup, cancelled with no grace credits remaining).
/// Treat `nil` as "no active subscription data" rather than an error.
public struct CurrentSubscription: Sendable, Codable {
    public let subscription: SubscriptionPlan?
    public let credits: SubscriptionCredits?
}

/// Resource namespace for plan + credit-balance.
///
/// Distinct from ``Usage`` — `usage.summary()` returns current-period
/// consumption (credits remaining + builds used + storage), while
/// `subscriptions.current()` returns the plan tier itself (price, billing
/// period, cancel state). They overlap on `monthlyCredits` and
/// `maxProjects` but serve different audiences:
/// `usage.summary()` for "am I about to hit my limits?",
/// `subscriptions.current()` for "what plan am I on, and when does it
/// renew?".
public struct Subscriptions: Sendable {
    let client: FloopFloop

    public func current() async throws -> CurrentSubscription {
        try await client.request(method: "GET", path: "/api/v1/subscriptions/current")
    }
}

/// Type-erased JSON value for the `features` map on ``SubscriptionPlan``.
/// Mirrors what every other SDK calls "any value" — Go uses `map[string]any`,
/// Rust uses `serde_json::Value`, Python returns the raw dict. Swift needs
/// an explicit Codable enum to round-trip arbitrary JSON.
public enum AnyCodableValue: Sendable, Codable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Int.self) {
            self = .int(v)
        } else if let v = try? c.decode(Double.self) {
            self = .double(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([AnyCodableValue].self) {
            self = .array(v)
        } else if let v = try? c.decode([String: AnyCodableValue].self) {
            self = .object(v)
        } else {
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Unsupported JSON value type"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}
