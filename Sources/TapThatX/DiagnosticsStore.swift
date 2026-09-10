import Foundation
import Darwin
import TapCore

struct DiagnosticEvent: Codable, Identifiable {
    let id: UUID
    let time: Double
    let kind: String
    let detail: String
}
struct Capture: Codable {
    let label: String
    let purpose: String
    let simulated: Bool
    let started: Double
    var duration: Double
    var samples: [AccelerationSample]
    var knocks: Int
    var expectedDoubleKnocks: Int?
    var keyTimes: [Double]?
}
struct DiagnosticExport: Codable {
    let version: String
    let model: String
    let os: String
    let preset: Preset
    let settings: DetectorSettings
    let events: [DiagnosticEvent]
    let captures: [Capture]
}

final class DiagnosticsStore {
    var recent = RecentMotionBuffer()
    private(set) var events: [DiagnosticEvent] = []
    private(set) var captures: [Capture] = []
    private(set) var current: Capture?
    let model: String = {
        var size = 0; sysctlbyname("hw.model", nil, &size, nil, 0)
        var value = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("hw.model", &value, &size, nil, 0)
        return String(cString: value)
    }()
    var captureRemaining: Int { current.map { max(0, Int(ceil(15 - (ProcessInfo.processInfo.systemUptime - $0.started)))) } ?? 0 }
    func log(_ kind: String, _ detail: String) {
        if events.count >= 2000 { events.removeFirst(500) }
        events.append(DiagnosticEvent(id: UUID(), time: ProcessInfo.processInfo.systemUptime, kind: kind, detail: detail))
    }
    func startCapture(label: String, purpose: String, simulated: Bool, expectedDoubleKnocks: Int) {
        finishCapture()
        current = Capture(label: label, purpose: purpose, simulated: simulated, started: ProcessInfo.processInfo.systemUptime, duration: 0, samples: [], knocks: 0, expectedDoubleKnocks: expectedDoubleKnocks, keyTimes: [])
        log("capture", "\(purpose): \(label), simulated=\(simulated)")
    }
    func append(_ sample: AccelerationSample) {
        guard current != nil else { return }
        if captureRemaining == 0 || current!.samples.count >= 20000 { finishCapture(); return }
        current?.samples.append(sample)
    }
    func markKey(at time: Double) {
        guard current != nil, (current?.keyTimes?.count ?? 0) < 4000 else { return }
        current?.keyTimes?.append(time)
    }
    func markKnock() { if current != nil { current?.knocks += 1 } }
    func tick() { if current != nil, captureRemaining == 0 { finishCapture() } }
    func finishCapture() {
        guard var capture = current else { return }
        capture.duration = min(15, ProcessInfo.processInfo.systemUptime - capture.started)
        current = nil
        if captures.count >= 12 { captures.removeFirst() }
        captures.append(capture)
    }
    func exportRecent(preset: Preset, settings: DetectorSettings, simulated: Bool, to url: URL) throws {
        let snapshot = recent.snapshot()
        guard let first = snapshot.samples.first, let last = snapshot.samples.last else {
            throw NSError(domain: "TapThatX", code: 1, userInfo: [NSLocalizedDescriptionKey: "No recent motion to save yet."])
        }
        let capture = Capture(label: "Unlabelled recent activity", purpose: "Diagnostic", simulated: simulated,
            started: first.time, duration: last.time - first.time, samples: snapshot.samples,
            knocks: 0, expectedDoubleKnocks: nil, keyTimes: snapshot.keyTimes)
        let payload = DiagnosticExport(version: "0.1.0", model: model,
            os: ProcessInfo.processInfo.operatingSystemVersionString, preset: preset,
            settings: settings, events: events.filter { $0.time >= first.time }, captures: [capture])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(payload).write(to: url, options: .atomic)
    }
    func clear() { current = nil; captures.removeAll(); events.removeAll() }
    func export(preset: Preset, settings: DetectorSettings, to url: URL) throws {
        finishCapture()
        let payload = DiagnosticExport(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0", model: model, os: ProcessInfo.processInfo.operatingSystemVersionString, preset: preset, settings: settings, events: events, captures: captures)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(payload).write(to: url, options: [.atomic])
    }
}
