import Foundation

/// Owns the sensor on a dedicated run loop. The UI drains timestamped samples in
/// batches instead of waking AppKit for every HID report. No samples are decimated.
public final class BufferedSensorReader {
    public var onSamples: (([AccelerationSample]) -> Void)?
    public var onStatus: ((String) -> Void)?
    public private(set) var sampleCount = 0
    public private(set) var rate = 0.0
    public private(set) var rejectedReports = 0
    private let inbox = SensorInbox()
    private let worker: Worker
    private var generation = 0
    private var startedAt = 0.0

    public init() {
        worker = Worker()
    }
    public func start(sampleRate: Int = 800) {
        generation += 1
        let token = generation
        inbox.reset(generation: token)
        sampleCount = 0; rejectedReports = 0; rate = 0
        startedAt = ProcessInfo.processInfo.systemUptime
        worker.perform { reader in
            reader.stop()
            reader.setReportInterval(SamplingRate.intervalMicroseconds(for: sampleRate))
            reader.onSample = { [inbox = self.inbox] in inbox.append($0, generation: token) }
            reader.onRejected = { [inbox = self.inbox] in inbox.reject(generation: token) }
            reader.onStatus = { [inbox = self.inbox] in inbox.status($0, generation: token) }
            reader.start()
        }
    }
    public func poll() {
        let batch = inbox.take()
        sampleCount += batch.samples.count
        rejectedReports += batch.dropped
        rate = Double(sampleCount) / max(0.001, ProcessInfo.processInfo.systemUptime - startedAt)
        for status in batch.statuses { onStatus?(status) }
        if !batch.samples.isEmpty { onSamples?(batch.samples) }
    }
    public func stop() {
        generation += 1; inbox.reset(generation: generation)
        let finished = DispatchSemaphore(value: 0)
        worker.perform { $0.stop(); finished.signal() }
        finished.wait() // Restore driver properties before restart or app termination.
    }

    private final class Worker {
        private let loop: CFRunLoop
        private let reader: SensorReader
        private let thread: Thread
        init() {
            // This handshake publishes immutable ownership references before use.
            let ready = DispatchSemaphore(value: 0)
            var workerLoop: CFRunLoop!
            var workerReader: SensorReader!
            thread = Thread {
                let loop = CFRunLoopGetCurrent()!
                let reader = SensorReader(runLoop: loop)
                // A dormant source keeps the run loop alive while recognition is paused.
                var context = CFRunLoopSourceContext()
                let keepAlive = CFRunLoopSourceCreate(nil, 0, &context)!
                CFRunLoopAddSource(loop, keepAlive, .commonModes)
                workerLoop = loop; workerReader = reader
                ready.signal()
                CFRunLoopRun()
                reader.stop()
                CFRunLoopRemoveSource(loop, keepAlive, .commonModes)
            }
            thread.name = "TapThatX sensor"
            thread.qualityOfService = .utility
            thread.start(); ready.wait()
            loop = workerLoop; reader = workerReader
        }
        func perform(_ action: @escaping (SensorReader) -> Void) {
            let reader = reader
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { action(reader) }
            CFRunLoopWakeUp(loop)
        }
        deinit {
            let loop = loop
            perform { reader in reader.stop(); CFRunLoopStop(loop) }
        }
    }
}

/// A generation rejects callbacks from a previous connection after restart.
final class SensorInbox {
    struct Batch {
        let samples: [AccelerationSample]
        let statuses: [String]
        let dropped: Int
    }
    private let lock = NSLock()
    private var generation = 0
    private var samples: [AccelerationSample] = []
    private var statuses: [String] = []
    private var dropped = 0
    func reset(generation: Int) {
        lock.lock(); defer { lock.unlock() }
        self.generation = generation
        samples.removeAll(keepingCapacity: true); statuses.removeAll(); dropped = 0
    }
    func append(_ sample: AccelerationSample, generation: Int) {
        lock.lock(); defer { lock.unlock() }
        guard generation == self.generation else { return }
        // Retain the newest contiguous batch after a long blocked consumer.
        if samples.count >= 512 { dropped += samples.count; samples.removeAll(keepingCapacity: true) }
        samples.append(sample)
    }
    func reject(generation: Int) {
        lock.lock(); defer { lock.unlock() }
        if generation == self.generation { dropped += 1 }
    }
    func status(_ value: String, generation: Int) {
        lock.lock(); defer { lock.unlock() }
        guard generation == self.generation else { return }
        if statuses.count == 16 { statuses.removeFirst() }
        statuses.append(value)
    }
    func take() -> Batch {
        lock.lock(); defer { lock.unlock() }
        let batch = Batch(samples: samples, statuses: statuses, dropped: dropped)
        samples = []; statuses = []; dropped = 0
        return batch
    }
}
