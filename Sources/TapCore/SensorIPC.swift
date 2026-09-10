import Foundation

public enum SensorIPC {
    public static let service = "com.tapthatx.sensor"
    public static let appIdentifier = "com.tapthatx.app"
    public static let helperIdentifier = "com.tapthatx.sensor.helper"
    public static func requirement(identifier: String, team: String) -> String? {
        guard team.count == 10, team.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else { return nil }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }
}

@objc public protocol SensorService {
    func start(reply: @escaping (String) -> Void)
    func read(reply: @escaping (Data, String, Int, Double) -> Void)
    func stop(reply: @escaping () -> Void)
}
