import AppKit
import XCTest
import TapCore
@testable import TapThatMac

@MainActor
final class RingPreviewTests: XCTestCase {
    private func model(mode: ActionAvailability.Mode,
                       execute: @escaping (Command, Bool) -> String) throws -> (AppModel, () -> Void) {
        _ = NSApplication.shared
        guard NSScreen.main != nil else { throw XCTSkip("Native panel checks require a desktop session") }
        let suite = "RingPreviewTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(mode.rawValue, forKey: "operatingMode")
        let model = AppModel(startServices: false, modeDefaults: defaults, commandExecution: execute)
        model.accessibilityPermission = true
        return (model, {
            model.shutdown()
            defaults.removePersistentDomain(forName: suite)
        })
    }

    func testPreviewSelectionNeverReachesExecutionInAnyMode() async throws {
        for mode in [ActionAvailability.Mode.active, .test, .paused] {
            var executions: [Command] = []
            let (model, cleanup) = try model(mode: mode) { command, _ in
                executions.append(command)
                return "Intercepted external execution"
            }
            defer { cleanup() }
            for command in Command.allCases {
                model.previewRing()
                XCTAssertTrue(model.ring.isOpen)
                XCTAssertTrue(model.ringPreviewActive)
                model.ring.state.choose?(command)
                try await Task.sleep(for: .milliseconds(300))
                XCTAssertFalse(model.ring.isOpen)
                XCTAssertFalse(model.ringPreviewActive, "Dismissal still clears presentation state")
                XCTAssertTrue(executions.isEmpty, "Preview executed \(command) in \(mode)")
                XCTAssertTrue(model.acknowledgment.hasPrefix("Preview only"))
            }
        }
    }

    func testNormalSelectionAfterPreviewCancellationStillExecutesOnce() async throws {
        var executions: [Command] = []
        var enabled: [Bool] = []
        let (model, cleanup) = try model(mode: .active) { command, allowed in
            executions.append(command)
            enabled.append(allowed)
            return "Intercepted external execution"
        }
        defer { cleanup() }
        model.previewRing()
        model.ring.confirm(.lock)
        model.ring.dismiss(restoreFocus: false)
        XCTAssertFalse(model.ringPreviewActive)
        model.ring.open()
        model.ring.state.choose?(.playPause)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(executions, [.playPause], "Cancelled preview must not dispatch into the new presentation")
        XCTAssertEqual(enabled, [true])
        XCTAssertFalse(model.ring.isOpen)
    }

    func testCancellingPreviewWithoutSelectionDoesNotExecute() async throws {
        var executions: [Command] = []
        let (model, cleanup) = try model(mode: .active) { command, _ in
            executions.append(command)
            return "Intercepted external execution"
        }
        defer { cleanup() }
        model.previewRing()
        model.ring.dismiss(restoreFocus: false)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(executions.isEmpty)
        XCTAssertFalse(model.ringPreviewActive)
        XCTAssertFalse(model.ring.isOpen)
    }
}
