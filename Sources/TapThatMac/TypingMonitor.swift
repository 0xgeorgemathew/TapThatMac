import AppKit

// A passive event tap observes timing only. Key contents and pointer
// positions never leave this callback.
final class TypingMonitor {
    var onKey: (() -> Void)?
    /// Clicks: a Force Touch trackpad click fires the Taptic Engine inside the
    /// chassis, and a double-click looks just like a double-tap to the sensor.
    var onPointer: (() -> Void)?
    private static let events: [CGEventType] = [.keyDown, .leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown]
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var isActive: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    func start() {
        stop()
        guard CGPreflightListenEventAccess() else { return }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: Self.events.reduce(CGEventMask(0)) { $0 | CGEventMask(1) << $1.rawValue },
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<TypingMonitor>.fromOpaque(context).takeUnretainedValue()
                switch type {
                case .keyDown: monitor.onKey?()
                case .leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown: monitor.onPointer?()
                case .tapDisabledByTimeout, .tapDisabledByUserInput:
                    if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                default: break
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }
    deinit { stop() }
}
