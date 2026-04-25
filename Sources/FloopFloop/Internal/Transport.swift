import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Internal envelope shapes. The backend wraps successful responses in
/// `{"data": ...}` and errors in `{"error": {"code": ..., "message": ...}}`.
struct DataEnvelope<T: Decodable>: Decodable {
    let data: T
}

struct ErrorEnvelope: Decodable {
    struct Inner: Decodable {
        let code: String
        let message: String
    }
    let error: Inner
}

/// JSON encoder/decoder matching the wire format. Backend uses camelCase
/// throughout. Dates are ISO8601 strings — we keep them as `String` in the
/// model types for byte-for-byte parity with the other SDKs.
enum JSON {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = []
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()
}

extension FloopFloop {
    /// Build, send, and decode an SDK request. The decoded body is the
    /// inner shape — the `{data: ...}` wrapper is unwrapped here.
    func request<Out: Decodable>(
        method: String,
        path: String,
        body: Encodable? = nil
    ) async throws -> Out {
        let raw = try await rawRequestBody(method: method, path: path, body: body)
        do {
            let env = try JSON.decoder.decode(DataEnvelope<Out>.self, from: raw)
            return env.data
        } catch {
            // Some endpoints (top-level lists, internals) don't wrap. Fall back.
            do {
                return try JSON.decoder.decode(Out.self, from: raw)
            } catch {
                throw FloopError(
                    code: .unknown,
                    status: 0,
                    message: "failed to decode response: \(error)"
                )
            }
        }
    }

    /// Send a request that returns no body (e.g. cancel, reactivate).
    func requestEmpty(
        method: String,
        path: String,
        body: Encodable? = nil
    ) async throws {
        _ = try await rawRequestBody(method: method, path: path, body: body)
    }

    /// Raw bytes of the (already-validated) response body. Used by
    /// uploads.create for the S3 PUT step.
    func rawRequestBody(
        method: String,
        path: String,
        body: Encodable? = nil
    ) async throws -> Data {
        // String concat instead of URL.append(path:) — that API is iOS 16+
        // / macOS 13+ and we target iOS 15+ / macOS 12+. The path always
        // starts with "/" so a plain concat produces the right shape.
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw FloopError(code: .validationError, message: "bad path: \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        req.addValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSON.encoder.encode(AnyEncodable(body))
        }

        let (data, response) = try await sendNoThrow(req)

        guard let http = response as? HTTPURLResponse else {
            throw FloopError(
                code: .networkError,
                message: "unexpected non-HTTP response"
            )
        }

        let requestId = http.value(forHTTPHeaderField: "x-request-id")
        let retryAfter = parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After"))

        guard (200..<300).contains(http.statusCode) else {
            let (code, message) = parseErrorEnvelope(data: data, status: http.statusCode)
            throw FloopError(
                code: code,
                status: http.statusCode,
                message: message,
                requestId: requestId,
                retryAfter: retryAfter
            )
        }
        return data
    }

    /// Wraps `URLSession.data(for:)` to translate transport errors into
    /// `FloopError`s with the right codes.
    private func sendNoThrow(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: req)
        } catch {
            let code: FloopErrorCode
            let nsErr = error as NSError
            if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorTimedOut {
                code = .timeout
            } else {
                code = .networkError
            }
            throw FloopError(
                code: code,
                status: 0,
                message: "could not reach \(baseURL.absoluteString): \(error.localizedDescription)"
            )
        }
    }

    /// Used by uploads.create for the direct S3 PUT step. No bearer header,
    /// no envelope unwrap, just a raw body upload.
    func rawPut(
        url: URL,
        body: Data,
        contentType: String
    ) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.addValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (_, response) = try await sendNoThrow(req)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw FloopError(
                code: .serverError,
                status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: "S3 PUT failed"
            )
        }
    }
}

private func parseErrorEnvelope(data: Data, status: Int) -> (FloopErrorCode, String) {
    if let env = try? JSON.decoder.decode(ErrorEnvelope.self, from: data) {
        return (FloopErrorCode.from(wire: env.error.code), env.error.message)
    }
    let fallback = defaultCode(for: status)
    return (fallback, "request failed (\(status))")
}

private func defaultCode(for status: Int) -> FloopErrorCode {
    switch status {
    case 401: return .unauthorized
    case 403: return .forbidden
    case 404: return .notFound
    case 409: return .conflict
    case 422: return .validationError
    case 429: return .rateLimited
    case 503: return .serviceUnavailable
    case 500..<600: return .serverError
    default: return .unknown
    }
}

/// Erased `Encodable` so we can hand a heterogeneous body to the JSON
/// encoder without forcing every call site to spell out the input type.
struct AnyEncodable: Encodable {
    let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ wrapped: T) {
        self._encode = wrapped.encode
    }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
