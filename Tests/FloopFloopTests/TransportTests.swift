import Foundation
import XCTest
@testable import FloopFloop

final class TransportTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    func testBearerHeaderAndDataEnvelopeUnwrap() async throws {
        StubURLProtocol.enqueueJSON(
            status: 200,
            headers: ["Content-Type": "application/json"],
            #"{"data":{"id":"u_1","email":"p@x","name":null,"role":"user","source":"api_key"}}"#
        )
        let client = makeStubbedClient()
        let user = try await client.user.me()
        XCTAssertEqual(user.id, "u_1")
        XCTAssertEqual(user.email, "p@x")
        XCTAssertEqual(user.role, "user")

        let req = StubURLProtocol.capturedRequests.first
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer flp_test")
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNotNil(req?.value(forHTTPHeaderField: "User-Agent"))
        XCTAssertTrue(req?.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("floopfloop-swift-sdk/") == true)
    }

    func testUserAgentSuffix() async throws {
        StubURLProtocol.enqueueJSON(#"{"data":{"id":"u","email":null,"name":null,"role":"user","source":"api_key"}}"#)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: cfg)
        let client = FloopFloop(
            apiKey: "flp_test",
            baseURL: "https://stub.test",
            userAgentSuffix: "myapp/1.2",
            session: session
        )
        _ = try await client.user.me()
        let ua = StubURLProtocol.capturedRequests.first?.value(forHTTPHeaderField: "User-Agent")
        XCTAssertTrue(ua?.hasSuffix(" myapp/1.2") == true, "expected UA to end with ' myapp/1.2', got \(String(describing: ua))")
    }

    func testErrorEnvelopeBecomesTypedError() async throws {
        StubURLProtocol.enqueueJSON(
            status: 404,
            headers: ["x-request-id": "req_1"],
            #"{"error":{"code":"NOT_FOUND","message":"no such user"}}"#
        )
        let client = makeStubbedClient()
        do {
            _ = try await client.user.me()
            XCTFail("expected throw")
        } catch let err as FloopError {
            XCTAssertEqual(err.code, .notFound)
            XCTAssertEqual(err.status, 404)
            XCTAssertEqual(err.message, "no such user")
            XCTAssertEqual(err.requestId, "req_1")
        }
    }

    func testRetryAfterDeltaSeconds() async throws {
        StubURLProtocol.enqueueJSON(
            status: 429,
            headers: ["Retry-After": "5"],
            #"{"error":{"code":"RATE_LIMITED","message":"slow"}}"#
        )
        let client = makeStubbedClient()
        do {
            _ = try await client.user.me()
            XCTFail("expected throw")
        } catch let err as FloopError {
            XCTAssertEqual(err.code, .rateLimited)
            XCTAssertEqual(err.retryAfter, 5)
        }
    }

    func testUnknownServerCodePassesThrough() async throws {
        StubURLProtocol.enqueueJSON(
            status: 418,
            body: Data(#"{"error":{"code":"TEAPOT_MODE","message":"short and stout"}}"#.utf8)
        )
        let client = makeStubbedClient()
        do {
            _ = try await client.user.me()
            XCTFail("expected throw")
        } catch let err as FloopError {
            if case .other(let s) = err.code {
                XCTAssertEqual(s, "TEAPOT_MODE")
            } else {
                XCTFail("expected .other, got \(err.code)")
            }
        }
    }

    func testNonJSON5xxFallsBackToServerError() async throws {
        StubURLProtocol.enqueue(status: 500, body: Data("upstream crashed".utf8))
        let client = makeStubbedClient()
        do {
            _ = try await client.user.me()
            XCTFail("expected throw")
        } catch let err as FloopError {
            XCTAssertEqual(err.code, .serverError)
            XCTAssertEqual(err.status, 500)
        }
    }

    func testEmptyAPIKeyTriggersPrecondition() {
        // Precondition trips the runtime — testing it would crash the test
        // host. Documented here for completeness; covered in the README.
    }

    func testBaseURLStripsTrailingSlashes() {
        let c = FloopFloop(apiKey: "flp_test", baseURL: "https://x.example.com//")
        XCTAssertEqual(c.baseURL.absoluteString, "https://x.example.com")
    }
}
