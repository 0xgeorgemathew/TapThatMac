import XCTest
@testable import TapCore

final class MotionTraceTests: XCTestCase {
    func testBriefPeakSurvivesDisplayDownsampling() {
        var trace = MotionTrace()
        trace.append(time: 1, amplitude: 0.001, threshold: 0.02)
        trace.append(time: 1.001, amplitude: 0.12, threshold: 0.02)
        trace.append(time: 1.002, amplitude: 0.001, threshold: 0.02)
        XCTAssertEqual(trace.points.count, 1)
        XCTAssertEqual(trace.points[0].peak, 0.12)
    }

    func testImpulsePeakAndGateSurviveDisplayDownsampling() {
        var trace = MotionTrace()
        trace.append(time: 1, amplitude: 0.01, threshold: 0.02,
                     impulseAmplitude: 0.006, impulseThreshold: 0.005)
        trace.append(time: 1.001, amplitude: 0.008, threshold: 0.02,
                     impulseAmplitude: 0.001, impulseThreshold: 0.004)
        XCTAssertEqual(trace.points.count, 1)
        XCTAssertEqual(trace.points[0].impulsePeak, 0.006)
        XCTAssertEqual(trace.points[0].impulseThreshold, 0.004)
        trace.append(time: 1.03, amplitude: 0.003, threshold: 0.02)
        XCTAssertNil(trace.points.last?.impulsePeak)
    }

    func testHistoryIsBoundedAndChronological() {
        var trace = MotionTrace()
        for index in 0..<2000 {
            trace.append(time: Double(index) * 0.03, amplitude: Double(index), threshold: 0.02)
        }
        XCTAssertEqual(trace.points.count, MotionTrace.capacity)
        XCTAssertEqual(trace.points.last?.peak, 1999)
        XCTAssertTrue(zip(trace.points, trace.points.dropFirst()).allSatisfy { $0.time < $1.time })
    }

    func testInvalidAndStaleSamplesDoNotCorruptGraph() {
        var trace = MotionTrace()
        trace.append(time: 1, amplitude: 0.1, threshold: 0.02)
        trace.append(time: 0.5, amplitude: 10, threshold: 0.02)
        trace.append(time: 2, amplitude: .nan, threshold: 0.02)
        XCTAssertEqual(trace.points.count, 1)
        XCTAssertEqual(trace.points[0].peak, 0.1)
    }

    func testBorrowedSensorReportDecodesSignedAxesAndRejectsMalformedReports() {
        var bytes = [UInt8](repeating: 0, count: 22)
        bytes.replaceSubrange(6..<10, with: [0, 128, 1, 0]) // 1.5 g
        bytes.replaceSubrange(10..<14, with: [0, 192, 255, 255]) // -0.25 g
        bytes.replaceSubrange(14..<18, with: [0, 0, 1, 0]) // 1 g
        bytes.withUnsafeBufferPointer { buffer in
            let sample = ReportDecoder.decode(buffer, reportID: 0, time: 10)
            XCTAssertEqual(sample?.x, 1.5)
            XCTAssertEqual(sample?.y, -0.25)
            XCTAssertEqual(sample?.z, 1)
            XCTAssertNil(ReportDecoder.decode(buffer, reportID: 1, time: 10))
        }
        XCTAssertNil(ReportDecoder.decode(Array(bytes.dropLast()), reportID: 0, time: 10))
    }

    func testThresholdControlPreservesExistingSensitivityRange() {
        for sensitivity in [0.5, 1.0, 2.0] {
            var settings = DetectorSettings(); settings.sensitivity = sensitivity
            XCTAssertEqual(DetectorSettings.sensitivity(forAmplitudeFloor: settings.amplitudeFloor), sensitivity, accuracy: 0.000001)
        }
        XCTAssertEqual(DetectorSettings.sensitivity(forAmplitudeFloor: 0), 17.5)
        XCTAssertEqual(DetectorSettings.sensitivity(forAmplitudeFloor: 0.002), 17.5, accuracy: 0.000001)
        var settings = DetectorSettings()
        settings.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: 0.002)
        XCTAssertEqual(settings.amplitudeFloor, 0.002, accuracy: 0.000001)
        XCTAssertEqual(DetectorSettings.sensitivity(forAmplitudeFloor: 1), 0.5)
        XCTAssertEqual(DetectorSettings.sensitivity(forAmplitudeFloor: .nan), 2)
    }
}
