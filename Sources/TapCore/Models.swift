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
    case approve = "ChatGPT: Approve once", reject = "ChatGPT: Reject", dictation = "ChatGPT: Dictation"
    public var assistantIntent: AssistantIntent? {
        switch self {
        case .approve: return .accept
        case .reject: return .reject
        case .dictation: return .dictation
        default: return nil
        }
    }
    public static func advancing(_ selected: Command?, by step: Int) -> Command {
        guard let selected, let index = allCases.firstIndex(of: selected) else {
            return step < 0 ? allCases.last! : allCases[0]
        }
        let count = allCases.count
        return allCases[((index + step) % count + count) % count]
    }
    public var symbol: String {
        switch self {
        case .playPause: return "playpause.fill"
        case .next: return "forward.end.fill"
        case .lock: return "lock.fill"
        case .previous: return "backward.end.fill"
        case .approve: return "checkmark"
        case .reject: return "xmark"
        case .dictation: return "mic.fill"
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

public struct DetectorSettings: Codable, Equatable {
    public static let minimumAmplitudeFloor = 0.002
    public static let maximumAmplitudeFloor = 0.07
    public static let minimumSensitivity = 0.5
    public static let maximumSensitivity = 17.5

    public var sensitivity: Double = 1
    public var suppressTyping = true
    /// Minimum onset speed for the broader knock envelope, in g/s.
    public var minimumRiseRate: Double = 1
    /// Light contacts use a shorter high-pass path and need a sharper onset.
    public var impulseMinimumRiseRate: Double = 3
    /// Contacts that remain above their confirmation level longer than this are motion, not taps.
    public var maximumPulseDuration: Double = 0.035
    /// Longest gap between deliberate contacts in one double tap.
    public var maximumTapInterval: Double = 0.45
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case sensitivity, suppressTyping, minimumRiseRate, impulseMinimumRiseRate, maximumPulseDuration,
             maximumTapInterval
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sensitivity = try values.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 1
        suppressTyping = try values.decodeIfPresent(Bool.self, forKey: .suppressTyping) ?? true
        minimumRiseRate = try values.decodeIfPresent(Double.self, forKey: .minimumRiseRate) ?? 1
        impulseMinimumRiseRate = try values.decodeIfPresent(Double.self, forKey: .impulseMinimumRiseRate) ?? 3
        maximumPulseDuration = try values.decodeIfPresent(Double.self, forKey: .maximumPulseDuration) ?? 0.035
        maximumTapInterval = try values.decodeIfPresent(Double.self, forKey: .maximumTapInterval) ?? 0.45
    }
    public static func sensitivity(forAmplitudeFloor value: Double) -> Double {
        guard value.isFinite else { return 2 }
        let floor = min(maximumAmplitudeFloor, max(minimumAmplitudeFloor, value))
        return min(maximumSensitivity, 0.035 / floor)
    }
    public var amplitudeFloor: Double {
        0.035 / max(Self.minimumSensitivity, min(Self.maximumSensitivity, sensitivity))
    }
}

public enum DoubleTapAction: String, CaseIterable {
    case ring = "Ring"
    case lock = "Lock Mac"
    case playPause = "Play / Pause"
    case next = "Next Track"
    case previous = "Previous Track"
    case approve = "ChatGPT: Approve once"
    case reject = "ChatGPT: Reject"
    case dictation = "ChatGPT: Dictation"

    public var command: Command? { Command(rawValue: rawValue) }

    public static func restored(saved: String?, preset: String?, quickAction: String?, assistantIntent: String?) -> Self {
        if let saved, let action = Self(rawValue: saved) { return action }
        switch preset.flatMap(Preset.init(rawValue:)) {
        case .commandRing: return .ring
        case .quickAction: return quickAction.flatMap(Self.init(rawValue:)) ?? .lock
        case .assistant:
            switch assistantIntent.flatMap(AssistantIntent.init(rawValue:)) {
            case .reject: return .reject
            case .dictation: return .dictation
            default: return .approve
            }
        default: return .lock
        }
    }
}
