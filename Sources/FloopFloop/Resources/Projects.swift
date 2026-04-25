import Foundation

// MARK: - Models

public struct Project: Sendable, Codable, Equatable {
    public let id: String
    public let name: String
    public let subdomain: String?
    public let status: String
    public let botType: String?
    public let url: String?
    public let amplifyAppUrl: String?
    public let isPublic: Bool
    public let isAuthProtected: Bool
    public let teamId: String?
    public let createdAt: String
    public let updatedAt: String
    public let thumbnailUrl: String?
}

public struct CreateProjectInput: Sendable, Codable {
    public var prompt: String
    public var name: String?
    public var subdomain: String?
    public var botType: String?
    public var isAuthProtected: Bool?
    public var teamId: String?

    public init(
        prompt: String,
        name: String? = nil,
        subdomain: String? = nil,
        botType: String? = nil,
        isAuthProtected: Bool? = nil,
        teamId: String? = nil
    ) {
        self.prompt = prompt
        self.name = name
        self.subdomain = subdomain
        self.botType = botType
        self.isAuthProtected = isAuthProtected
        self.teamId = teamId
    }
}

public struct CreatedProject: Sendable, Codable {
    public struct Deployment: Sendable, Codable {
        public let id: String
        public let status: String
        public let version: Int
    }
    public let project: Project
    public let deployment: Deployment
}

public struct StatusEvent: Sendable, Codable, Equatable {
    public let step: Int
    public let totalSteps: Int
    public let status: String
    public let message: String
    public let progress: Double?
    public let queuePosition: Int?
}

public struct RefineAttachment: Sendable, Codable, Equatable {
    public let key: String
    public let fileName: String
    public let fileType: String
    public let fileSize: Int64

    public init(key: String, fileName: String, fileType: String, fileSize: Int64) {
        self.key = key
        self.fileName = fileName
        self.fileType = fileType
        self.fileSize = fileSize
    }
}

public struct RefineInput: Sendable, Codable {
    public var message: String
    public var attachments: [RefineAttachment]?
    public var codeEditOnly: Bool?

    public init(
        message: String,
        attachments: [RefineAttachment]? = nil,
        codeEditOnly: Bool? = nil
    ) {
        self.message = message
        self.attachments = attachments
        self.codeEditOnly = codeEditOnly
    }
}

/// Three-shape response from `POST /projects/:id/refine`. Exactly one
/// field is non-nil on success.
public struct RefineResult: Sendable, Codable {
    public struct Queued: Sendable, Codable, Equatable {
        public let messageId: String
    }
    public struct Processing: Sendable, Codable, Equatable {
        public let deploymentId: String
        public let queuePriority: Int
    }
    public struct SavedOnly: Sendable, Codable, Equatable {}

    public var queued: Queued?
    public var processing: Processing?
    public var savedOnly: SavedOnly?

    private enum CodingKeys: String, CodingKey {
        case queued, messageId, processing, deploymentId, queuePriority
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let isProcessing = try? c.decode(Bool.self, forKey: .processing), isProcessing {
            let depId = try c.decode(String.self, forKey: .deploymentId)
            let prio = (try? c.decode(Int.self, forKey: .queuePriority)) ?? 0
            self.processing = .init(deploymentId: depId, queuePriority: prio)
            return
        }
        if let q = try? c.decode(Bool.self, forKey: .queued) {
            if q {
                let msgId = try c.decode(String.self, forKey: .messageId)
                self.queued = .init(messageId: msgId)
            } else {
                self.savedOnly = .init()
            }
            return
        }
        throw FloopError(code: .unknown, message: "refine: unrecognised response shape")
    }

    public func encode(to encoder: Encoder) throws {
        // Only used by tests that round-trip; not part of the wire input.
    }
}

public struct ConversationMessage: Sendable, Codable {
    public let id: String
    public let projectId: String
    public let role: String
    public let content: String
    public let status: String
    public let position: Int?
    public let createdAt: String
}

public struct ConversationsResult: Sendable, Codable {
    public let messages: [ConversationMessage]
    public let queued: [ConversationMessage]
    public let latestVersion: Int
}

public struct ListProjectsOptions: Sendable {
    public var teamId: String?
    public init(teamId: String? = nil) { self.teamId = teamId }
}

public struct StreamOptions: Sendable {
    public var interval: TimeInterval
    public var maxWait: TimeInterval

    public init(interval: TimeInterval = 2, maxWait: TimeInterval = 600) {
        self.interval = interval
        self.maxWait = maxWait
    }
}

// MARK: - Resource

public struct Projects: Sendable {
    let client: FloopFloop

    public func create(_ input: CreateProjectInput) async throws -> CreatedProject {
        try await client.request(method: "POST", path: "/api/v1/projects", body: input)
    }

    public func list(_ opts: ListProjectsOptions = .init()) async throws -> [Project] {
        var path = "/api/v1/projects"
        if let teamId = opts.teamId, !teamId.isEmpty {
            path += "?teamId=\(percentEncode(teamId))"
        }
        return try await client.request(method: "GET", path: path)
    }

    /// Fetch a single project by id or subdomain. There is no dedicated
    /// `GET /api/v1/projects/:id` endpoint — we filter the list. For
    /// accounts with many projects this is a real cost; cache the
    /// project handle and reuse it instead of re-resolving.
    public func get(_ ref: String, opts: ListProjectsOptions = .init()) async throws -> Project {
        let all = try await list(opts)
        guard let match = all.first(where: { $0.id == ref || $0.subdomain == ref }) else {
            throw FloopError(code: .notFound, status: 404, message: "project not found: \(ref)")
        }
        return match
    }

    public func status(_ ref: String) async throws -> StatusEvent {
        try await client.request(method: "GET", path: "/api/v1/projects/\(percentEncode(ref))/status")
    }

    public func cancel(_ ref: String) async throws {
        try await client.requestEmpty(method: "POST", path: "/api/v1/projects/\(percentEncode(ref))/cancel")
    }

    public func reactivate(_ ref: String) async throws {
        try await client.requestEmpty(method: "POST", path: "/api/v1/projects/\(percentEncode(ref))/reactivate")
    }

    public func refine(_ ref: String, _ input: RefineInput) async throws -> RefineResult {
        try await client.request(method: "POST", path: "/api/v1/projects/\(percentEncode(ref))/refine", body: input)
    }

    public func conversations(_ ref: String, limit: Int? = nil) async throws -> ConversationsResult {
        var path = "/api/v1/projects/\(percentEncode(ref))/conversations"
        if let limit, limit > 0 { path += "?limit=\(limit)" }
        return try await client.request(method: "GET", path: path)
    }

    /// Async-stream the project's status events as it builds. Yields each
    /// de-duplicated snapshot (same status / step / progress / queuePosition)
    /// until a terminal state (live / failed / cancelled / archived) or
    /// `opts.maxWait` elapses.
    ///
    /// On non-success terminals throws `FloopError` with code
    /// `.buildFailed` / `.buildCancelled` / `.timeout`.
    public func stream(_ ref: String, opts: StreamOptions = .init()) -> AsyncThrowingStream<StatusEvent, Error> {
        // Use the unambiguous factory rather than the closure-init form —
        // Swift's type inference deadlocks on
        // `AsyncThrowingStream { continuation in ... }` when the body
        // contains `try await` calls and a Task wrapper. `makeStream()`
        // hands back the typed continuation directly.
        let (stream, continuation) = AsyncThrowingStream<StatusEvent, Error>.makeStream()

        let task = Task<Void, Never> {
            do {
                try await self.runStream(ref: ref, opts: opts) { event in
                    continuation.yield(event)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// Polling loop body for `stream`. Factored out so the type-inference
    /// surface inside `stream` stays trivial.
    private func runStream(
        ref: String,
        opts: StreamOptions,
        yield: (StatusEvent) -> Void
    ) async throws {
        let deadline = Date().addingTimeInterval(opts.maxWait)
        var lastKey: String? = nil

        while !Task.isCancelled {
            if Date() >= deadline {
                throw FloopError(
                    code: .timeout,
                    message: "stream: project \(ref) did not reach a terminal state within \(opts.maxWait)s"
                )
            }
            let event = try await self.status(ref)
            let progressStr = event.progress.map { String($0) } ?? ""
            let queuePosStr = event.queuePosition.map { String($0) } ?? ""
            let key = "\(event.status)|\(event.step)|\(progressStr)|\(queuePosStr)"
            if key != lastKey {
                lastKey = key
                yield(event)
            }
            switch event.status {
            case "live", "archived":
                return
            case "failed":
                throw FloopError(
                    code: .buildFailed,
                    message: event.message.isEmpty ? "build failed" : event.message
                )
            case "cancelled":
                throw FloopError(
                    code: .buildCancelled,
                    message: event.message.isEmpty ? "build cancelled" : event.message
                )
            default:
                try await Task.sleep(nanoseconds: UInt64(opts.interval * 1_000_000_000))
            }
        }
    }

    /// Block until the project reaches `live`. Throws `FloopError` on the
    /// non-success terminals. Returns the hydrated `Project`.
    public func waitForLive(_ ref: String, opts: StreamOptions = .init()) async throws -> Project {
        for try await _ in stream(ref, opts: opts) {
            // discard intermediate events
        }
        return try await get(ref)
    }
}

// MARK: - Internal helpers

func percentEncode(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
}
