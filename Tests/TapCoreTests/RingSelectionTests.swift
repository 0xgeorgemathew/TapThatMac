import XCTest
@testable import TapCore

final class RingSelectionTests: XCTestCase {
    func testKeyboardWrapPreservesRequestedDirection() {
        XCTAssertEqual(angle(315, 0, direction: 1), 360)
        XCTAssertEqual(angle(0, 7, direction: -1), -45)
        XCTAssertEqual(angle(675, 0, direction: 1), 720)
        XCTAssertEqual(angle(-360, 7, direction: -1), -405)
    }

    func testPointerTakesShortestRouteAcrossBothBoundaries() {
        XCTAssertEqual(angle(315, 0), 360)
        XCTAssertEqual(angle(0, 7), -45)
        XCTAssertEqual(angle(720, 6), 630)
        XCTAssertEqual(angle(-405, 1), -315)
    }

    func testDirectionCanChooseLongerRouteWhenRequired() {
        XCTAssertEqual(angle(45, 7, direction: 1), 315)
        XCTAssertEqual(angle(315, 1, direction: -1), 45)
        XCTAssertEqual(angle(45, 7), -45)
    }

    func testRapidForwardThenBackwardTargetsRemainContinuous() {
        var current = 315.0
        for (index, direction, expected) in [(0, 1, 360.0), (1, 1, 405.0), (0, -1, 360.0), (7, -1, 315.0), (6, -1, 270.0)] {
            current = angle(current, index, direction: direction)
            XCTAssertEqual(current, expected)
        }
    }

    func testPointerRetargetsFromAnIntermediatePresentedAngle() {
        // The renderer is still near the top even though its prior target was 180.
        XCTAssertEqual(angle(12, 7), -45)
        XCTAssertEqual(angle(348, 0), 360)
    }

    func testRepeatedSelectionNeverAddsARevolution() {
        for direction in [-1, 0, 1] {
            XCTAssertEqual(angle(720, 0, direction: direction), 720)
            XCTAssertEqual(angle(-45, 7, direction: direction), -45)
        }
    }

    func testSameCommandReselectIsANoopAtAnyPresentedAngle() {
        // Hovering the already-selected sector while its flight is still short
        // of the endpoint must settle on the nearest turn of that endpoint.
        for presented in [-721.5, -360, -181, -90.25, -0.75, 0, 0.75, 90.25, 179.5, 180.5, 359.25, 361, 718.5] {
            let result = angle(presented, 0)
            XCTAssertEqual(result.truncatingRemainder(dividingBy: 360), 0, accuracy: 0.0000001)
            XCTAssertLessThanOrEqual(abs(result - presented), 180.0000001)
        }
        // Settled exactly on the endpoint, the angle comes back untouched.
        XCTAssertEqual(angle(720, 0), 720)
        XCTAssertEqual(angle(-360, 0), -360)
    }

    func testFractionalSectorsRemainStableAcrossManyTurns() {
        for direction in [-1, 1] {
            var current = 0.0
            for step in 1...700 {
                let index = ((step * direction) % 7 + 7) % 7
                current = RingSelection.targetAngle(current: current, index: index, count: 7, direction: direction)
                XCTAssertEqual(current, Double(step * direction) * 360 / 7, accuracy: 0.00000001)
                XCTAssertEqual(RingSelection.targetAngle(current: current, index: index, count: 7, direction: direction), current)
            }
        }
    }

    func testInvalidGeometryLeavesCurrentAngleAlone() {
        XCTAssertEqual(RingSelection.targetAngle(current: 45, index: 0, count: 0, direction: 1), 45)
        XCTAssertEqual(angle(45, -1), 45)
        XCTAssertEqual(angle(45, 8), 45)
        XCTAssertEqual(angle(.infinity, 0), .infinity)
    }

    private func angle(_ current: Double, _ index: Int, direction: Int = 0) -> Double {
        RingSelection.targetAngle(current: current, index: index, count: 8, direction: direction)
    }
}
