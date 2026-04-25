import Foundation
import XCTest
@testable import FloopFloop

final class ProjectsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    func testCreateAndGet() async throws {
        let createBody = """
        {"data":{
          "project":{"id":"p_1","name":"Test","subdomain":"test","status":"queued",
                    "botType":"site","url":null,"amplifyAppUrl":null,
                    "isPublic":false,"isAuthProtected":true,"teamId":null,
                    "createdAt":"2026-04-25T00:00:00Z","updatedAt":"2026-04-25T00:00:00Z",
                    "thumbnailUrl":null},
          "deployment":{"id":"d_1","status":"pending","version":1}
        }}
        """
        StubURLProtocol.enqueueJSON(createBody)

        let client = makeStubbedClient()
        let created = try await client.projects.create(.init(prompt: "demo", subdomain: "test"))
        XCTAssertEqual(created.project.id, "p_1")
        XCTAssertEqual(created.project.subdomain, "test")
        XCTAssertEqual(created.deployment.version, 1)
    }

    func testGetFiltersList() async throws {
        let listBody = """
        {"data":[
          {"id":"p_1","name":"A","subdomain":"a","status":"live","botType":"site","url":"https://a.x","amplifyAppUrl":null,"isPublic":false,"isAuthProtected":true,"teamId":null,"createdAt":"2026-04-25T00:00:00Z","updatedAt":"2026-04-25T00:00:00Z","thumbnailUrl":null},
          {"id":"p_2","name":"B","subdomain":"b","status":"queued","botType":"site","url":null,"amplifyAppUrl":null,"isPublic":false,"isAuthProtected":true,"teamId":null,"createdAt":"2026-04-25T00:00:00Z","updatedAt":"2026-04-25T00:00:00Z","thumbnailUrl":null}
        ]}
        """
        StubURLProtocol.enqueueJSON(listBody)
        let client = makeStubbedClient()
        let p = try await client.projects.get("b")
        XCTAssertEqual(p.id, "p_2")
    }

    func testGetMissingThrowsNotFound() async throws {
        StubURLProtocol.enqueueJSON(#"{"data":[]}"#)
        let client = makeStubbedClient()
        do {
            _ = try await client.projects.get("nope")
            XCTFail("expected NOT_FOUND")
        } catch let err as FloopError {
            XCTAssertEqual(err.code, .notFound)
            XCTAssertEqual(err.status, 404)
        }
    }

    func testRefineProcessingShape() async throws {
        StubURLProtocol.enqueueJSON(#"{"processing":true,"deploymentId":"d_42","queuePriority":3}"#)
        let client = makeStubbedClient()
        let res = try await client.projects.refine("test", .init(message: "tweak"))
        XCTAssertNotNil(res.processing)
        XCTAssertEqual(res.processing?.deploymentId, "d_42")
        XCTAssertEqual(res.processing?.queuePriority, 3)
        XCTAssertNil(res.queued)
        XCTAssertNil(res.savedOnly)
    }

    func testRefineQueuedShape() async throws {
        StubURLProtocol.enqueueJSON(#"{"queued":true,"messageId":"m_7"}"#)
        let client = makeStubbedClient()
        let res = try await client.projects.refine("test", .init(message: "tweak"))
        XCTAssertNotNil(res.queued)
        XCTAssertEqual(res.queued?.messageId, "m_7")
    }

    func testRefineSavedOnlyShape() async throws {
        StubURLProtocol.enqueueJSON(#"{"queued":false}"#)
        let client = makeStubbedClient()
        let res = try await client.projects.refine("test", .init(message: "tweak"))
        XCTAssertNotNil(res.savedOnly)
        XCTAssertNil(res.queued)
    }
}
