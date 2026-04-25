# Cookbook

Concrete `floop-swift-sdk` patterns you can copy-paste. Every snippet uses only the SDK's public surface — no undocumented endpoints, no private helpers.

For the basics (install, client setup, resource tour) see the [README](../README.md). This file is the **"I know the basics, now how do I actually build X"** layer.

These recipes mirror the [Node](https://github.com/FloopFloopAI/floop-node-sdk/blob/main/docs/recipes.md), [Python](https://github.com/FloopFloopAI/floop-python-sdk/blob/main/docs/recipes.md), [Go](https://github.com/FloopFloopAI/floop-go-sdk/blob/main/docs/recipes.md), [Rust](https://github.com/FloopFloopAI/floop-rust-sdk/blob/main/docs/recipes.md), [Ruby](https://github.com/FloopFloopAI/floop-ruby-sdk/blob/main/docs/recipes.md), [PHP](https://github.com/FloopFloopAI/floop-php-sdk/blob/main/docs/recipes.md), and [Kotlin](https://github.com/FloopFloopAI/floop-kotlin-sdk/blob/main/docs/recipes.md) cookbooks, translated to Swift idioms (`async`/`await`, `AsyncThrowingStream`, `Task` cancellation, `Sendable` everywhere).

All snippets assume:

```swift
import FloopFloop
```

and that you're running them inside an `async` context (e.g. `@main struct App` with `static func main() async throws`, or a `Task { ... }` block).

---

## 1. Ship a project from prompt to live URL

The canonical one-call flow: create, wait, done. `waitForLive` throws `FloopError` with `code == .buildFailed` / `.buildCancelled` / `.timeout` on non-success terminals, so a plain `try/catch` is enough.

```swift
import FloopFloop

func ship(client: FloopFloop, prompt: String, subdomain: String) async throws -> String {
    let created = try await client.projects.create(.init(
        prompt: prompt,
        subdomain: subdomain,
        botType: "site"
    ))

    do {
        // Polls status every 2s; bounds the total wait to 10 minutes.
        let live = try await client.projects.waitForLive(created.project.id)
        guard let url = live.url else {
            throw FloopError(
                code: .unknown,
                message: "project is live but has no URL yet"
            )
        }
        return url
    } catch let err as FloopError where err.code == .buildFailed {
        print("build failed: \(err.message)")
        throw err
    }
}

@main
struct Demo {
    static func main() async throws {
        let client = FloopFloop(apiKey: ProcessInfo.processInfo.environment["FLOOP_API_KEY"]!)
        let url = try await ship(
            client: client,
            prompt: "A single-page portfolio for a landscape photographer",
            subdomain: "landscape-portfolio"
        )
        print("Live at \(url)")
    }
}
```

**Wall-clock timeout via Task cancellation.** Wrap the call in a `Task` and call `cancel()` from a sibling timer:

```swift
let task = Task<Project, Error> {
    try await client.projects.waitForLive(created.project.id)
}
Task {
    try await Task.sleep(nanoseconds: 10 * 60 * 1_000_000_000) // 10 min
    task.cancel()
}
let live = try await task.value
```

The polling loop inside `stream` checks `Task.isCancelled` between polls AND `Task.sleep` is cancellation-aware, so the abort propagates promptly. `StreamOptions.maxWait` is the polling-side cap (default 600 s); the parent-task cancellation is the caller-side cap. Both honoured, whichever fires first.

**When to prefer `stream` over `waitForLive`:** when you want to show progress to a user (CLI spinner, SwiftUI status line). `waitForLive` only returns at the end — no visibility into what the build is doing.

---

## 2. Watch a build progress in real time

`projects.stream(ref)` returns `AsyncThrowingStream<StatusEvent, Error>`. Iterate it with `for try await` — each yielded event is a de-duplicated status snapshot. The stream terminates on `live` / `failed` / `cancelled` / `archived` (or on `maxWait` exhaustion); non-success terminals throw `FloopError`.

```swift
import FloopFloop

func watchBuild(client: FloopFloop) async throws {
    let created = try await client.projects.create(.init(
        prompt: "A recipe blog with a dark theme",
        subdomain: "recipe-blog",
        botType: "site"
    ))

    do {
        for try await event in client.projects.stream(created.project.id) {
            let progress = event.progress.map { " \(Int($0))%" } ?? ""
            let detail   = event.message.isEmpty ? "" : " — \(event.message)"
            print("[\(event.status)]\(progress) step \(event.step)/\(event.totalSteps)\(detail)")
        }
    } catch let err as FloopError {
        switch err.code {
        case .buildFailed:    fatalError("build failed: \(err.message)")
        case .buildCancelled: fatalError("user cancelled build")
        case .timeout:        fatalError("build stalled past maxWait")
        default:              throw err
        }
    }

    // Reached "live" cleanly — fetch the hydrated project.
    let done = try await client.projects.get(created.project.id)
    if let url = done.url { print("Live at \(url)") }
}
```

**Early abort.** Throw your own sentinel error from inside the loop body, or call `task.cancel()` from outside. The first pattern survives refactors better:

```swift
struct EnoughProgress: Error {}

do {
    for try await event in client.projects.stream("recipe-blog") {
        if let p = event.progress, p >= 50 {
            throw EnoughProgress()
        }
        print("[\(event.status)] \(event.progress ?? 0)%")
    }
} catch is EnoughProgress {
    print("saw enough progress, moving on")
}
```

The `AsyncThrowingStream` finishes the underlying poll task automatically when the iterator is dropped, so there's no leak.

---

## 3. Refine a project, even when it's mid-build

`projects.refine` returns a `RefineResult` with three mutually-exclusive optional fields:

- `queued: Queued?` — project is currently deploying; your message is queued.
- `processing: Processing?` — your message triggered a new build immediately.
- `savedOnly: SavedOnly?` — saved as a conversation entry without triggering a build.

Exactly one is non-nil on success.

```swift
import FloopFloop

func refineAndWait(client: FloopFloop, ref: String, message: String) async throws {
    let res = try await client.projects.refine(ref, .init(message: message))

    if let p = res.processing {
        print("Build started (deployment \(p.deploymentId))")
        _ = try await client.projects.waitForLive(ref)
    } else if let q = res.queued {
        print("Queued behind current build (message \(q.messageId))")
        // Poll once — when "live", your queued message has been processed.
        _ = try await client.projects.waitForLive(ref)
    } else if res.savedOnly != nil {
        print("Saved as a chat message, no build triggered")
    }
}
```

**Why three optional fields instead of an enum?** Swift's `enum` with associated values is the natural fit, but `Codable` deserialisation against the JSON shape is cleaner with three `Optional` fields — they exactly mirror what's on the wire (`{"queued": true, "messageId": "..."}` vs `{"processing": true, "deploymentId": "..."}`). The SDK guarantees exactly one is non-nil on success.

A future major version may swap to a Codable enum with a tagged-union representation once we have a representative sample of caller code to validate the migration cost.

---

## 4. Upload an image and refine with it as context

Uploads are two-step: `uploads.create` presigns an S3 URL and does the direct PUT, returning an `UploadedAttachment`. **Use `asRefineAttachment()`** to drop straight into `refine`'s `attachments` array — the SDK does the conversion for you (matches Kotlin and Ruby; unlike Go/Rust where the conversion is explicit because the underlying `fileSize` types differ).

```swift
import FloopFloop
import Foundation

func refineWithMockup(client: FloopFloop, projectRef: String, imagePath: String) async throws {
    let url = URL(fileURLWithPath: imagePath)
    let bytes = try Data(contentsOf: url)
    let attachment = try await client.uploads.create(.init(
        fileName: url.lastPathComponent,
        data: bytes
        // fileType: "image/png"  // optional — guessed from the extension
    ))

    _ = try await client.projects.refine(
        projectRef,
        .init(
            message: "Make the homepage look like this mockup.",
            attachments: [attachment.asRefineAttachment()]
        )
    )
}
```

**Supported types:** `png`, `jpg/jpeg`, `gif`, `svg`, `webp`, `ico`, `pdf`, `txt`, `csv`, `doc`, `docx`. Max 5 MB per upload (`MAX_UPLOAD_BYTES` constant). The SDK validates client-side before hitting the network, so bad inputs throw `FloopError(code: .validationError, ...)` with no round-trip.

Attachments only flow through `refine` today — `create` doesn't accept them via the SDK. If you need to anchor a brand-new project against images, create with a prompt first, then refine with the attachments as a follow-up.

---

## 5. Rotate an API key from a CI job

Three-step rotation: create the new key, write it to your secret store, then revoke the old one. The order matters — you must revoke with a **different** key than the one making the call (the backend returns `400 VALIDATION_ERROR` if you try to revoke the key you're authenticated with).

```swift
import FloopFloop
import Foundation

func rotate(victimName: String) async throws {
    // Use a long-lived bootstrap key (stored as a CI secret) to do the
    // rotation. Don't use the key we're about to revoke — that hits
    // the self-revoke guard.
    guard let bootstrapKey = ProcessInfo.processInfo.environment["FLOOP_BOOTSTRAP_KEY"] else {
        throw FloopError(code: .validationError, message: "FLOOP_BOOTSTRAP_KEY is required")
    }
    let bootstrap = FloopFloop(apiKey: bootstrapKey)

    // 1. Find the key we want to rotate by its name. (Each name is
    //    unique per account because the dashboard enforces it; matching
    //    by name is more reliable than matching the prefix substring.)
    let keys = try await bootstrap.apiKeys.list()
    guard let victim = keys.first(where: { $0.name == victimName }) else {
        throw FloopError(code: .notFound, status: 404, message: "key not found: \(victimName)")
    }

    // 2. Mint the replacement.
    let fresh = try await bootstrap.apiKeys.create(name: "\(victimName)-new")
    try await writeSecret(name: "FLOOP_API_KEY", value: fresh.rawKey)

    // 3. Revoke the old one. apiKeys.remove() accepts an id OR a name.
    try await bootstrap.apiKeys.remove(victim.id)
}

// writeSecret wires into your CI platform's secret store —
// AWS Secrets Manager, Vault, GitHub Actions `gh secret set`, etc.
func writeSecret(name: String, value: String) async throws { /* ... */ }
```

**Can't I just reuse the bootstrap key forever?** Technically yes — if it's tightly scoped and audited. In practice, a single long-lived "rotator key" is a common compromise: it only has permission to mint/list/revoke keys, never appears in application traffic, and itself gets rotated manually on a rare cadence (annually, or on compromise).

The 5-keys-per-account cap applies to active keys, so make sure to revoke old rotations rather than accumulating them.

---

## 6. Retry with backoff on `.rateLimited` and `.networkError`

`FloopError` carries everything you need to implement backoff correctly:

- `retryAfter: TimeInterval?` — populated from the `Retry-After` response header on 429s (parsed from delta-seconds OR HTTP-date), in **seconds**. `nil` when not set.
- `code: FloopErrorCode` — distinguishes retryable (`.rateLimited`, `.networkError`, `.timeout`, `.serviceUnavailable`, `.serverError`) from permanent (`.unauthorized`, `.forbidden`, `.validationError`, `.notFound`, `.conflict`, `.buildFailed`, `.buildCancelled`).

```swift
import FloopFloop
import Foundation

private let retryable: Set<String> = [
    FloopErrorCode.rateLimited.rawValue,
    FloopErrorCode.networkError.rawValue,
    FloopErrorCode.timeout.rawValue,
    FloopErrorCode.serviceUnavailable.rawValue,
    FloopErrorCode.serverError.rawValue,
]

func withRetry<T>(maxAttempts: Int = 5, _ fn: () async throws -> T) async throws -> T {
    var attempt = 0
    while true {
        attempt += 1
        do {
            return try await fn()
        } catch let err as FloopError {
            if !retryable.contains(err.code.rawValue) { throw err }
            if attempt >= maxAttempts { throw err }

            // Prefer the server's hint; fall back to exponential backoff
            // with jitter capped at 30 s.
            let serverHint: TimeInterval? = err.retryAfter
            let expo = min(30.0, 0.25 * Double(1 << min(attempt, 7)))
            let jitter = Double.random(in: 0..<0.25)
            let wait = (serverHint ?? expo) + jitter

            let reqTag = err.requestId.map { " (request \($0))" } ?? ""
            print("floop: \(err.code.rawValue) (attempt \(attempt)/\(maxAttempts)), retrying in \(Int(wait * 1000))ms\(reqTag)")
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }
}

// Wrap any SDK call:
func example(client: FloopFloop) async throws {
    let projects = try await withRetry { try await client.projects.list() }
    _ = projects
}
```

**Don't retry everything.** `.validationError`, `.unauthorized`, and `.forbidden` are not going to fix themselves between attempts — retrying them just burns rate-limit budget and delays the real error reaching your logs.

**Cancellation.** `Task.sleep(nanoseconds:)` is cancellation-aware. If the surrounding task is cancelled mid-sleep, it throws `CancellationException` and unwinds cleanly — no special handling needed.

**`.unknown` vs `.other`.** The SDK's `.unknown` case maps to the wire string `"UNKNOWN"`; truly unrecognised server codes pass through as `.other("SOME_NEW_CODE")`. The retryable set above only includes the specific codes we want to retry — `.other(...)` is intentionally **not** retryable by default. If you want to retry on a specific new code, add it explicitly to the set.

---

## Got a pattern worth adding?

Open an issue at [floop-swift-sdk/issues](https://github.com/FloopFloopAI/floop-swift-sdk/issues) describing the use case. Recipes live in this file, not in `Sources/`, so they're easy to update without a release.
