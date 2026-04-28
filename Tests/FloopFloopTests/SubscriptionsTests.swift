import Foundation
import XCTest
@testable import FloopFloop

final class SubscriptionsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    func testCurrentPopulated() async throws {
        StubURLProtocol.enqueueJSON(#"""
        {"data":{
          "subscription":{
            "status":"active",
            "billingPeriod":"monthly",
            "currentPeriodStart":"2026-04-01T00:00:00Z",
            "currentPeriodEnd":"2026-05-01T00:00:00Z",
            "canceledAt":null,
            "planName":"pro",
            "planDisplayName":"Pro",
            "priceMonthly":29,
            "priceAnnual":290,
            "monthlyCredits":500,
            "maxProjects":50,
            "maxStorageMb":5000,
            "maxBandwidthMb":50000,
            "creditRolloverMonths":1,
            "features":{"teams":true}
          },
          "credits":{
            "current":423,
            "rolledOver":50,
            "total":473,
            "rolloverExpiresAt":"2026-05-01T00:00:00Z",
            "lifetimeUsed":1234
          }
        }}
        """#)
        let client = makeStubbedClient()
        let out = try await client.subscriptions.current()
        XCTAssertEqual(out.subscription?.planName, "pro")
        XCTAssertEqual(out.subscription?.monthlyCredits, 500)
        XCTAssertEqual(out.subscription?.billingPeriod, "monthly")
        XCTAssertNil(out.subscription?.canceledAt)
        XCTAssertEqual(out.credits?.total, 473)
        XCTAssertEqual(out.credits?.rolloverExpiresAt, "2026-05-01T00:00:00Z")

        // Verify the request hit the right path
        let req = StubURLProtocol.capturedRequests.first
        XCTAssertEqual(req?.url?.path, "/api/v1/subscriptions/current")
        XCTAssertEqual(req?.httpMethod, "GET")
    }

    func testCurrentBothNull() async throws {
        StubURLProtocol.enqueueJSON(#"{"data":{"subscription":null,"credits":null}}"#)
        let client = makeStubbedClient()
        let out = try await client.subscriptions.current()
        XCTAssertNil(out.subscription)
        XCTAssertNil(out.credits)
    }
}
