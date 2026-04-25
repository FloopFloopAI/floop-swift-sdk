import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Maximum upload size (5 MB), validated client-side before hitting the
/// network. Mirrors the backend's `MAX_BYTES`.
public let MAX_UPLOAD_BYTES: Int = 5 * 1024 * 1024

private let extToMime: [String: String] = [
    ".png":  "image/png",
    ".jpg":  "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif":  "image/gif",
    ".svg":  "image/svg+xml",
    ".webp": "image/webp",
    ".ico":  "image/x-icon",
    ".pdf":  "application/pdf",
    ".txt":  "text/plain",
    ".csv":  "text/csv",
    ".doc":  "application/msword",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
]

public func guessMimeType(fileName: String) -> String? {
    let lower = fileName.lowercased()
    guard let dot = lower.lastIndex(of: ".") else { return nil }
    let ext = String(lower[dot...])
    return extToMime[ext]
}

public struct UploadedAttachment: Sendable, Codable {
    public let key: String
    public let fileName: String
    public let fileType: String
    public let fileSize: Int64

    /// Drop straight into ``RefineInput.attachments`` — the wire field
    /// shape matches.
    public func asRefineAttachment() -> RefineAttachment {
        RefineAttachment(key: key, fileName: fileName, fileType: fileType, fileSize: fileSize)
    }
}

public struct CreateUploadInput: Sendable {
    public var fileName: String
    public var data: Data
    public var fileType: String?

    public init(fileName: String, data: Data, fileType: String? = nil) {
        self.fileName = fileName
        self.data = data
        self.fileType = fileType
    }
}

public struct Uploads: Sendable {
    let client: FloopFloop

    public func create(_ input: CreateUploadInput) async throws -> UploadedAttachment {
        let resolvedType = input.fileType ?? guessMimeType(fileName: input.fileName)
        guard let mime = resolvedType, extToMime.values.contains(mime) else {
            throw FloopError(
                code: .validationError,
                message: "Unsupported file type for \(input.fileName). Allowed: png, jpg, gif, svg, webp, ico, pdf, txt, csv, doc, docx."
            )
        }
        guard input.data.count <= MAX_UPLOAD_BYTES else {
            let mb = Int(input.data.count / 1024 / 1024)
            throw FloopError(
                code: .validationError,
                message: "\(input.fileName) is \(mb) MB — the upload limit is 5 MB."
            )
        }

        struct PresignBody: Encodable {
            let fileName: String
            let fileType: String
            let fileSize: Int64
        }
        struct PresignResponse: Decodable {
            let uploadUrl: String
            let key: String
            let fileId: String
        }

        let presign: PresignResponse = try await client.request(
            method: "POST",
            path: "/api/v1/uploads",
            body: PresignBody(
                fileName: input.fileName,
                fileType: mime,
                fileSize: Int64(input.data.count)
            )
        )

        guard let uploadUrl = URL(string: presign.uploadUrl) else {
            throw FloopError(code: .serverError, message: "presign returned bad URL")
        }
        try await client.rawPut(url: uploadUrl, body: input.data, contentType: mime)

        return UploadedAttachment(
            key: presign.key,
            fileName: input.fileName,
            fileType: mime,
            fileSize: Int64(input.data.count)
        )
    }
}
