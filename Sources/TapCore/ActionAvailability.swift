public enum ActionAvailability {
    public enum Mode: String, CaseIterable, Codable {
        case active = "Active"
        case test = "Test"
        case paused = "Paused"
    }

    public static func blockReason(mode: Mode, calibration: Bool, simulated: Bool,
                                   inactive: Bool, monitoringOnly: Bool) -> String? {
        if calibration { return "Calibration in progress" }
        if mode == .paused { return "Recognition paused" }
        if mode == .test { return "Test mode: system actions are off" }
        if inactive { return "Mac inactive: actions paused" }
        if simulated { return "Simulation: system actions unavailable" }
        if monitoringOnly { return "Below 50 Hz: recording only" }
        return nil
    }

    public static func canExecute(preview: Bool, blockReason: String?) -> Bool {
        !preview && blockReason == nil
    }
}
