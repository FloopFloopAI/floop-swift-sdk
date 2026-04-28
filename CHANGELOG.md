# Changelog

All notable changes to `FloopFloop` (Swift SDK) are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this package adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0-alpha.2] — 2026-04-28

### Added
- **`client.subscriptions.current()`** — new resource accessor that wraps
  `GET /api/v1/subscriptions/current` and returns the authenticated user's
  plan + credit-balance snapshot. Distinct from `usage.summary()` —
  `usage.summary()` covers current-period consumption (credits remaining,
  builds used, storage), while `subscriptions.current()` returns the plan
  tier itself (price, billing period, cancel state). They overlap on
  `monthlyCredits` and `maxProjects` but serve different audiences ("am I
  about to hit my limits?" vs "what plan am I on, and when does it
  renew?").
- New types `CurrentSubscription`, `SubscriptionPlan`, `SubscriptionCredits`,
  plus `AnyCodableValue` (used for the free-form `features` map). Both
  `subscription` and `credits` on `CurrentSubscription` are `Optional`
  and can be `nil` independently — a user may exist without a
  subscription (mid-signup, cancelled with no grace credits).

### Changed
- `FloopFloopSDK.version` bumped to `0.1.0-alpha.2`.

### Tests
- New `SubscriptionsTests.swift` with two cases (populated, both-null).

### Notes
- Mirrors [`@floopfloop/sdk` PR #6](https://github.com/FloopFloopAI/floop-node-sdk/pull/6)
  (Node `0.1.0-alpha.3`) — cross-SDK parity drop.

## [0.1.0-alpha.1] — 2026-04-25

First public release. Full parity with the Node, Python, Go, Rust, Ruby, and PHP SDKs.

### Added

- `FloopFloop` client — the main entry point. Construct with `apiKey` plus optional `baseURL`, `timeout`, `userAgentSuffix`, `session`.
- Resource accessors: `projects`, `subdomains`, `secrets`, `library`, `usage`, `apiKeys`, `uploads`, `user`.
- `projects` — `create`, `list`, `get`, `status`, `cancel`, `reactivate`, `refine`, `conversations`, `stream` (`AsyncThrowingStream` over `StatusEvent`), `waitForLive`.
- `uploads.create` — two-step flow: presign against `/api/v1/uploads`, then direct `PUT` to the returned S3 URL. 5 MB cap, allowlisted MIME types, validated client-side.
- `FloopError` — single error type. Exposes `code: FloopErrorCode`, `status: Int`, `message: String`, `requestId: String?`, `retryAfter: TimeInterval?`. `FloopErrorCode` is an enum with 13 named cases plus `.other(String)` for unknown server codes.
- `Retry-After` parsing handles both delta-seconds and HTTP-date (past dates → `0`).
- Concurrency: every public type conforms to `Sendable`; methods are `async throws`.
- Test scaffolding: `URLProtocol`-based stub harness in `Tests/FloopFloopTests/TestHelpers.swift` for offline integration tests.

[0.1.0-alpha.1]: https://github.com/FloopFloopAI/floop-swift-sdk/releases/tag/v0.1.0-alpha.1
