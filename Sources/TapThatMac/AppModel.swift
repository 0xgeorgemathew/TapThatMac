import AppKit
import SwiftUI
import ServiceManagement
import TapCore
import Combine

/// One accepted tap, and whether it completed or opened a recognized pair.
struct TapMark: Equatable {
    let time: Double
    var paired = false
}

enum InputMode: String { case sensor = "Direct sensor", helper = "Sensor helper", simulated = "Simulated input" }

enum SensorRecoveryPolicy {
    static func shouldAttemptHelper(after status: String) -> Bool {
        status.range(of: "access denied", options: .caseInsensitive) != nil
            || status.range(of: "reports stopped", options: .caseInsensitive) != nil
    }
}

enum OperatingModeMigration {
    static func restore(savedMode: String?, wasPaused: Bool, actionsEnabled: Bool?) -> ActionAvailability.Mode {
        if let savedMode, let mode = ActionAvailability.Mode(rawValue: savedMode) { return mode }
        if wasPaused { return .paused }
        if actionsEnabled == false { return .test }
        return .active
    }
}

final class AppModel: ObservableObject {
    @Published var doubleTapAction = DoubleTapAction.restored(
        saved: UserDefaults.standard.string(forKey: "doubleTapAction"),
        preset: UserDefaults.standard.string(forKey: "preset"),
        quickAction: UserDefaults.standard.string(forKey: "quickAction"),
        assistantIntent: UserDefaults.standard.string(forKey: "assistantIntent")
    ) { didSet {
        UserDefaults.standard.set(doubleTapAction.rawValue, forKey: "doubleTapAction")
        resetInteraction(resetDetector: false); logSettings()
    } }
    // Keep the existing diagnostic export format readable by older tools.
    var preset: Preset {
        if doubleTapAction == .ring { return .commandRing }
        if doubleTapAction.command?.assistantIntent != nil { return .assistant }
        return doubleTapAction == .lock ? .doubleTapLock : .quickAction
    }
    private(set) var input: InputMode = .sensor { didSet { restart() } }
    private(set) var sampleRate: Int = {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--sample-rate"),
              args.indices.contains(index + 1), let requested = Int(args[index + 1]),
              SamplingRate.options.contains(requested) else {
            return 800
        }
        return requested
    }()
    @Published var operatingMode: ActionAvailability.Mode { didSet {
        modeDefaults.set(operatingMode.rawValue, forKey: "operatingMode")
        restart(); logSettings()
    } }
    var paused: Bool { operatingMode == .paused }
    @Published var sensitivity = 2.0 {
        didSet {
            guard !isRestoringSettings else { return }
            settingsDefaults.set(sensitivity, forKey: "knockSensitivity")
            detector.settings.sensitivity = sensitivity
            if !applyingProfile {
                activeCalibrationProfile = nil
                settingsDefaults.removeObject(forKey: "activeCalibrationProfileID")
                settingsDefaults.removeObject(forKey: "calibrationSessionID")
            }
            persistDetectorSettings()
            resetInteraction(); logSettings()
        }
    }
    @Published var suppressTyping = true { didSet {
        guard !isRestoringSettings else { return }
        detector.settings.suppressTyping = suppressTyping
        persistDetectorSettings(); resetInteraction(); logSettings()
    } }
    private let legacyCalibrationMode = CommandLine.arguments.contains("--calibrate")
    @Published var status = "Starting"
    @Published var helperStatus = HelperClient.status
    @Published var acknowledgment = "Choose your double-tap action in Actions"
    private(set) var sampleCount = 0
    private(set) var rate = 0.0
    private(set) var rejected = 0
    private(set) var knocks = 0
    private(set) var recognizedPairs = 0
    private var lastLoggedRejection = -Double.infinity
    private var lastLoggedReason = ""
    private(set) var lastDoubleTime: Double?
    @Published var typingPermission = false
    @Published var accessibilityPermission = false
    @Published private(set) var calibrationProfiles: [CalibrationProfile] = []
    @Published private(set) var activeCalibrationProfile: CalibrationProfile?
    let diagnostics = DiagnosticsStore()
    let calibration: CalibrationController
    private var calibrationObservation: AnyCancellable?
    private var lastCalibrationRejected = 0
    let ring = RadialPanelController()
    private let sensor = BufferedSensorReader()
    private let helper = HelperClient()
    private lazy var toast = AcknowledgmentController(isRedundant: { [weak self] in
        NSApp.isActive && self?.setupIsVisible == true
    })
    private var detector = KnockDetector()
    private var applyingProfile = false
    // Published observers run during init after all stored properties exist.
    // Restore the complete detector and profile before enabling edit side effects.
    private var isRestoringSettings = true
    private var router = GestureRouter(burstGuard: KnockPolicy.pairBurstGuard)
    private var lastKeyTime: Double?
    private var timer: Timer?
    private let typingMonitor = TypingMonitor()
    private var localKeyMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var inactiveReasons: Set<String> = []
    private var simulatedUntil = 0.0
    private var generation = 0
    private var lastStatus = ""
    private var lastSensorTime: Double?
    private var pendingImpacts: [Double] = []
    private var simulationStarted = 0.0
    private var lastSampleAt = 0.0
    weak var setupWindow: NSWindow?
    var reopenMainWindow: (() -> Void)?
    var refreshGraph: (() -> Void)?
    var graphIsAttached = false
    private(set) var motionTrace = MotionTrace()
    // Reactive UI signals (glass redesign pass 2). Both are fed from the
    // existing main-runloop tick, never per sensor sample.
    /// Decaying envelope of current motion magnitude in g (the same peaks the
    /// graph renders), sent at most every 100 ms while settings are visible.
    /// Falls toward zero when the stream stalls so reactive UI settles.
    let liveAmplitude = PassthroughSubject<Double, Never>()
    /// Fires once per accepted tap (each member of a pair fires once).
    let tapDetected = PassthroughSubject<Void, Never>()
    /// Fires once per recognized double-tap, whatever it then does.
    let doubleTapRecognized = PassthroughSubject<Void, Never>()
    /// Recent accepted taps in sensor time, for the graph's tap markers.
    private(set) var recentTaps: [TapMark] = []
    private var lastLiveAmplitudeAt = 0.0
    private var liveLevel = 0.0
    private var collectGraph = false
    private var lastRuntimeWrite = 0.0
    private(set) var isShutdown = false
    var setupIsVisible: Bool { setupWindow?.isVisible == true && setupWindow?.occlusionState.contains(.visible) == true }
    var amplitudeFloor: Double { detector.settings.amplitudeFloor }
    var liveWarmingUp: Bool { detector.warmingUp }
    private(set) var ringPreviewActive = false
    func setAmplitudeFloor(_ value: Double) {
        sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: value)
    }
    private var lastPermissionRefresh = 0.0
    private var lastPresentationTime = 0.0
    private var launchPermissionsRequested = false
    private var helperSetupRequested = false
    private var waitingForHelperApproval = false
    private var applicationObservers: [NSObjectProtocol] = []
    private var awaitingLock = false
    private var showLockReceiptOnReturn = false
    private var lockAttempt = 0
    private let settingsDefaults: UserDefaults
    private let modeDefaults: UserDefaults
    private let servicesEnabled: Bool
    private let commandExecution: ((Command, Bool) -> String)?
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    var actionBlockReason: String? {
        if legacyCalibrationMode { return "Legacy calibration mode: system actions are off" }
        let reason = ActionAvailability.blockReason(mode: operatingMode,
            calibration: calibration.blocksActions, simulated: input == .simulated,
            inactive: !inactiveReasons.isEmpty, monitoringOnly: input == .sensor && sampleRate < 50)
        if reason != nil { return reason }
        return accessibilityPermission ? nil : "Allow Accessibility to run system actions"
    }
    var canEnableActions: Bool { actionBlockReason == nil }
    var actionStatus: String { actionBlockReason ?? "Ready · \(doubleTapAction.rawValue)" }

    var calibrationUnavailableReason: String? {
        if input == .simulated { return "Calibration requires the connected sensor." }
        if paused || !inactiveReasons.isEmpty { return "Resume the sensor in an active session." }
        if !setupIsVisible { return "Keep Tap That Mac visible during calibration." }
        if status != "Streaming accelerometer" { return "Connect the sensor before recording." }
        if sampleRate != 800 { return "Calibration requires the normal 800 Hz sensor rate." }
        if rate < 700 || rate > 900 { return "Waiting for a steady sensor stream near 800 Hz." }
        if !typingPermission { return "Enable Input Monitoring so overlapping typing can be identified." }
        if calibration.blocksActions, let context = calibration.session?.context,
           context.input != input.rawValue || context.requestedRate != (input == .helper ? 800 : sampleRate)
            || context.initialSettings.sensitivity != sensitivity {
            return "Input or sensitivity changed. Cancel and start a fresh calibration session."
        }
        return nil
    }
    var canStartCalibration: Bool { calibrationUnavailableReason == nil }

    func beginCalibration(setup: DeskSetup = .openMac) {
        guard canStartCalibration else { return }
        resetInteraction()
        calibration.begin(context: CalibrationContext(surface: setup.rawValue, placement: diagnostics.model,
            device: diagnostics.model, os: ProcessInfo.processInfo.operatingSystemVersionString,
            input: input.rawValue, requestedRate: input == .helper ? 800 : sampleRate,
            initialSettings: detector.settings, includesSurfaceBumps: true))
    }
    func recordCalibrationTrial() {
        guard canStartCalibration else { return }
        lastCalibrationRejected = rejected
        calibration.record(at: now)
    }
    func cancelCalibration() {
        if calibration.cancel(at: now) { resetInteraction() }
    }

    func handleWindowClose() {
        if calibration.blocksActions { cancelCalibration() }
    }
    func applyCalibration() {
        guard calibration.stage == .complete, calibration.session?.verificationPassed == true,
              var settings = calibration.candidateSettings, let session = calibration.session,
              canStartCalibration, session.context.input == input.rawValue else { return }
        settings.suppressTyping = suppressTyping
        applyingProfile = true
        sensitivity = settings.sensitivity
        detector.settings = settings
        router = GestureRouter(maximumInterval: settings.maximumTapInterval, burstGuard: KnockPolicy.pairBurstGuard)
        applyingProfile = false
        persistDetectorSettings()
        let profile = CalibrationProfile(session: session, settings: settings)
        calibrationProfiles.removeAll { $0.id == profile.id }
        calibrationProfiles.insert(profile, at: 0)
        activeCalibrationProfile = profile
        persistCalibrationProfiles()
        settingsDefaults.set(profile.id.uuidString, forKey: "activeCalibrationProfileID")
        settingsDefaults.set(profile.id.uuidString, forKey: "calibrationSessionID")
        calibration.markApplied()
        acknowledgment = "Your personal tap profile is active."
        diagnostics.log("calibration", "Applied session \(session.id); floor=\(settings.amplitudeFloor); rise=\(settings.minimumRiseRate)/\(settings.impulseMinimumRiseRate); duration=\(settings.maximumPulseDuration); pair=\(settings.maximumTapInterval)")
    }

    func activateCalibrationProfile(_ id: UUID) {
        guard let profile = calibrationProfiles.first(where: { $0.id == id }), !calibration.blocksActions else { return }
        var settings = profile.settings
        settings.suppressTyping = suppressTyping
        applyingProfile = true
        sensitivity = settings.sensitivity
        detector.settings = settings
        router = GestureRouter(maximumInterval: settings.maximumTapInterval, burstGuard: KnockPolicy.pairBurstGuard)
        applyingProfile = false
        activeCalibrationProfile = profile
        persistDetectorSettings()
        settingsDefaults.set(id.uuidString, forKey: "activeCalibrationProfileID")
        acknowledgment = "\(profile.name) profile applied"
    }

    func keepCurrentSettingsWithoutProfile() {
        activeCalibrationProfile = nil
        settingsDefaults.removeObject(forKey: "activeCalibrationProfileID")
        settingsDefaults.removeObject(forKey: "calibrationSessionID")
        acknowledgment = "Current detector settings kept without a tap profile"
    }

    init(startServices: Bool = true, calibration: CalibrationController = CalibrationController(),
         modeDefaults: UserDefaults = .standard,
         settingsDefaults: UserDefaults = .standard,
         commandExecution: ((Command, Bool) -> String)? = nil) {
        self.settingsDefaults = settingsDefaults
        self.modeDefaults = modeDefaults
        self.commandExecution = commandExecution
        servicesEnabled = startServices
        operatingMode = OperatingModeMigration.restore(
            savedMode: modeDefaults.string(forKey: "operatingMode"),
            wasPaused: modeDefaults.bool(forKey: "paused"),
            actionsEnabled: modeDefaults.object(forKey: "actionsEnabled") as? Bool
        )
        self.calibration = calibration
        calibrationObservation = calibration.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        let storedSettings = loadDetectorSettings()
        var savedSettings = storedSettings ?? DetectorSettings()
        if storedSettings == nil {
            let savedSensitivity = settingsDefaults.object(forKey: "knockSensitivity") as? Double ?? 2.0
            savedSettings.sensitivity = savedSensitivity.isFinite
                ? min(DetectorSettings.maximumSensitivity,
                      max(DetectorSettings.minimumSensitivity, savedSensitivity)) : 2.0
        }
        sensitivity = savedSettings.sensitivity
        suppressTyping = savedSettings.suppressTyping
        detector.settings = savedSettings
        router = GestureRouter(maximumInterval: savedSettings.maximumTapInterval, burstGuard: KnockPolicy.pairBurstGuard)
        calibrationProfiles = loadCalibrationProfiles()
        if let rawID = settingsDefaults.string(forKey: "activeCalibrationProfileID"),
           let id = UUID(uuidString: rawID) {
            activeCalibrationProfile = calibrationProfiles.first { $0.id == id }
        }
        isRestoringSettings = false
        ring.onChoose = { [weak self] in self?.execute($0) }
        ring.onDismiss = { [weak self] in
            self?.ringPreviewActive = false
            self?.router.reset()
            self?.diagnostics.log("ring", "Dismissed; ready for a new pair")
        }
        guard startServices else { return }
        sensor.onSamples = { [weak self] in self?.ingest($0) }
        sensor.onStatus = { [weak self] in self?.sensorStatus($0) }
        helper.onSamples = { [weak self] in self?.ingest($0) }
        helper.onStatus = { [weak self] in self?.sensorStatus($0) }
        observeLifecycle()
        applicationObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { [weak self] _ in
            self?.requestLaunchPermissions()
        })
        applicationObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshPermissions()
        })
        if NSApp?.isRunning == true { DispatchQueue.main.async { [weak self] in self?.requestLaunchPermissions() } }
        typingMonitor.onKey = { [weak self] in self?.noteKey() }
        typingMonitor.onPointer = { [weak self] in self?.notePointer() }
        refreshPermissions()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.noteKey(); return event
        }
        configureTimer()
        diagnostics.log("session", "model=\(diagnostics.model); \(ProcessInfo.processInfo.operatingSystemVersionString)")
        restart()
    }
    private func configureTimer() {
        let interval = (paused || !inactiveReasons.isEmpty) ? 0.5
            : (!setupIsVisible && input == .sensor && sampleRate < 20 ? 1.0 / Double(sampleRate) : 0.05)
        guard timer?.timeInterval != interval else { return }
        timer?.invalidate()
        let tickTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        tickTimer.tolerance = min(0.005, interval / 10)
        timer = tickTimer
        RunLoop.main.add(tickTimer, forMode: .common)
    }
    private func logSettings() {
        diagnostics.log("settings", "preset=\(preset.rawValue); action=\(doubleTapAction.rawValue); input=\(input.rawValue); sampleRate=\(sampleRate); sensitivity=\(sensitivity); typing=\(suppressTyping); mode=\(operatingMode.rawValue)")
    }
    private func persistDetectorSettings() {
        guard let data = try? JSONEncoder().encode(detector.settings) else { return }
        settingsDefaults.set(data, forKey: "detectorSettings")
    }
    private func loadDetectorSettings() -> DetectorSettings? {
        guard let data = settingsDefaults.data(forKey: "detectorSettings") else { return nil }
        return try? JSONDecoder().decode(DetectorSettings.self, from: data)
    }
    private func persistCalibrationProfiles() {
        guard let data = try? JSONEncoder().encode(calibrationProfiles) else { return }
        settingsDefaults.set(data, forKey: "calibrationProfiles")
    }
    private func loadCalibrationProfiles() -> [CalibrationProfile] {
        guard let data = settingsDefaults.data(forKey: "calibrationProfiles"),
              let profiles = try? JSONDecoder().decode([CalibrationProfile].self, from: data) else { return [] }
        return profiles
    }
    /// A click vetoes nearby contacts like a key does, but it isn't typing, so
    /// calibration doesn't flag it.
    private func notePointer() {
        lastKeyTime = now
        diagnostics.recent.appendKey(at: now)
        if suppressTyping { pendingImpacts.removeAll(); router.reset() }
    }
    private func noteKey() {
        // Never retain characters, key codes, or application identity.
        calibration.key(at: now)
        lastKeyTime = now
        diagnostics.markKey(at: now)
        diagnostics.recent.appendKey(at: now)
        if suppressTyping { pendingImpacts.removeAll(); router.reset() }
    }
    func refreshPermissions() {
        let listeningAllowed = CGPreflightListenEventAccess()
        if listeningAllowed && !typingMonitor.isActive { typingMonitor.start() }
        if !listeningAllowed { typingMonitor.stop() }
        let listening = listeningAllowed && typingMonitor.isActive
        let trusted = ActionExecutor.trusted
        let helperState = HelperClient.status
        if typingPermission != listening { typingPermission = listening }
        if accessibilityPermission != trusted { accessibilityPermission = trusted }
        if helperStatus != helperState { helperStatus = helperState }
        if waitingForHelperApproval && HelperClient.service.status == .enabled {
            waitingForHelperApproval = false
            if input == .helper && !paused { restart() }
        }
    }
    func requestLaunchPermissions() {
        guard !launchPermissionsRequested else { return }
        launchPermissionsRequested = true
        if !ActionExecutor.trusted { ActionExecutor.requestPermission() }
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        refreshPermissions()
        prepareSensorAccess()
    }
    private func prepareSensorAccess() {
        guard launchPermissionsRequested, !helperSetupRequested, input == .sensor, !paused else { return }
        guard SensorRecoveryPolicy.shouldAttemptHelper(after: status) else { return }
        helperSetupRequested = true
        if HelperClient.service.status == .enabled { input = .helper; return }
        installHelper()
        guard HelperClient.service.status == .enabled || HelperClient.service.status == .requiresApproval else {
            acknowledgment = helperStatus; toast.show(helperStatus)
            return
        }
        waitingForHelperApproval = HelperClient.service.status == .requiresApproval
        input = .helper
        if waitingForHelperApproval {
            acknowledgment = "Approve the Tap That Mac sensor helper in Login Items to enable hardware double-taps"
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func reconnectSensor() {
        helperSetupRequested = false
        waitingForHelperApproval = false
        restart()
        prepareSensorAccess()
    }

    func openHelperApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
    private func observeLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        for (off, on, reason) in [(NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "sleep"),
                                  (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "session"),
                                  (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "display")] {
            observers.append(center.addObserver(forName: off, object: nil, queue: .main) { [weak self] _ in
                self?.setInactive(reason, active: true)
            })
            observers.append(center.addObserver(forName: on, object: nil, queue: .main) { [weak self] _ in
                self?.setInactive(reason, active: false)
            })
        }
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                if locked {
                    if self.awaitingLock {
                        self.awaitingLock = false
                        self.showLockReceiptOnReturn = true
                        self.acknowledgment = "macOS reported that the screen locked"
                        self.diagnostics.log("lock", self.acknowledgment)
                    }
                }
                self.setInactive("locked", active: locked)
            })
        }
    }
    private func setInactive(_ reason: String, active: Bool) {
        let wasInactive = !inactiveReasons.isEmpty
        let changed: Bool
        if active { changed = inactiveReasons.insert(reason).inserted }
        else { changed = inactiveReasons.remove(reason) != nil }
        guard changed else { return }
        diagnostics.log("lifecycle", "\(reason)=\(active); blocked=\(inactiveReasons.sorted().joined(separator: ","))")
        // Lock, display and session notifications overlap. Restart only when
        // crossing the active boundary, not once for every notification.
        if wasInactive != !inactiveReasons.isEmpty { restart() }
        if inactiveReasons.isEmpty, showLockReceiptOnReturn {
            showLockReceiptOnReturn = false
            acknowledgment = "Mac locked by Tap That Mac"
            toast.show(acknowledgment)
        }
    }

    func resetInteraction(resetDetector: Bool = true) {
        calibration.interrupt("Input or interaction settings changed. Retry this recording.", at: now)
        generation += 1; pendingImpacts.removeAll(); router.reset(); ring.dismiss()
        lastDoubleTime = nil
        // Changing an action or closing settings must not add another 1.5 s warmup.
        if resetDetector {
            diagnostics.recent = RecentMotionBuffer()
            detector.reset(); lastKeyTime = nil; lastSensorTime = nil
        }
    }
    func restart() {
        guard servicesEnabled else { return }
        configureTimer()
        resetInteraction(); diagnostics.finishCapture(); sensor.stop(); helper.stop(); sampleCount = 0; rate = 0
        if paused || !inactiveReasons.isEmpty { status = paused ? "Paused" : "Inactive session"; return }
        switch input {
        case .sensor: sensor.start(sampleRate: sampleRate)
        case .helper: helper.start()
        case .simulated: status = "Simulated. No hardware or system actions"; simulationStarted = now; simulatedUntil = now
        }
    }
    private func sensorStatus(_ value: String) {
        guard input != .simulated else { return }
        if status != value { status = value }
        if value != lastStatus {
            lastStatus = value; diagnostics.log("sensor", value)
            if value != "Streaming accelerometer" { resetInteraction() }
            DispatchQueue.main.async { [weak self] in self?.prepareSensorAccess() }
        }
    }
    private func ingest(_ samples: [AccelerationSample]) {
        // Published property reads perform Combine/key-path work. Read settings
        // once per delivery batch, never once per sensor report.
        guard !paused, inactiveReasons.isEmpty else { return }
        let recording = diagnostics.current != nil
        let receivedAt = now
        calibration.append(samples, receivedAt: receivedAt)
        let maximumGap = max(0.5, 3.0 / Double(sampleRate))
        var waitingForData = input != .simulated && status == "Waiting for fresh sensor data"
        for sample in samples {
            guard sample.time > receivedAt - max(0.5, timer?.timeInterval ?? 0.05) - 0.05, sample.time <= receivedAt + 0.01 else { continue }
            if let previous = lastSensorTime, sample.time <= previous { continue }
            if let previous = lastSensorTime, sample.time - previous > maximumGap { resetInteraction() }
            lastSensorTime = sample.time; lastSampleAt = receivedAt
            if waitingForData { sensorStatus("Streaming accelerometer"); waitingForData = false }
            sampleCount += 1
            diagnostics.recent.append(sample)
            if recording { diagnostics.append(sample) }
            if detector.ingest(sample, lastKeyTime: lastKeyTime, maximumSampleGap: maximumGap) {
                pendingImpacts.append(detector.acceptedOnset)
                diagnostics.log("impact", "\(detector.acceptedPath); onset=\(String(format: "%.3f", detector.acceptedOnset)); confirmed=\(String(format: "%.3f", sample.time))")
            }
            if detector.lastRejectionTime > lastLoggedRejection {
                // A slow swell is re-rejected on every sample above threshold;
                // log one line per distinct rejection, not one per sample.
                let reason = detector.lastRejectionReason
                if reason != lastLoggedReason || detector.lastRejectionTime - lastLoggedRejection > 0.25 {
                    diagnostics.log("pulse", "\(reason); t=\(String(format: "%.3f", detector.lastRejectionTime))")
                }
                lastLoggedRejection = detector.lastRejectionTime
                lastLoggedReason = reason
            }
            if collectGraph {
                motionTrace.append(time: sample.time, amplitude: detector.feature, threshold: detector.threshold,
                                   impulseAmplitude: detector.impulseFeature, impulseThreshold: detector.impulseThreshold)
            }
        }
    }
    private func knock(at time: Double) {
        knocks += 1; diagnostics.markKnock(); diagnostics.log("knock", "\(input.rawValue); t=\(String(format: "%.3f", time))")
        recentTaps.append(TapMark(time: time))
        if recentTaps.count > 24 { recentTaps.removeFirst(recentTaps.count - 24) }
        tapDetected.send()
        for event in router.knock(at: time) { route(event, at: time) }
    }
    private func route(_ event: GestureEvent, at time: Double) {
        guard !calibration.blocksActions else { return }
        if event == .double {
            recognizedPairs += 1
            for index in recentTaps.indices.suffix(2) { recentTaps[index].paired = true }
            doubleTapRecognized.send()
        }
        // Ignore additional vibration while a lock request is in flight.
        guard !ring.state.automaticAction, ring.state.committing == nil, !awaitingLock else { return }
        guard input != .sensor || sampleRate >= 50 else { return }
        switch event {
        case .ambiguous:
            diagnostics.log("gesture", "Ambiguous sequence cancelled")
            if ring.isOpen { ring.dismiss() }
        case .single:
            if ring.isOpen {
                ring.advance()
                diagnostics.log("ring", "Tap selected: \(ring.state.selected?.rawValue ?? "none")")
            }
        case .triple: return // Triple-tap is intentionally unavailable.
        case .double:
            lastDoubleTime = time
            diagnostics.log("gesture", "Double knock; \(preset.rawValue)")
            if ring.isOpen {
                // Preview selection remains display-only regardless of the mode.
                if let selected = ring.state.selected { ring.confirm(selected) }
            } else {
                if let reason = actionBlockReason { acknowledgment = reason; toast.show(reason); return }
                if let command = doubleTapAction.command {
                    if command == .lock || command == .playPause { ring.openAndPerform(command) }
                    else { execute(command) }
                } else { ring.open() }
            }
            diagnostics.log("ring", ring.isOpen ? "Opened" : "Closed or direct action")
            router.consumeOpening(at: time)
        }
    }
    private func execute(_ command: Command, preview: Bool = false) {
        let allowed = ActionAvailability.canExecute(preview: preview, blockReason: actionBlockReason)
        if preview {
            acknowledgment = "Preview only · \(command.rawValue) was not run"
            toast.show(acknowledgment)
            return
        }
        if let commandExecution {
            acknowledgment = commandExecution(command, allowed)
            return
        }
        if let intent = command.assistantIntent {
            if let reason = actionBlockReason { acknowledgment = reason; toast.show(reason); return }
            let token = generation
            AssistantActionExecutor().execute(intent, stillEnabled: { [weak self] in
                guard let self else { return false }
                return self.generation == token && self.canEnableActions
            }) { [weak self] result in
                guard let self else { return }
                self.acknowledgment = result
                self.diagnostics.log("assistant", result); self.toast.show(result)
            }
            return
        }

        if allowed && !ActionExecutor.trusted { ActionExecutor.requestPermission() }
        acknowledgment = actionBlockReason ?? ActionExecutor().execute(command, enabled: allowed)
        if command == .lock && allowed && ActionExecutor.trusted {
            awaitingLock = true; lockAttempt += 1
            let attempt = lockAttempt
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.awaitingLock, self.lockAttempt == attempt else { return }
                self.awaitingLock = false
                self.acknowledgment = "Lock not confirmed. Check Accessibility permission and Control-Command-Q."
                self.diagnostics.log("lock", self.acknowledgment)
                self.toast.show(self.acknowledgment)
            }
        }
        diagnostics.log("action", acknowledgment)
        toast.show(acknowledgment)
    }
    func inspectAssistantControls() { acknowledgment = AssistantActionExecutor().inspect() }
    func previewRing() {
        guard !ring.isOpen else { return }
        resetInteraction(resetDetector: false)
        ringPreviewActive = true
        ring.open(onChoose: { [weak self] command in
            self?.execute(command, preview: true)
        })
        guard ring.isOpen else { ringPreviewActive = false; return }
        router.consumeOpening(at: now)
    }
    func simulateKnock() {
        guard input == .simulated, !paused else { return }
        simulatedUntil = now + 0.018
    }
    func simulateDouble() {
        simulateKnock()
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self, self.generation == token else { return }; self.simulateKnock()
        }
    }
    private func tick() {
        let time = now
        let currentInput = input
        if currentInput == .sensor { sensor.poll() }
        collectGraph = setupIsVisible && graphIsAttached
        if time - lastPermissionRefresh >= (setupIsVisible ? 5 : 30) {
            lastPermissionRefresh = time
            refreshPermissions()
        }
        // Continuous disk telemetry is opt-in; ordinary use has no status writes.
        if (legacyCalibrationMode || CommandLine.arguments.contains("--runtime-diagnostics")), time - lastRuntimeWrite >= 5 {
            lastRuntimeWrite = time
            writeRuntimeStatus()
        }
        if input == .simulated && !paused && inactiveReasons.isEmpty {
            // Five samples per UI tick keep simulated filtering at 100 Hz.
            let samples = (0..<5).map { index in
                let t = time - 0.04 + Double(index) * 0.01
                return AccelerationSample(time: t, x: t < simulatedUntil && t > simulatedUntil - 0.018 ? 0.3 : 0, y: 0, z: 1)
            }
            ingest(samples)
            rate = Double(sampleCount) / max(0.01, time - simulationStarted)
        } else { rate = input == .helper ? helper.rate : sensor.rate }
        rejected = input == .helper ? helper.rejected : sensor.rejectedReports
        if rejected > lastCalibrationRejected { calibration.flag("Sensor reports were dropped or rejected.") }
        lastCalibrationRejected = rejected
        if calibration.stage == .recording && (!setupIsVisible || !typingPermission) {
            calibration.interrupt("Keep calibration visible and Input Monitoring enabled while recording.", at: time)
        }
        calibration.tick(at: time)
        let ready = pendingImpacts.filter { time - $0 >= 0.04 }
        pendingImpacts.removeAll { time - $0 >= 0.04 }
        for impact in ready {
            if !suppressTyping || !KnockPolicy.typingBlocks(at: impact, lastKeyTime: lastKeyTime) { knock(at: impact) }
        }
        // Expire using processed sensor time. Wall time can run ahead of a second
        // tap that is still awaiting pulse confirmation in the sensor batch.
        let pendingOnset = (pendingImpacts + [detector.pendingOnset].compactMap { $0 }).min()
        if let event = router.advance(wallTime: time, processedSensorTime: lastSensorTime ?? time,
                                      pendingOnset: pendingOnset) { route(event, at: time) }
        let tapPending = ring.isOpen && router.hasPendingTap
        if ring.state.tapPending != tapPending { ring.state.tapPending = tapPending }
        diagnostics.tick()
        // The graph draws independently at 20 Hz. The large settings form only
        // refreshes counters once a second, and never while hidden or occluded.
        if setupIsVisible {
            refreshGraph?()
            // Live motion envelope for reactive UI, throttled to ~10 Hz. The
            // level decays between sends and drops to zero when the trace has
            // no fresh points, so glow and indicator settle when motion stops.
            if time - lastLiveAmplitudeAt >= 0.1 {
                lastLiveAmplitudeAt = time
                let peak = motionTrace.points.last
                let stale = peak.map { time - $0.time > 0.3 } ?? true
                liveLevel = max(stale ? 0 : peak?.peak ?? 0, liveLevel * 0.7)
                liveAmplitude.send(liveLevel)
            }
            if time - lastPresentationTime >= 1 {
                lastPresentationTime = time
                objectWillChange.send()
            }
        }
        if status == "Streaming accelerometer", time - lastSampleAt > max(0.5, 3.0 / Double(sampleRate)) {
            resetInteraction(); status = "Waiting for fresh sensor data"
        }
    }
    private func writeRuntimeStatus() {
        // Local counters and state only; no raw motion or keyboard data.
        let state: [String: Any] = [
            "status": status, "input": input.rawValue, "samples": sampleCount,
            "warmingUp": detector.warmingUp, "knocks": knocks, "feature": detector.feature,
            "threshold": detector.threshold, "sensitivity": sensitivity, "inactiveReasons": inactiveReasons.sorted(),
            "requestedSampleRate": sampleRate, "effectiveSampleRate": input == .helper ? helper.rate : sensor.rate,
            "measuredSampleRate": rate, "setupVisible": setupIsVisible,
            "accessibility": accessibilityPermission, "helper": helperStatus, "operatingMode": operatingMode.rawValue,
            "events": diagnostics.events.suffix(12).map { "\($0.kind): \($0.detail)" }
        ]
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Tap That Mac")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("runtime-status.json"), options: .atomic)
        } catch { /* Diagnostics must not interrupt recognition. */ }
    }

    func installHelper() {
        guard let team = Bundle.main.object(forInfoDictionaryKey: "TapThatMacTeamIdentifier") as? String,
              SensorIPC.requirement(identifier: SensorIPC.appIdentifier, team: team) != nil else {
            helperStatus = "Build with an Apple signing identity and TEAM_ID before registering the helper"
            return
        }
        do { try HelperClient.service.register(); helperStatus = HelperClient.status }
        catch { helperStatus = "Registration failed: \(error.localizedDescription)" }
    }
    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        generation += 1
        awaitingLock = false
        lockAttempt += 1
        pendingImpacts.removeAll()
        if calibration.blocksActions { _ = calibration.cancel(at: now) }
        timer?.invalidate(); timer = nil; toast.dismiss(); ring.dismiss(); sensor.stop(); helper.stop(); diagnostics.finishCapture()
        typingMonitor.stop()
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers.removeAll()
        applicationObservers.forEach(NotificationCenter.default.removeObserver)
        applicationObservers.removeAll()
    }
}
