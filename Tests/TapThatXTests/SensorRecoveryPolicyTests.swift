import XCTest
@testable import TapThatX

final class SensorRecoveryPolicyTests: XCTestCase {
    func testAccessFailuresSelectAutomaticHelperFallback() {
        XCTAssertTrue(SensorRecoveryPolicy.shouldAttemptHelper(after: "Sensor access denied"))
        XCTAssertTrue(SensorRecoveryPolicy.shouldAttemptHelper(after: "Sensor reports stopped"))
        XCTAssertTrue(SensorRecoveryPolicy.shouldAttemptHelper(after: "ACCESS DENIED"))
        XCTAssertFalse(SensorRecoveryPolicy.shouldAttemptHelper(after: "Streaming accelerometer"))
        XCTAssertFalse(SensorRecoveryPolicy.shouldAttemptHelper(after: "No sensor found"))
    }
}
