import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Main entry point for the FloopFloop SDK.
///
/// Construct once and reuse — `URLSession` keeps connections alive per
/// instance, so a fresh client per request loses connection-reuse and adds
/// a TLS handshake every call.
///
/// ```swift
/// import FloopFloop
///
/// let client = FloopFloop(apiKey: ProcessInfo.processInfo.environment["FLOOP_API_KEY"]!)
///
/// let created = try await client.projects.create(.init(
///     prompt: "A landing page for a cat cafe",
///     subdomain: "cat-cafe",
///     botType: "site"
/// ))
/// let live = try await client.projects.waitForLive(created.project.id)
/// print("Live at: \(live.url ?? "")")
/// ```
public final class FloopFloop: Sendable {
    public static let defaultBaseURL = "https://www.floopfloop.com"
    public static let defaultTimeout: TimeInterval = 30

    let apiKey: String
    let baseURL: URL
    let session: URLSession
    let userAgent: String

    /// Create a client with the given bearer token.
    ///
    /// - Parameters:
    ///   - apiKey: Your `flp_…` API key. Required.
    ///   - baseURL: Override for staging or local dev. Defaults to
    ///     `https://www.floopfloop.com`. Trailing slashes stripped.
    ///   - timeout: Per-request timeout. Defaults to 30s.
    ///   - userAgentSuffix: Appended to the SDK's User-Agent. Useful for
    ///     identifying your application in our logs.
    ///   - session: Bring-your-own `URLSession`. Lets you wire in a custom
    ///     proxy, ATS exception, or test-double. The SDK does not mutate
    ///     the session you pass in.
    public init(
        apiKey: String,
        baseURL: String = defaultBaseURL,
        timeout: TimeInterval = defaultTimeout,
        userAgentSuffix: String? = nil,
        session: URLSession? = nil
    ) {
        precondition(!apiKey.isEmpty, "FloopFloop: apiKey must not be empty")

        self.apiKey = apiKey

        var trimmed = baseURL
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        self.baseURL = URL(string: trimmed) ?? URL(string: FloopFloop.defaultBaseURL)!

        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = timeout
            self.session = URLSession(configuration: cfg)
        }

        let suffix = userAgentSuffix.map { " \($0)" } ?? ""
        self.userAgent = "floopfloop-swift-sdk/\(FloopFloopSDK.version)\(suffix)"
    }

    // MARK: - Resource accessors

    public var projects:   Projects   { Projects(client: self) }
    public var subdomains: Subdomains { Subdomains(client: self) }
    public var secrets:    Secrets    { Secrets(client: self) }
    public var library:    Library    { Library(client: self) }
    public var usage:      Usage      { Usage(client: self) }
    public var apiKeys:    ApiKeys    { ApiKeys(client: self) }
    public var uploads:    Uploads    { Uploads(client: self) }
    public var user:       UserAPI    { UserAPI(client: self) }
}
