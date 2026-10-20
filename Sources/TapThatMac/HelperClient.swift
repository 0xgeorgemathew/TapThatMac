import Foundation
import ServiceManagement
import TapCore

final class HelperClient {
    var onSamples: (([AccelerationSample]) -> Void)?
    var onStatus: ((String) -> Void)?
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var generation = 0
    private var retriesRemaining = 0
    private var pendingRead = false
    private var pendingSince = 0.0
    private(set) var rate = 0.0
    private(set) var rejected = 0
    static var service: SMAppService { .daemon(plistName: "com.tapthatmac.sensor.plist") }
    static var status: String {
        switch service.status {
        case .enabled: return "Approved"
        case .requiresApproval: return "Awaiting approval in Login Items"
        case .notRegistered: return "Not installed"
        case .notFound: return "Helper missing from app bundle"
        @unknown default: return "Unknown helper state"
        }
    }
    func start() {
        stop()
        retriesRemaining = 3
        connect()
    }
    private func connect() {
        guard let team = Bundle.main.object(forInfoDictionaryKey: "TapThatMacTeamIdentifier") as? String,
              let requirement = SensorIPC.requirement(identifier: SensorIPC.helperIdentifier, team: team) else {
            onStatus?("Helper unavailable in unsigned builds; signed packaging is required"); return
        }
        guard Self.service.status == .enabled else { onStatus?(Self.status); return }
        let connection = NSXPCConnection(machServiceName: SensorIPC.service, options: .privileged)
        connection.setCodeSigningRequirement(requirement)
        connection.remoteObjectInterface = NSXPCInterface(with: SensorService.self)
        connection.interruptionHandler = { [weak self, weak connection] in
            DispatchQueue.main.async { guard let connection, self?.connection === connection else { return }; self?.fail("Helper interrupted. Reconnect to retry") }
        }
        connection.invalidationHandler = { [weak self, weak connection] in
            DispatchQueue.main.async { guard let connection, self?.connection === connection else { return }; self?.fail("Helper disconnected or approval revoked") }
        }
        self.connection = connection; connection.resume()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak connection] in
            guard let self, let connection, self.connection === connection, self.timer == nil else { return }
            self.fail("Helper start timed out. Reconnect to retry")
        }
        proxy()?.start { [weak self, weak connection] status in
            DispatchQueue.main.async {
                guard let self, let connection, self.connection === connection else { return }
                self.onStatus?(status)
                let pollTimer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.read() }
                self.timer = pollTimer
                RunLoop.main.add(pollTimer, forMode: .common)
            }
        }
    }
    private func proxy() -> SensorService? {
        let current = connection
        return connection?.remoteObjectProxyWithErrorHandler { [weak self, weak current] error in
            let message = error.localizedDescription
            DispatchQueue.main.async { guard let current, self?.connection === current else { return }; self?.fail("Helper: \(message)") }
        } as? SensorService
    }
    private func read() {
        if pendingRead {
            if ProcessInfo.processInfo.systemUptime - pendingSince > 3 { fail("Helper timed out. Reconnect to retry") }
            return
        }
        pendingRead = true; pendingSince = ProcessInfo.processInfo.systemUptime
        let current = connection
        proxy()?.read { [weak self, weak current] data, status, rejected, rate in
            DispatchQueue.main.async {
                guard let self, let current, self.connection === current else { return }
                self.pendingRead = false; self.rate = rate; self.rejected = rejected; self.onStatus?(status)
                guard data.count <= 1_000_000, let samples = try? JSONDecoder().decode([AccelerationSample].self, from: data), samples.count <= 2048 else {
                    self.fail("Malformed sensor helper response"); return
                }
                if !samples.isEmpty { self.retriesRemaining = 3 }
                self.onSamples?(samples)
            }
        }
    }
    private func fail(_ message: String) {
        let remaining = retriesRemaining
        stop()
        guard remaining > 0, Self.service.status == .enabled else { onStatus?(message); return }
        retriesRemaining = remaining - 1
        onStatus?("Reconnecting sensor helper")
        let token = generation
        // The daemon accepts one client; let its previous connection finish
        // invalidating before retrying a reconnect after lock or wake.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.generation == token else { return }
            self.connect()
        }
    }
    func stop() {
        generation += 1; retriesRemaining = 0
        timer?.invalidate(); timer = nil; pendingRead = false
        let previous = connection; connection = nil
        previous?.invalidationHandler = nil; previous?.interruptionHandler = nil
        // The helper also expires its sampling lease if this reply is lost.
        if let proxy = previous?.remoteObjectProxy as? SensorService { proxy.stop { previous?.invalidate() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { previous?.invalidate() }
    }
}
