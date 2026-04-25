import Foundation

public struct LibraryProject: Sendable, Codable {
    public let id: String
    public let name: String
    public let subdomain: String?
    public let description: String?
    public let botType: String?
    public let url: String?
    public let thumbnailUrl: String?
    public let likes: Int?
    public let createdAt: String
}

public struct LibraryListOptions: Sendable {
    public var botType: String?
    public var search: String?
    public var sort: String?
    public var page: Int?
    public var limit: Int?

    public init(
        botType: String? = nil,
        search: String? = nil,
        sort: String? = nil,
        page: Int? = nil,
        limit: Int? = nil
    ) {
        self.botType = botType
        self.search = search
        self.sort = sort
        self.page = page
        self.limit = limit
    }
}

public struct ClonedProject: Sendable, Codable {
    public let project: Project
}

public struct Library: Sendable {
    let client: FloopFloop

    public func list(_ opts: LibraryListOptions = .init()) async throws -> [LibraryProject] {
        var params: [String] = []
        if let botType = opts.botType { params.append("botType=\(percentEncode(botType))") }
        if let search  = opts.search  { params.append("search=\(percentEncode(search))") }
        if let sort    = opts.sort    { params.append("sort=\(percentEncode(sort))") }
        if let page    = opts.page    { params.append("page=\(page)") }
        if let limit   = opts.limit   { params.append("limit=\(limit)") }

        var path = "/api/v1/library"
        if !params.isEmpty { path += "?\(params.joined(separator: "&"))" }
        return try await client.request(method: "GET", path: path)
    }

    public func clone(_ projectId: String, subdomain: String) async throws -> ClonedProject {
        struct Body: Encodable { let subdomain: String }
        return try await client.request(
            method: "POST",
            path: "/api/v1/library/\(percentEncode(projectId))/clone",
            body: Body(subdomain: subdomain)
        )
    }
}
