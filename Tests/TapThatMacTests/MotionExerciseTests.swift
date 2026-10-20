import AppKit
import XCTest
import TapCore
@testable import TapThatMac

/// Live motion harness. These tests drive the real centered panel on the real
/// window server, so they run only when explicitly requested:
/// RING_EXERCISE=1 swift test --filter MotionExerciseTests
/// All assertions are on logical state, never pixels. The ambient pointer may
/// hover-select while the panel is on screen, so selection is asserted only
/// synchronously (before the run loop delivers hover events) or immediately
/// after a direct select; settles gate only hover-invariant state such as
/// isOpen, committing and executed actions.
@MainActor
final class MotionExerciseTests: XCTestCase {
    private func exerciseController() throws -> RadialPanelController {
        guard ProcessInfo.processInfo.environment["RING_EXERCISE"] == "1" else {
            throw XCTSkip("Set RING_EXERCISE=1 to drive the real panel")
        }
        _ = NSApplication.shared
        guard NSScreen.main != nil else { throw XCTSkip("Native panel checks require a desktop session") }
        return RadialPanelController(playSelectionSound: {})
    }

    private func settle(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    /// Polls on an explicit deadline so slow frames under load widen the wait
    /// instead of failing the assertion.
    private func wait(timeout: Double, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    /// Distance in turns from a whole revolution, safe either side of 0/360.
    private func wholeTurnError(_ angle: Double) -> Double {
        abs(angle / 360 - (angle / 360).rounded())
    }

    func testRapidAdvanceWithWrapStaysContinuous() async throws {
        let ring = try exerciseController()
        var actions: [Command] = []
        ring.onChoose = { actions.append($0) }
        ring.open()
        XCTAssertTrue(ring.isOpen)
        XCTAssertEqual(ring.state.selected, .playPause)
        let count = Command.allCases.count
        // Three clockwise laps, crossing last->first on each lap. The endpoint
        // is a whole number of turns whether the surface is still at its start
        // (open() renders once synchronously) or accumulated turn by turn.
        for _ in 0..<3 {
            for _ in 0..<count { ring.advance() }
            XCTAssertEqual(ring.state.selected, .playPause)
        }
        XCTAssertLessThan(wholeTurnError(ring.state.selectionAngle), 0.000001)
        // Two counterclockwise laps back.
        for _ in 0..<(2 * count) { ring.advance(by: -1) }
        XCTAssertEqual(ring.state.selected, .playPause)
        XCTAssertLessThan(wholeTurnError(ring.state.selectionAngle), 0.000001)
        // Real frames: the spring flies toward the settled target.
        await settle(0.12)
        // Rapid reversal pairs; each select forces its command, so an ambient
        // hover between pairs cannot shift the expectation.
        for _ in 0..<10 {
            ring.state.select(.next, direction: 1)
            XCTAssertEqual(ring.state.selected, .next)
            ring.state.select(.playPause, direction: -1)
            XCTAssertEqual(ring.state.selected, .playPause)
        }
        XCTAssertLessThan(wholeTurnError(ring.state.selectionAngle), 0.000001)
        XCTAssertLessThan(abs(ring.state.selectionAngle), 1440)
        await settle(0.2)
        XCTAssertTrue(ring.isOpen)
        XCTAssertTrue(actions.isEmpty)
        ring.dismiss(restoreFocus: false)
        XCTAssertFalse(ring.isOpen)
    }

    func testRetargetsFromMidFlightPresentedAngles() async throws {
        let ring = try exerciseController()
        var actions: [Command] = []
        ring.onChoose = { actions.append($0) }
        ring.open()
        XCTAssertEqual(ring.state.selected, .playPause)
        let sweep = 360.0 / Double(Command.allCases.count)
        // Pointer-style retargets while the surface sits between sectors.
        var presented = 20.0
        for command in Command.allCases {
            ring.state.presentedSelectionAngle = presented
            ring.state.select(command)
            let expected = Double(Command.allCases.firstIndex(of: command)!) * sweep
            XCTAssertEqual(ring.state.selectionAngle.truncatingRemainder(dividingBy: 360), expected, accuracy: 0.0001)
            XCTAssertLessThanOrEqual(abs(ring.state.selectionAngle - presented), 180.0001)
            presented = ring.state.selectionAngle - 12
        }
        XCTAssertEqual(ring.state.selected, .dictation)
        // Re-selecting the same command from short of its endpoint adds no turn.
        let endpoint = ring.state.selectionAngle
        ring.state.presentedSelectionAngle = endpoint - 12
        ring.state.select(.dictation)
        XCTAssertEqual(ring.state.selectionAngle, endpoint, accuracy: 0.0001)
        // A real flight starts, then a retarget lands on the adjacent sector.
        ring.state.select(.lock, direction: 1)
        await settle(0.08)
        let origin = ring.state.presentedSelectionAngle ?? ring.state.selectionAngle
        ring.state.select(.next)
        XCTAssertEqual(ring.state.selectionAngle.truncatingRemainder(dividingBy: 360), sweep, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(abs(ring.state.selectionAngle - origin), 180.0001)
        // Sustained travel keeps the highlight moving for a trace window.
        let sequence: [Command] = [.lock, .previous, .approve, .reject, .dictation, .playPause, .next,
                                   .previous, .reject, .playPause, .lock, .dictation, .next, .playPause,
                                   .previous, .lock, .next, .reject, .approve, .previous, .dictation,
                                   .playPause, .lock, .next]
        for command in sequence {
            ring.state.select(command)
            try? await Task.sleep(for: .milliseconds(140))
        }
        ring.state.select(.previous)
        XCTAssertEqual(ring.state.selected, .previous)
        XCTAssertEqual(ring.state.selectionAngle.truncatingRemainder(dividingBy: 360), 3 * sweep, accuracy: 0.0001)
        await settle(0.35)
        XCTAssertTrue(ring.isOpen)
        XCTAssertTrue(actions.isEmpty)
        ring.dismiss(restoreFocus: false)
    }

    func testConfirmWhileSelectionIsMovingExecutesConfirmedCommandOnce() async throws {
        let ring = try exerciseController()
        var actions: [Command] = []
        ring.onChoose = { actions.append($0) }
        ring.open()
        // The highlight is mid-travel when a different sector is committed.
        ring.state.select(.dictation, direction: 1)
        await settle(0.08)
        ring.state.presentedSelectionAngle = 100
        ring.confirm(.lock)
        XCTAssertEqual(ring.state.selected, .lock)
        XCTAssertEqual(ring.state.committing, .lock)
        XCTAssertEqual(ring.state.selectionAngle.truncatingRemainder(dividingBy: 360), 2 * 360.0 / 7, accuracy: 0.0001)
        // While committing, further input must not queue a second execution.
        ring.confirm(.next)
        ring.advance()
        await wait(timeout: 1.5) { !ring.isOpen }
        XCTAssertFalse(ring.isOpen)
        XCTAssertEqual(actions, [.lock])
    }

    func testDismissDuringOpeningAndMidConfirmation() async throws {
        let ring = try exerciseController()
        var actions: [Command] = []
        ring.onChoose = { actions.append($0) }
        ring.open()
        ring.dismiss(restoreFocus: false)
        XCTAssertFalse(ring.isOpen)
        await settle(0.25)
        XCTAssertFalse(ring.isOpen)
        XCTAssertTrue(actions.isEmpty)
        // Reopen, then abort while the 0.22 s execution timer is still pending.
        ring.open()
        XCTAssertTrue(ring.isOpen)
        XCTAssertEqual(ring.state.selected, .playPause)
        ring.state.presentedSelectionAngle = 200
        ring.confirm(.reject)
        XCTAssertEqual(ring.state.committing, .reject)
        await settle(0.1)
        ring.dismiss(restoreFocus: false)
        await settle(0.35)
        XCTAssertTrue(actions.isEmpty)
        XCTAssertFalse(ring.isOpen)
    }

    func testRepeatedOpenCloseCycles() async throws {
        let ring = try exerciseController()
        var actions: [Command] = []
        ring.onChoose = { actions.append($0) }
        for cycle in 0..<6 {
            ring.open()
            XCTAssertTrue(ring.isOpen)
            // Synchronous: the default sector before any hover can arrive.
            XCTAssertEqual(ring.state.selected, .playPause)
            if cycle % 2 == 0 {
                ring.advance(by: -1)
                XCTAssertEqual(ring.state.selected, .dictation)
                await settle(0.15) // opening and selection springs fly
                ring.confirm(.dictation) // hover-proof: confirm forces the command
                XCTAssertEqual(ring.state.committing, .dictation)
                await wait(timeout: 1.5) { !ring.isOpen }
                XCTAssertFalse(ring.isOpen)
                XCTAssertEqual(actions.last, .dictation)
            } else {
                ring.advance()
                XCTAssertEqual(ring.state.selected, .next)
                await settle(0.15)
                ring.dismiss(restoreFocus: false)
                XCTAssertFalse(ring.isOpen)
            }
        }
        XCTAssertEqual(actions, [.dictation, .dictation, .dictation])
    }
}
