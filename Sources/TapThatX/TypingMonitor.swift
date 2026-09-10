import AppKit

// A passive event tap observes timing only. Key contents never leave this callback.
final class TypingMonitor {
    var onKey: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var isActive: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    func start() {
        stop()
        guard CGPreflightListenEventAccess() else { return }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(1) << CGEventType.keyDown.rawValue,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<TypingMonitor>.fromOpaque(context).takeUnretainedValue()
                if type == .keyDown { monitor.onKey?() }
                else if type == .tapDisabledByTimeout, let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
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
