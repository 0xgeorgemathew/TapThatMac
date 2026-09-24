import Foundation

public enum CalibrationActivity: String, Codable, CaseIterable {
    case quiet, everydayMotion, lightTap, knock, lightPair, knockPair

    public var title: String {
        switch self {
        case .quiet: return "Quiet background"
        case .everydayMotion: return "Everyday movement"
        case .lightTap: return "One light tap"
        case .knock: return "One knock"
        case .lightPair: return "Two light taps"
        case .knockPair: return "Two knocks"
        }
    }
    public var expectedContacts: Int {
        switch self {
        case .quiet, .everydayMotion: return 0
        case .lightTap, .knock: return 1
        case .lightPair, .knockPair: return 2
        }
    }
    public var instruction: String {
        switch self {
        case .quiet: return "Leave your hands off the surface and keep still."
        case .everydayMotion: return "Use your keyboard and trackpad normally. Move your hands as usual, without deliberate taps or knocks."
        case .lightTap: return "When “Tap now” appears, touch the chosen surface once with your finger pad, then lift your hand."
        case .knock: return "When “Tap now” appears, knock once with your knuckle or nail, then lift your hand."
        case .lightPair: return "When “Tap now” appears, make two light taps about a quarter-second apart."
        case .knockPair: return "When “Tap now” appears, make two knocks about a quarter-second apart."
        }
    }
}

public enum CalibrationPartition: String, Codable { case training, verification }

public struct CalibrationStep: Codable, Equatable {
    public let activity: CalibrationActivity
    public let partition: CalibrationPartition
    public var duration: Double { activity.expectedContacts == 0 ? 10 : 6.5 }
    public init(_ activity: CalibrationActivity, _ partition: CalibrationPartition) {
        self.activity = activity; self.partition = partition
    }
    public static let sequence: [CalibrationStep] = [
        .init(.quiet, .training), .init(.everydayMotion, .training),
        .init(.lightTap, .training), .init(.lightTap, .training), .init(.lightTap, .training),
        .init(.knock, .training), .init(.knock, .training), .init(.knock, .training),
        .init(.quiet, .verification), .init(.everydayMotion, .verification),
        .init(.lightTap, .verification), .init(.lightTap, .verification),
        .init(.knock, .verification), .init(.knock, .verification),
        .init(.lightPair, .verification), .init(.knockPair, .verification)
    ]
}

public struct CalibrationContext: Codable {
    public let surface: String
    public let placement: String
    public let device: String
    public let os: String
    public let input: String
    public let requestedRate: Int
    public let initialSettings: DetectorSettings
    public init(surface: String, placement: String, device: String, os: String,
                input: String, requestedRate: Int, initialSettings: DetectorSettings) {
        self.surface = surface; self.placement = placement; self.device = device
        self.os = os; self.input = input; self.requestedRate = requestedRate
        self.initialSettings = initialSettings
    }
}

public struct CalibrationQuality: Codable {
    public let measuredRate: Double
    public let maximumGap: Double
    public let maximumDeliveryDelay: Double
    public let issues: [String]
    public var usable: Bool { issues.isEmpty }
}

/// A cue window is an interval reported by the user, never a detector-generated label.
public struct CalibrationTrial: Codable, Identifiable {
    public let id: UUID
    public let step: CalibrationStep
    public let started: Double
    public let ended: Double
    public let cueTime: Double?
    public let responseEnd: Double?
    public let samples: [AccelerationSample]
    public let keyTimes: [Double]
    public let quality: CalibrationQuality
    public var confirmed = false
}

public struct CalibrationSession: Codable {
    public let schemaVersion: Int
    public let detectorVersion: String
    public let id: UUID
    public let created: Date
    public let context: CalibrationContext
    public var trials: [CalibrationTrial] = []
    public var candidateFloor: Double?
    public var verificationPassed = false
    public var finished = false
    public init(context: CalibrationContext) {
        schemaVersion = 1; detectorVersion = "dual-pulse-v1"
        id = UUID(); created = Date(); self.context = context
    }
}
