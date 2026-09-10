import XCTest
@testable import TapCore
final class RecentMotionBufferTests: XCTestCase {
    func testBoundsSamplesAndPreservesChronologicalReplay() {
        var buffer = RecentMotionBuffer()
        for i in 0..<16_000 {
            buffer.append(AccelerationSample(time: Double(i) / 800, x: 0, y: 0, z: 1))
        }
        buffer.appendKey(at: 1); buffer.appendKey(at: 19)
        let result = buffer.snapshot()
        XCTAssertEqual(result.samples.count, 12_000)
        XCTAssertEqual(result.samples.first?.time, 5)
        XCTAssertEqual(result.keyTimes, [19])
    }
    func testLowRateExpiresOldSamplesAndRejectsInvalidInput() {
        var buffer = RecentMotionBuffer()
        XCTAssertTrue(buffer.snapshot().samples.isEmpty)
        for i in 0...30 { buffer.append(AccelerationSample(time: Double(i), x: 0, y: 0, z: 1)) }
        buffer.append(AccelerationSample(time: 29, x: 0, y: 0, z: 1))
        buffer.append(AccelerationSample(time: 31, x: .nan, y: 0, z: 1))
        XCTAssertEqual(buffer.snapshot().samples.map(\.time), Array(15...30).map(Double.init))
    }
}
