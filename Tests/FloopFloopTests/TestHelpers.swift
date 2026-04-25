import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import FloopFloop

/// In-process URLProtocol that lets tests stub `URLSession.data(for:)`
/// without touching the network. Each test enqueues canned responses;
/// the protocol pops them off the queue and returns them.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        var status: Int
        var headers: [String: String]
        var body: Data
    }

    /// Test scaffolding: queue of canned responses to return for the next
    /// `URLSession.data(for:)` calls, in order. Captured requests are
    /// appended to ``capturedRequests``.
    nonisolated(unsafe) static var queue: [Stub] = []
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []
    nonisolated(unsafe) static let lock = NSLock()

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        queue.removeAll()
        capturedRequests.removeAll()
    }

    static func enqueue(status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
        lock.lock()
        defer { lock.unlock() }
        queue.append(Stub(status: status, headers: headers, body: body))
    }

    static func enqueueJSON(status: Int = 200, headers: [String: String] = [:], _ json: String) {
        enqueue(status: status, headers: headers, body: Data(json.utf8))
    }

    static func popStub() -> Stub? {
        lock.lock()
        defer { lock.unlock() }
        return queue.isEmpty ? nil : queue.removeFirst()
    }

    static func capture(_ req: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        capturedRequests.append(req)
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.capture(request)
        let stub = StubURLProtocol.popStub() ?? Stub(status: 200, headers: [:], body: Data())
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Build a `FloopFloop` client wired to a `URLSession` that intercepts
/// requests via ``StubURLProtocol``.
func makeStubbedClient(apiKey: String = "flp_test", baseURL: String = "https://stub.test") -> FloopFloop {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: cfg)
    return FloopFloop(apiKey: apiKey, baseURL: baseURL, session: session)
}
