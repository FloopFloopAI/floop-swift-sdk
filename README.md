# FloopFloop Swift SDK

[![CI](https://img.shields.io/github/actions/workflow/status/FloopFloopAI/floop-swift-sdk/ci.yml?branch=main&logo=github&label=ci)](https://github.com/FloopFloopAI/floop-swift-sdk/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/swift-5.9%2B-orange?logo=swift&logoColor=white)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2017%20%7C%20macOS%2014%20%7C%20tvOS%2017%20%7C%20watchOS%2010%20%7C%20visionOS%201-blue)](Package.swift)
[![License: MIT](https://img.shields.io/github/license/FloopFloopAI/floop-swift-sdk)](LICENSE)

Official Swift SDK for the [FloopFloop](https://www.floopfloop.com) API. Build, refine, and manage FloopFloop projects from any Swift codebase — server-side or client-side.

Same surface as the [Node](https://github.com/FloopFloopAI/floop-node-sdk), [Python](https://github.com/FloopFloopAI/floop-python-sdk), [Go](https://github.com/FloopFloopAI/floop-go-sdk), [Rust](https://github.com/FloopFloopAI/floop-rust-sdk), [Ruby](https://github.com/FloopFloopAI/floop-ruby-sdk), and [PHP](https://github.com/FloopFloopAI/floop-php-sdk) SDKs.

## Install

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/FloopFloopAI/floop-swift-sdk.git", from: "0.1.0-alpha.1"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "FloopFloop", package: "floop-swift-sdk"),
    ]),
],
```

Or via **Xcode**: File → Add Package Dependencies → paste `https://github.com/FloopFloopAI/floop-swift-sdk.git`.

Requires Swift 5.9+ and one of: iOS 17+ / macOS 14+ / tvOS 17+ / watchOS 10+ / visionOS 1+. Zero runtime dependencies — uses `URLSession` and `Foundation` only.

## Quickstart

```swift
import FloopFloop

let client = FloopFloop(apiKey: ProcessInfo.processInfo.environment["FLOOP_API_KEY"]!)

let created = try await client.projects.create(.init(
    prompt: "A landing page for a cat cafe",
    subdomain: "cat-cafe",
    botType: "site"
))

let live = try await client.projects.waitForLive(created.project.id)
print("Live at: \(live.url ?? "—")")
```

Grab an API key at [www.floopfloop.com/account/api-keys](https://www.floopfloop.com/account/api-keys). Note: this SDK is for **server-side / desktop / development** use today. Mobile-app distribution requires a different auth flow — see [Mobile note](#mobile-note) below.

## Resources

| Resource | Methods |
|---|---|
| `client.projects` | `create`, `list`, `get`, `status`, `cancel`, `reactivate`, `refine`, `conversations`, `stream`, `waitForLive` |
| `client.subdomains` | `check`, `suggest` |
| `client.secrets` | `list`, `set`, `remove` |
| `client.library` | `list`, `clone` |
| `client.usage` | `summary` |
| `client.apiKeys` | `list`, `create`, `remove` (accepts id or name) |
| `client.uploads` | `create` (presign + direct S3 PUT) |
| `client.user` | `me` |

Every method is `async throws`. Non-2xx responses throw `FloopError`.

## Streaming a build

```swift
for try await event in client.projects.stream("my-subdomain") {
    print("[\(event.status)] step \(event.step)/\(event.totalSteps) — \(event.message)")
}
```

The stream de-duplicates identical consecutive snapshots (same `status` / `step` / `progress` / `queuePosition`) and terminates on `live`, `failed`, `cancelled`, or `archived`. Throws `FloopError` with `code: .buildFailed` / `.buildCancelled` / `.timeout` on non-success terminals.

`waitForLive` is a convenience wrapper that returns the hydrated `Project` once the build reaches `live`.

## Error handling

```swift
import FloopFloop

do {
    _ = try await client.projects.status("p_nonexistent")
} catch let err as FloopError {
    if err.code == .rateLimited, let after = err.retryAfter {
        try await Task.sleep(nanoseconds: UInt64(after * 1_000_000_000))
        // retry…
    }
    throw err
}
```

`FloopError` exposes:

- `code: FloopErrorCode` — `.unauthorized`, `.forbidden`, `.validationError`, `.rateLimited`, `.notFound`, `.conflict`, `.serviceUnavailable`, `.serverError`, `.networkError`, `.timeout`, `.buildFailed`, `.buildCancelled`, `.unknown`. Unknown server codes pass through as `.other(String)`.
- `status: Int` — HTTP status. `0` for transport-level failures.
- `requestId: String?` — `x-request-id` from the response. Quote it in bug reports.
- `retryAfter: TimeInterval?` — seconds parsed from the `Retry-After` response header (delta-seconds OR HTTP-date).

## Configuration

```swift
let client = FloopFloop(
    apiKey: "flp_…",
    baseURL: "https://staging.floopfloop.com",   // default: https://www.floopfloop.com
    timeout: 60,                                  // default: 30s
    userAgentSuffix: "myapp/1.2.3",               // appended to floopfloop-swift-sdk/<version>
    session: URLSession(configuration: .default)  // bring-your-own session for proxies / ATS
)
```

## Mobile note

Don't embed an API key in an iOS or Android app — anyone with the IPA / APK can extract it. For shipped mobile apps, the right pattern is:

1. **Your mobile app** talks to **your backend** (signed in via Sign in with Apple / Google / etc.).
2. **Your backend** holds the `flp_*` API key and talks to FloopFloop on the user's behalf.

A first-party mobile auth flow (so users can log into FloopFloop from a FloopFloop-built mobile app directly) is a separate piece of work tracked on the platform roadmap.

## Development

```bash
swift build
swift test
```

Tests stub `URLSession` via a `URLProtocol` subclass — no network, no API key needed.

## License

MIT — see [LICENSE](LICENSE).
