import Foundation
import IOKit
import IOKit.hid

// Lifecycle calls and callbacks belong to the run loop selected at initialization.
public final class SensorReader {
    public var onSample: ((AccelerationSample) -> Void)?
    public var onRejected: (() -> Void)?
    public var onStatus: ((String) -> Void)?
    public private(set) var status = "Stopped"
    public private(set) var sampleCount = 0
    public private(set) var rejectedReports = 0
    public private(set) var rate = 0.0
    private var device: IOHIDDevice?
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
    private var startedAt = 0.0
    private var lastSample = 0.0
    private var watchdog: Timer?
    private var driver: io_registry_entry_t = 0
    private var originalProperties: [String: CFTypeRef] = [:]
    private var timebase: mach_timebase_info_data_t = {
        var value = mach_timebase_info_data_t(); mach_timebase_info(&value); return value
    }()
    private let runLoop: CFRunLoop
    private var reportInterval: Int
    public init(runLoop: CFRunLoop = CFRunLoopGetMain(), reportInterval: Int = 1250) {
        self.runLoop = runLoop
        self.reportInterval = max(1000, reportInterval)
    }
    deinit { stop(); buffer.deallocate() }

    public func setReportInterval(_ interval: Int) {
        reportInterval = max(1000, interval)
    }
    private func setStatus(_ value: String) { status = value; onStatus?(value) }
    public func start() {
        stop(); sampleCount = 0; rejectedReports = 0; rate = 0
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDevice"), &iterator)
        guard result == KERN_SUCCESS else { setStatus("Enumeration failed: \(result)"); return }
        defer { IOObjectRelease(iterator) }
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            func property(_ name: String) -> Int? {
                (IORegistryEntryCreateCFProperty(service, name as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
            }
            guard property("PrimaryUsagePage") == 0xFF00, property("PrimaryUsage") == 3 else { continue }
            guard property("MaxInputReportSize") == 22 else { setStatus("Unsupported accelerometer report format"); return }
            guard let hid = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { setStatus("Cannot create HID device"); return }
            let opened = IOHIDDeviceOpen(hid, IOOptionBits(kIOHIDOptionsTypeNone))
            guard opened == kIOReturnSuccess else {
                setStatus("Sensor access denied or unavailable (IOKit \(opened)); try the approved sensor helper.")
                return
            }
            device = hid
            // The SPU HID driver is a descendant of this device, not its parent.
            // Restrict configuration to this accelerometer's own subtree.
            var children: io_iterator_t = 0
            if IORegistryEntryCreateIterator(service, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &children) == KERN_SUCCESS {
                defer { IOObjectRelease(children) }
                while case let child = IOIteratorNext(children), child != 0 {
                    defer { IOObjectRelease(child) }
                    guard IOObjectConformsTo(child, "AppleSPUHIDDriver") != 0,
                          let old = IORegistryEntryCreateCFProperty(child, "ReportInterval" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { continue }
                    let result = IORegistryEntrySetCFProperty(child, "ReportInterval" as CFString, NSNumber(value: reportInterval))
                    if result == KERN_SUCCESS {
                        IOObjectRetain(child); driver = child
                        originalProperties["ReportInterval"] = old
                    } else {
                        onStatus?("Sensor rate request failed (IOKit \(result)); check measured rate")
                    }
                    break
                }
            }
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputReportWithTimeStampCallback(hid, buffer, 4096, { context, result, _, type, reportID, report, length, timestamp in
                guard let context else { return }
                let reader = Unmanaged<SensorReader>.fromOpaque(context).takeUnretainedValue()
                guard result == kIOReturnSuccess, type == kIOHIDReportTypeInput, length == 22 else {
                    reader.rejectedReports += 1; reader.onRejected?(); return
                }
                let seconds = Double(timestamp) * Double(reader.timebase.numer) / Double(reader.timebase.denom) / 1_000_000_000
                guard let sample = ReportDecoder.decode(UnsafeBufferPointer(start: report, count: length), reportID: reportID, time: seconds) else {
                    reader.rejectedReports += 1; reader.onRejected?(); return
                }
                reader.sampleCount += 1
                reader.lastSample = ProcessInfo.processInfo.systemUptime
                reader.rate = Double(reader.sampleCount) / max(0.001, reader.lastSample - reader.startedAt)
                if reader.sampleCount == 1 { reader.setStatus("Streaming accelerometer") }
                reader.onSample?(sample)
            }, context)
            IOHIDDeviceRegisterRemovalCallback(hid, { context, _, _ in
                guard let context else { return }
                let reader = Unmanaged<SensorReader>.fromOpaque(context).takeUnretainedValue()
                CFRunLoopPerformBlock(reader.runLoop, CFRunLoopMode.commonModes.rawValue) {
                    reader.stop(); reader.setStatus("Sensor disconnected — reconnect to retry")
                }
                CFRunLoopWakeUp(reader.runLoop)
            }, context)
            IOHIDDeviceScheduleWithRunLoop(hid, runLoop, CFRunLoopMode.commonModes.rawValue)
            startedAt = ProcessInfo.processInfo.systemUptime; lastSample = startedAt
            setStatus("Waiting for accelerometer reports")
            watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, ProcessInfo.processInfo.systemUptime - self.lastSample > 3 else { return }
                self.stop(); self.setStatus("Sensor opened but reports stopped or never arrived; helper may be required.")
            }
            return
        }
        setStatus("Unsupported: no matching Apple Silicon accelerometer")
    }

    public func stop() {
        watchdog?.invalidate(); watchdog = nil
        if let device {
            IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil
        if driver != 0 {
            for (key, value) in originalProperties { IORegistryEntrySetCFProperty(driver, key as CFString, value) }
            IOObjectRelease(driver); driver = 0; originalProperties.removeAll()
        }
        setStatus("Stopped")
    }
}
