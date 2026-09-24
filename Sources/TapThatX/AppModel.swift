import AppKit
import SwiftUI
import ServiceManagement
import TapCore
import Combine

enum InputMode: String, CaseIterable { case sensor = "Direct sensor", helper = "Sensor helper", simulated = "Simulated input" }

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
    @Published var input: InputMode = .sensor { didSet { restart() } }
    @Published var sampleRate: Int = {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--sample-rate"),
              args.indices.contains(index + 1), let requested = Int(args[index + 1]),
              SamplingRate.options.contains(requested) else {
            let saved = UserDefaults.standard.integer(forKey: "sampleRate")
            return SamplingRate.options.contains(saved) ? saved : 800
        }
        return requested
    }() { didSet { UserDefaults.standard.set(sampleRate, forKey: "sampleRate"); restart(); logSettings() } }
    @Published var paused = false { didSet { restart() } }
    @Published var sensitivity = 2.0 {
        didSet {
            UserDefaults.standard.set(sensitivity, forKey: "knockSensitivity")
            UserDefaults.standard.removeObject(forKey: "calibrationSessionID")
            detector.settings.sensitivity = sensitivity
            resetInteraction(); logSettings()
        }
    }
    @Published var suppressTyping = true { didSet { detector.settings.suppressTyping = suppressTyping; resetInteraction(); logSettings() } }
    @Published var actionsEnabled = !CommandLine.arguments.contains("--calibrate") { didSet { resetInteraction(resetDetector: false); logSettings() } }
    @Published var status = "Starting"
    @Published var helperStatus = HelperClient.status
    @Published var acknowledgment = "Choose your double-tap action in Actions"
    private(set) var sampleCount = 0
    private(set) var rate = 0.0
    private(set) var rejected = 0
    private(set) var feature = 0.0
    private(set) var threshold = 0.0
    private(set) var knocks = 0
    private(set) var recognizedPairs = 0
    private var lastLoggedRejection = -Double.infinity
    private(set) var lastDoubleTime: Double?
    private(set) var captureRemaining = 0
    private(set) var captures: [Capture] = []
    private(set) var recentEvents: [DiagnosticEvent] = []
    @Published var typingPermission = false
    @Published var accessibilityPermission = false
    private(set) var warmingUp = true
    @Published var calibrationMode = CommandLine.arguments.contains("--calibrate")
    let diagnostics = DiagnosticsStore()
    let calibration: CalibrationController
    private var calibrationObservation: AnyCancellable?
    private var lastCalibrationRejected = 0
    let ring = RadialPanelController()
    private let sensor = BufferedSensorReader()
    private let helper = HelperClient()
    private let toast = AcknowledgmentController()
    private var detector = KnockDetector()
    private var router = GestureRouter()
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
    var refreshGraph: (() -> Void)?
    var graphIsAttached = false
    private(set) var motionTrace = MotionTrace()
    private var wasTuning = false
    private var collectGraph = false
    private var lastRuntimeWrite = 0.0
    var isTuning: Bool { setupWindow?.isVisible == true }
    var setupIsVisible: Bool { isTuning && setupWindow?.occlusionState.contains(.visible) == true }
    var amplitudeFloor: Double { detector.settings.amplitudeFloor }
    var liveThreshold: Double { detector.threshold }
    var liveWarmingUp: Bool { detector.warmingUp }
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
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    var actionBlockReason: String? {
        ActionAvailability.blockReason(calibration: calibrationMode, settingsOpen: isTuning,
            simulated: input == .simulated, paused: paused, inactive: !inactiveReasons.isEmpty,
            recording: diagnostics.current != nil || calibration.blocksActions, enabled: actionsEnabled,
            monitoringOnly: input == .sensor && sampleRate < 50)
    }
    var canEnableActions: Bool { actionBlockReason == nil }
    var actionStatus: String { actionBlockReason ?? "Ready when settings close" }
    func enableAndCloseSettings() {
        guard diagnostics.current == nil, !calibration.blocksActions else { return }
        calibrationMode = false; actionsEnabled = true
        setupWindow?.close()
        resetInteraction(resetDetector: false)
    }

    var calibrationUnavailableReason: String? {
        if input == .simulated { return "Choose a real sensor in Input Source." }
        if paused || !inactiveReasons.isEmpty { return "Resume the sensor in an active session." }
        if !setupIsVisible { return "Keep the calibration window visible." }
        if status != "Streaming accelerometer" { return "Connect the sensor before recording." }
        if input == .sensor && sampleRate != 800 { return "Choose 800 Hz in Tap Tuning before calibration." }
        if rate < 700 || rate > 900 { return "Waiting for a steady sensor stream near 800 Hz." }
        if !typingPermission { return "Enable Input Monitoring so overlapping typing can be identified." }
        if diagnostics.current != nil { return "Finish the diagnostic recording first." }
        if calibration.blocksActions, let context = calibration.session?.context,
           context.input != input.rawValue || context.requestedRate != (input == .helper ? 800 : sampleRate)
            || context.initialSettings.sensitivity != sensitivity {
            return "Input or sensitivity changed. Cancel and start a fresh calibration session."
        }
        return nil
    }
    var canStartCalibration: Bool { calibrationUnavailableReason == nil }

    func beginCalibration(surface: String, placement: String) {
        guard canStartCalibration else { return }
        resetInteraction()
        calibration.begin(context: CalibrationContext(surface: surface, placement: placement,
            device: diagnostics.model, os: ProcessInfo.processInfo.operatingSystemVersionString,
            input: input.rawValue, requestedRate: input == .helper ? 800 : sampleRate,
            initialSettings: detector.settings))
    }
    func recordCalibrationTrial() {
        guard canStartCalibration else { return }
        lastCalibrationRejected = rejected
        calibration.record(at: now)
    }
    func cancelCalibration() {
        if calibration.cancel(at: now) { resetInteraction() }
    }
    func applyCalibration() {
        guard calibration.stage == .complete, calibration.session?.verificationPassed == true,
              let floor = calibration.floor, canStartCalibration,
              calibration.session?.context.input == input.rawValue else { return }
        setAmplitudeFloor(floor)
        UserDefaults.standard.set(calibration.session?.id.uuidString, forKey: "calibrationSessionID")
        calibration.markApplied()
        acknowledgment = "Personal sensitivity applied. Recalibrate when the surface or placement changes."
        diagnostics.log("calibration", "Applied session \(calibration.session!.id); floor=\(floor)")
    }

    init(startServices: Bool = true, calibration: CalibrationController = CalibrationController()) {
        self.calibration = calibration
        calibrationObservation = calibration.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        let savedSensitivity = UserDefaults.standard.object(forKey: "knockSensitivity") as? Double ?? 2.0
        sensitivity = savedSensitivity.isFinite ? min(7, max(0.5, savedSensitivity)) : 2.0
        detector.settings.sensitivity = sensitivity
        guard startServices else { return }
        sensor.onSamples = { [weak self] in self?.ingest($0) }
        sensor.onStatus = { [weak self] in self?.sensorStatus($0) }
        helper.onSamples = { [weak self] in self?.ingest($0) }
        helper.onStatus = { [weak self] in self?.sensorStatus($0) }
        ring.onChoose = { [weak self] in self?.execute($0) }
        ring.onDismiss = { [weak self] in
            self?.router.reset()
            self?.diagnostics.log("ring", "Dismissed; ready for a new pair")
        }
        observeLifecycle()
        applicationObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { [weak self] _ in
            self?.requestLaunchPermissions()
        })
        applicationObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshPermissions()
        })
        if NSApp?.isRunning == true { DispatchQueue.main.async { [weak self] in self?.requestLaunchPermissions() } }
        typingMonitor.onKey = { [weak self] in self?.noteKey() }
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
        diagnostics.log("settings", "preset=\(preset.rawValue); action=\(doubleTapAction.rawValue); input=\(input.rawValue); sampleRate=\(sampleRate); sensitivity=\(sensitivity); typing=\(suppressTyping); enabled=\(actionsEnabled)")
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
        guard status.contains("access denied") || status.contains("reports stopped") else { return }
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
            acknowledgment = "Approve the TapThatX sensor helper in Login Items to enable hardware double-taps"
            SMAppService.openSystemSettingsLoginItems()
        }
    }
    func requestTypingPermission() { _ = CGRequestListenEventAccess(); refreshPermissions() }
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
            acknowledgment = "Mac locked by TapThatX"
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
            detector.reset(); lastKeyTime = nil; lastSensorTime = nil; warmingUp = true
        }
    }
    func restart() {
        configureTimer()
        resetInteraction(); diagnostics.finishCapture(); sensor.stop(); helper.stop(); sampleCount = 0; rate = 0
        if paused || !inactiveReasons.isEmpty { status = paused ? "Paused" : "Inactive session"; return }
        switch input {
        case .sensor: sensor.start(sampleRate: sampleRate)
        case .helper: helper.start()
        case .simulated: status = "Simulated — no hardware or system actions"; simulationStarted = now; simulatedUntil = now
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
                lastLoggedRejection = detector.lastRejectionTime
                diagnostics.log("pulse", "\(detector.lastRejectionReason); t=\(String(format: "%.3f", lastLoggedRejection))")
            }
            if collectGraph {
                motionTrace.append(time: sample.time, amplitude: detector.feature, threshold: detector.threshold)
            }
        }
    }
    private func knock(at time: Double) {
        knocks += 1; diagnostics.markKnock(); diagnostics.log("knock", "\(input.rawValue); t=\(String(format: "%.3f", time))")
        for event in router.knock(at: time) { route(event, at: time) }
    }
    private func route(_ event: GestureEvent, at time: Double) {
        guard !calibration.blocksActions else { return }
        if event == .double { recognizedPairs += 1 }
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
                // Preview uses the same gestures. execute(_:) retains all action
                // availability checks, so settings and simulation remain dry runs.
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
    private func execute(_ command: Command) {
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

        let allowed = actionsEnabled && canEnableActions && diagnostics.current == nil
        if allowed && !ActionExecutor.trusted { ActionExecutor.requestPermission() }
        acknowledgment = actionBlockReason ?? ActionExecutor().execute(command, enabled: allowed)
        if command == .lock && allowed && ActionExecutor.trusted {
            awaitingLock = true; lockAttempt += 1
            let attempt = lockAttempt
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.awaitingLock, self.lockAttempt == attempt else { return }
                self.awaitingLock = false
                self.acknowledgment = "Lock not confirmed. Check Accessibility permission and Control–Command–Q."
                self.diagnostics.log("lock", self.acknowledgment)
                self.toast.show(self.acknowledgment)
            }
        }
        diagnostics.log("action", acknowledgment)
        toast.show(acknowledgment)
    }
    func inspectAssistantControls() { acknowledgment = AssistantActionExecutor().inspect() }
    func previewRing() { guard !calibration.blocksActions else { return }; resetInteraction(resetDetector: false); ring.open(); router.consumeOpening(at: now) }
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
        if isTuning != wasTuning {
            wasTuning = isTuning
            configureTimer()
            resetInteraction(resetDetector: false)
            motionTrace = MotionTrace()
        }
        if time - lastPermissionRefresh >= (setupIsVisible ? 5 : 30) {
            lastPermissionRefresh = time
            refreshPermissions()
        }
        // Continuous disk telemetry is opt-in; ordinary use has no status writes.
        if (calibrationMode || CommandLine.arguments.contains("--runtime-diagnostics")), time - lastRuntimeWrite >= 5 {
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
            if !suppressTyping || lastKeyTime.map({ abs(impact - $0) > 0.18 }) != false { knock(at: impact) }
        }
        // Expire using processed sensor time, including the 35 ms pulse-confirmation
        // window. Wall time can run ahead of a second tap still in the sensor batch.
        if let event = router.advance(wallTime: time, processedSensorTime: lastSensorTime ?? time) { route(event, at: time) }
        diagnostics.tick()
        // The graph draws independently at 20 Hz. The large settings form only
        // refreshes counters once a second, and never while hidden or occluded.
        if setupIsVisible {
            refreshGraph?()
            if time - lastPresentationTime >= 1 {
                lastPresentationTime = time
                objectWillChange.send()
                captureRemaining = diagnostics.captureRemaining; captures = diagnostics.captures
                recentEvents = Array(diagnostics.events.suffix(8).reversed())
                feature = detector.feature; threshold = detector.threshold; warmingUp = detector.warmingUp
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
            "requestedSampleRate": sampleRate, "measuredSampleRate": rate, "tuning": isTuning, "setupVisible": setupIsVisible,
            "accessibility": accessibilityPermission, "helper": helperStatus, "actionsEnabled": actionsEnabled,
            "events": diagnostics.events.suffix(12).map { "\($0.kind): \($0.detail)" }
        ]
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("TapThatX")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("runtime-status.json"), options: .atomic)
        } catch { /* Diagnostics must not interrupt recognition. */ }
    }

    func startCapture(label: String, purpose: String, expectedDoubleKnocks: Int) {
        guard !calibration.blocksActions else { return }
        resetInteraction()
        diagnostics.startCapture(label: label, purpose: purpose, simulated: input == .simulated, expectedDoubleKnocks: expectedDoubleKnocks)
    }
    func saveRecentActivity() {
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("TapThatX")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = "recent-activity-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).json"
            try diagnostics.exportRecent(preset: preset, settings: detector.settings, simulated: input == .simulated, to: directory.appendingPathComponent(name))
            acknowledgment = "Saved last 15 seconds locally: \(name)"
        } catch { acknowledgment = "Recent activity save failed: \(error.localizedDescription)" }
        toast.show(acknowledgment)
    }
    func saveDiagnosticRecordings() {
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("TapThatX")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("diagnostic-recordings-\(UUID().uuidString).json")
            try diagnostics.export(preset: preset, settings: detector.settings, to: url)
            acknowledgment = "Saved \(url.lastPathComponent) in Library/Application Support/TapThatX"
        } catch { acknowledgment = "Diagnostic save failed: \(error.localizedDescription)" }
    }

    func mark(_ message: String) { diagnostics.log("feedback", message); acknowledgment = "Feedback marker saved" }
    func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "TapThatX-diagnostics.json"
        if panel.runModal() == .OK, let url = panel.url {
            do { try diagnostics.export(preset: preset, settings: detector.settings, to: url); acknowledgment = "Diagnostics exported" }
            catch { acknowledgment = "Export failed: \(error.localizedDescription)" }
        }
    }
    func installHelper() {
        guard let team = Bundle.main.object(forInfoDictionaryKey: "TapThatXTeamIdentifier") as? String,
              SensorIPC.requirement(identifier: SensorIPC.appIdentifier, team: team) != nil else {
            helperStatus = "Build with an Apple signing identity and TEAM_ID before registering the helper"
            return
        }
        do { try HelperClient.service.register(); helperStatus = HelperClient.status }
        catch { helperStatus = "Registration failed: \(error.localizedDescription)" }
    }
    func removeHelper() {
        waitingForHelperApproval = false; helperSetupRequested = true
        helper.stop(); resetInteraction()
        HelperClient.service.unregister { [weak self] error in
            DispatchQueue.main.async { self?.helperStatus = error.map { "Removal failed: \($0.localizedDescription)" } ?? HelperClient.status }
        }
    }
    func shutdown() {
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
