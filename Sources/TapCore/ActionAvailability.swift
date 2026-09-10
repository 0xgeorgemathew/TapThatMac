public enum ActionAvailability {
    public static func blockReason(calibration: Bool, settingsOpen: Bool, simulated: Bool,
                                   paused: Bool, inactive: Bool, recording: Bool,
                                   enabled: Bool, monitoringOnly: Bool) -> String? {
        if recording { return "Recording: actions paused" }
        if calibration { return "Calibration: use Enable & close to finish" }
        if settingsOpen { return "Settings open: taps are previewed only" }
        if paused { return "Recognition paused" }
        if inactive { return "Mac inactive: actions paused" }
        if simulated { return "Simulation: system actions unavailable" }
        if monitoringOnly { return "Below 50 Hz: recording only" }
        if !enabled { return "System actions switched off" }
        return nil
    }
}
