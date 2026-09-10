import Foundation

public struct AccelerationSample: Codable, Sendable {
    public let time: Double
    public let x: Double
    public let y: Double
    public let z: Double
    public init(time: Double, x: Double, y: Double, z: Double) {
        self.time = time; self.x = x; self.y = y; self.z = z
    }
}

public enum SamplingRate {
    public static let options = [1, 2, 5, 10, 20, 50, 100, 200, 400, 800]
    public static func intervalMicroseconds(for rate: Int) -> Int { 1_000_000 / max(1, min(800, rate)) }
}

public enum Preset: String, CaseIterable, Codable {
    case assistant = "ChatGPT controls"
    case doubleTapLock = "Double-tap Lock"
    case quickAction = "Quick Action"
    case commandRing = "Command Ring"
}

public enum Command: String, CaseIterable, Codable {
    // Clockwise from the top.
    case playPause = "Play / Pause", next = "Next Track", lock = "Lock Mac", previous = "Previous Track"
    public var symbol: String {
        switch self {
        case .playPause: return "playpause.fill"
        case .next: return "forward.end.fill"
        case .lock: return "lock.fill"
        case .previous: return "backward.end.fill"
        }
    }
}

public enum ReportDecoder {
    public static func decode(_ bytes: [UInt8], reportID: UInt32, time: Double) -> AccelerationSample? {
        bytes.withUnsafeBufferPointer { decode($0, reportID: reportID, time: time) }
    }
    // Vendor page 0xFF00, usage 3, report ID 0; Q16 signed little-endian XYZ.
    public static func decode(_ bytes: UnsafeBufferPointer<UInt8>, reportID: UInt32, time: Double) -> AccelerationSample? {
        guard bytes.count == 22, reportID == 0, time.isFinite, time >= 0 else { return nil }
        func axis(_ offset: Int) -> Double {
            let bits = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
            return Double(Int32(bitPattern: bits)) / 65536
        }
        return AccelerationSample(time: time, x: axis(6), y: axis(10), z: axis(14))
    }
}

public struct DetectorSettings: Codable {
    public var sensitivity: Double = 1
    public var suppressTyping = true
    public init() {}
    public static func sensitivity(forAmplitudeFloor value: Double) -> Double {
        guard value.isFinite else { return 2 }
        return min(7, 0.035 / min(0.07, max(0.005, value)))
    }
    public var amplitudeFloor: Double { 0.035 / max(0.5, min(7, sensitivity)) }
}
