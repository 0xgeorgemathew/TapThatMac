import Foundation
import TapCore

final class SensorSession: NSObject, SensorService {
    private let reader = SensorReader()
    private var samples: [AccelerationSample] = []
    private var droppedSamples = 0
    private var lease: Timer?
    private var lastRead = 0.0

    override init() {
        super.init()
        reader.onSample = { [weak self] sample in
            guard let self else { return }
            if self.samples.count >= 2048 { self.samples.removeFirst(1024); self.droppedSamples += 1024 }
            self.samples.append(sample)
        }
    }
    func start(reply: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            self.samples.removeAll(); self.droppedSamples = 0; self.reader.start()
            self.lastRead = ProcessInfo.processInfo.systemUptime
            self.lease?.invalidate()
            self.lease = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, ProcessInfo.processInfo.systemUptime - self.lastRead > 3 else { return }
                self.shutdown()
            }
            reply(self.reader.status)
        }
    }
    func read(reply: @escaping (Data, String, Int, Double) -> Void) {
        DispatchQueue.main.async {
            self.lastRead = ProcessInfo.processInfo.systemUptime
            let batch = self.samples; self.samples.removeAll(keepingCapacity: true)
            do { reply(try JSONEncoder().encode(batch), self.reader.status, self.reader.rejectedReports + self.droppedSamples, self.reader.rate) }
            catch { reply(Data(), "Sensor encoding failed", self.reader.rejectedReports + self.droppedSamples, self.reader.rate) }
        }
    }
    func stop(reply: @escaping () -> Void) { DispatchQueue.main.async { self.shutdown(); reply() } }
    func shutdown() {
        lease?.invalidate(); lease = nil; reader.stop(); samples.removeAll()
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private var activeConnection: NSXPCConnection?
    private let requirement: String
    private let lock = NSLock()
    init(requirement: String) { self.requirement = requirement }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard activeConnection == nil else { return false }
        connection.setCodeSigningRequirement(requirement)
        let session = SensorSession()
        connection.exportedInterface = NSXPCInterface(with: SensorService.self)
        connection.exportedObject = session
        connection.invalidationHandler = { [weak self, weak connection] in
            DispatchQueue.main.async {
                session.shutdown()
                guard let self else { return }
                self.lock.lock()
                if self.activeConnection === connection { self.activeConnection = nil }
                self.lock.unlock()
            }
        }
        connection.interruptionHandler = { [weak connection] in connection?.invalidate() }
        activeConnection = connection
        connection.resume()
        return true
    }
}

// launchd supplies a bundle-relative executable; derive the containing app's signed metadata.
let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let appURL = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
guard let bundle = Bundle(url: appURL),
      let team = bundle.object(forInfoDictionaryKey: "TapThatXTeamIdentifier") as? String,
      let requirement = SensorIPC.requirement(identifier: SensorIPC.appIdentifier, team: team) else {
    fputs("Missing signed app team identifier; refusing sensor service.\n", stderr)
    exit(1)
}
let delegate = ListenerDelegate(requirement: requirement)
let listener = NSXPCListener(machServiceName: SensorIPC.service)
listener.delegate = delegate
listener.setConnectionCodeSigningRequirement(requirement)
listener.resume()
RunLoop.main.run()
