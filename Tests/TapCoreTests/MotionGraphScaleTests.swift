import XCTest
@testable import TapCore

final class MotionGraphScaleTests: XCTestCase {
    func testSmallSignalsUseMeaningfulPlotHeight() {
        XCTAssertGreaterThan(MotionGraphScale.detail.position(for: 0.001), 0.14)
        XCTAssertGreaterThan(MotionGraphScale.detail.position(for: 0.006), 0.42)
        XCTAssertEqual(MotionGraphScale.linear.position(for: 0.006), 0.06, accuracy: 1e-10)
    }

    func testDraggingRoundTripsAcrossFullThresholdRange() {
        for scale in MotionGraphScale.allCases {
            for amplitude in stride(from: 0.005, through: 0.07, by: 0.0005) {
                XCTAssertEqual(scale.amplitude(at: scale.position(for: amplitude)), amplitude, accuracy: 1e-10)
            }
            XCTAssertEqual(scale.position(for: 0), 0)
            XCTAssertEqual(scale.position(for: 0.1), 1)
            XCTAssertEqual(scale.amplitude(at: 0), 0)
            XCTAssertEqual(scale.amplitude(at: 1), 0.1, accuracy: 1e-10)
        }
    }

    func testScaleIsMonotonicAndTicksRemainReadable() {
        for scale in MotionGraphScale.allCases {
            let positions = scale.ticks.map { scale.position(for: $0) }
            for (a, b) in zip(positions, positions.dropFirst()) {
                XCTAssertGreaterThan(b - a, 0.1)
            }
        }
    }

    func testOutOfRangeAndInvalidInputsAreBounded() {
        for scale in MotionGraphScale.allCases {
            XCTAssertEqual(scale.position(for: -1), 0)
            XCTAssertEqual(scale.position(for: 10), 1)
            XCTAssertEqual(scale.position(for: .nan), 0)
            XCTAssertEqual(scale.amplitude(at: -1), 0)
            XCTAssertEqual(scale.amplitude(at: 10), 0.1, accuracy: 1e-10)
            XCTAssertEqual(scale.amplitude(at: .infinity), 0)
        }
    }
}
