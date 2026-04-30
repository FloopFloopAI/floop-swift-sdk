import Foundation

/// Single error type thrown by every SDK call on non-2xx responses and on
/// network / timeout failures. Inspect ``code`` to branch — unknown server
/// codes pass through verbatim in ``code.rawValue`` rather than raising a
/// subclass we'd have to keep in sync.
///
/// Mirrors the Node / Python / Go / Rust / Ruby / PHP SDK error taxonomy.
public struct FloopError: Error, Sendable, CustomStringConvertible {
    /// Application error code. Use ``FloopErrorCode`` to pattern-match the
    /// known set; unknown server codes pass through as ``.other(String)``.
    public let code: FloopErrorCode

    /// HTTP status code. ``0`` for transport-level failures.
    public let status: Int

    /// Human-readable message from the server (or a local description for
    /// network errors).
    public let message: String

    /// The server's `x-request-id` header value, when present. Quote it in
    /// bug reports — it lets support pull the trace.
    public let requestId: String?

    /// Seconds to wait before retrying, parsed from the `Retry-After`
    /// response header (delta-seconds OR HTTP-date). `nil` when not set.
    public let retryAfter: TimeInterval?

    public init(
        code: FloopErrorCode,
        status: Int = 0,
        message: String,
        requestId: String? = nil,
        retryAfter: TimeInterval? = nil
    ) {
        self.code = code
        self.status = status
        self.message = message
        self.requestId = requestId
        self.retryAfter = retryAfter
    }

    public var description: String {
        var parts = "floop: [\(code.rawValue)"
        if status > 0 { parts += " \(status)" }
        parts += "] \(message)"
        if let requestId { parts += " (request \(requestId))" }
        return parts
    }
}

extension FloopError: LocalizedError {
    public var errorDescription: String? { description }
}

/// Error codes returned by the FloopFloop API plus a few the SDK itself
/// produces for transport-level failures. Unknown server codes pass through
/// verbatim via ``.other(String)`` so callers can branch on new codes
/// without an SDK update.
public enum FloopErrorCode: Sendable, Equatable {
    case unauthorized
    case forbidden
    case validationError
    case rateLimited
    case notFound
    case conflict
    case serviceUnavailable
    case serverError
    case networkError
    case timeout
    case buildFailed
    case buildCancelled
    case insufficientCredits
    case paymentFailed
    case unknown
    /// Any server code the SDK doesn't have a dedicated case for.
    case other(String)

    /// The canonical uppercase string used on the wire and in the other SDKs.
    public var rawValue: String {
        switch self {
        case .unauthorized:        return "UNAUTHORIZED"
        case .forbidden:           return "FORBIDDEN"
        case .validationError:     return "VALIDATION_ERROR"
        case .rateLimited:         return "RATE_LIMITED"
        case .notFound:            return "NOT_FOUND"
        case .conflict:            return "CONFLICT"
        case .serviceUnavailable:  return "SERVICE_UNAVAILABLE"
        case .serverError:         return "SERVER_ERROR"
        case .networkError:        return "NETWORK_ERROR"
        case .timeout:             return "TIMEOUT"
        case .buildFailed:         return "BUILD_FAILED"
        case .buildCancelled:      return "BUILD_CANCELLED"
        case .insufficientCredits: return "INSUFFICIENT_CREDITS"
        case .paymentFailed:       return "PAYMENT_FAILED"
        case .unknown:             return "UNKNOWN"
        case .other(let s):        return s
        }
    }

    static func from(wire: String) -> FloopErrorCode {
        switch wire {
        case "UNAUTHORIZED":        return .unauthorized
        case "FORBIDDEN":           return .forbidden
        case "VALIDATION_ERROR":    return .validationError
        case "RATE_LIMITED":        return .rateLimited
        case "NOT_FOUND":           return .notFound
        case "CONFLICT":            return .conflict
        case "SERVICE_UNAVAILABLE": return .serviceUnavailable
        case "SERVER_ERROR":        return .serverError
        case "NETWORK_ERROR":       return .networkError
        case "TIMEOUT":             return .timeout
        case "BUILD_FAILED":        return .buildFailed
        case "BUILD_CANCELLED":     return .buildCancelled
        case "INSUFFICIENT_CREDITS": return .insufficientCredits
        case "PAYMENT_FAILED":      return .paymentFailed
        case "UNKNOWN":             return .unknown
        default:                    return .other(wire)
        }
    }
}

/// Internal helper. Parses a `Retry-After` header value per RFC 7231 —
/// accepts either delta-seconds or an HTTP-date. Returns `nil` on
/// empty/unparseable.
func parseRetryAfter(_ header: String?) -> TimeInterval? {
    guard let header, !header.isEmpty else { return nil }
    if let secs = Double(header) {
        return secs >= 0 ? secs : nil
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    // RFC 7231 IMF-fixdate: "Sun, 06 Nov 1994 08:49:37 GMT"
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    if let date = formatter.date(from: header) {
        let delta = date.timeIntervalSinceNow
        return delta > 0 ? delta : 0
    }
    return nil
}
