import XCTest
@testable import TapCore

final class GestureAndBufferTests: XCTestCase {
    func testTripleDoesNotAlsoEmitDouble() {
        var router = GestureRouter(recognizesTriples: true)
        XCTAssertTrue(router.knock(at: 1).isEmpty)
        XCTAssertTrue(router.knock(at: 1.2).isEmpty)
        XCTAssertEqual(router.knock(at: 1.4), [.triple])
        XCTAssertNil(router.advance(to: 2))
    }
    func testDoubleWaitsForThirdTapWindow() {
        var router = GestureRouter(recognizesTriples: true)
        _ = router.knock(at: 1); _ = router.knock(at: 1.2)
        XCTAssertNil(router.advance(to: 1.6))
        XCTAssertEqual(router.advance(to: 1.66), .double)
        XCTAssertNil(router.advance(to: 2))
    }
    func testEchoDoesNotBecomeThirdTap() {
        var router = GestureRouter(recognizesTriples: true)
        _ = router.knock(at: 1); _ = router.knock(at: 1.2)
        XCTAssertTrue(router.knock(at: 1.23).isEmpty)
        XCTAssertEqual(router.advance(to: 1.66), .double)
    }
    func testResetCancelsPendingDouble() {
        var router = GestureRouter(recognizesTriples: true)
        _ = router.knock(at: 1); _ = router.knock(at: 1.2)
        router.reset()
        XCTAssertNil(router.advance(to: 2))
    }
    func testSingleCanCycleAfterOpeningCooldown() {
        var router = GestureRouter(recognizesTriples: true)
        router.consumeOpening(at: 1)
        XCTAssertTrue(router.knock(at: 1.1).isEmpty)
        _ = router.knock(at: 1.5)
        XCTAssertEqual(router.advance(to: 2), .single)
    }
    func testInboxRejectsOldConnectionAndDrainsOnce() {
        let inbox = SensorInbox()
        inbox.reset(generation: 2)
        inbox.append(AccelerationSample(time: 1, x: 0, y: 0, z: 1), generation: 1)
        inbox.status("Old status", generation: 1)
        inbox.append(AccelerationSample(time: 2, x: 0, y: 0, z: 1), generation: 2)
        let batch = inbox.take()
        XCTAssertEqual(batch.samples.map(\.time), [2])
        XCTAssertTrue(batch.statuses.isEmpty)
        XCTAssertTrue(inbox.take().samples.isEmpty)
    }
    func testInboxReportsMalformedReportsOnlyForCurrentConnection() {
        let inbox = SensorInbox()
        inbox.reset(generation: 2)
        inbox.reject(generation: 1); inbox.reject(generation: 2)
        XCTAssertEqual(inbox.take().dropped, 1)
        XCTAssertEqual(inbox.take().dropped, 0)
    }
    func testInboxBoundsBacklogAndReportsLoss() {
        let inbox = SensorInbox()
        inbox.reset(generation: 1)
        for index in 0..<600 {
            inbox.append(AccelerationSample(time: Double(index), x: 0, y: 0, z: 1), generation: 1)
        }
        let batch = inbox.take()
        XCTAssertEqual(batch.dropped, 512)
        XCTAssertEqual(batch.samples.count, 88)
        XCTAssertEqual(batch.samples.first?.time, 512)
        XCTAssertEqual(batch.samples.last?.time, 599)
    }
}
