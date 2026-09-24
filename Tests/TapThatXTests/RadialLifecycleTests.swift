import AppKit
import XCTest
import TapCore
@testable import TapThatX

@MainActor
final class RadialLifecycleTests: XCTestCase {
    private func controller(playSelectionSound: @escaping () -> Void = {}) throws -> RadialPanelController {
        _ = NSApplication.shared
        guard NSScreen.main != nil else { throw XCTSkip("Native panel checks require a desktop session") }
        return RadialPanelController(playSelectionSound: playSelectionSound)
    }

    private func settle(_ seconds: Double = 0.3) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    func testConfirmationCapturesLogicalCommandAndExecutesOnce() async throws {
        let ring = try controller()
        var actions: [Command] = []
        ring.onChoose = { actions.append($0) }
        ring.open()
        ring.advance()
        ring.advance()
        XCTAssertEqual(ring.state.selected, .lock)
        ring.confirm(.lock)
        ring.confirm(.next)
        ring.advance()
        await settle()
        XCTAssertEqual(actions, [.lock])
        XCTAssertFalse(ring.isOpen)
    }

    func testDismissDuringConfirmationAndReopenInvalidatesOldAction() async throws {
        let ring = try controller()
        var actions: [Command] = []
        ring.onChoose = { actions.append($0) }
        ring.open()
        ring.confirm(.lock)
        let retiringState = ring.state
        ring.dismiss(restoreFocus: false)
        XCTAssertFalse(retiringState.isPresented)
        XCTAssertNil(retiringState.choose)
        XCTAssertNil(ring.state.committing)
        ring.open()
        // The reopened ring resets to the default sector. Selection is asserted
        // synchronously here: the panel is real and centered on screen, so once
        // the run loop delivers events the ambient pointer may hover-select a
        // sector. After settling, only hover-invariant state is asserted.
        XCTAssertTrue(ring.isOpen)
        XCTAssertEqual(ring.state.selected, .playPause)
        XCTAssertEqual(ring.state.selectionAngle, 0, accuracy: 0.001)
        await settle()
        XCTAssertTrue(ring.isOpen)
        XCTAssertTrue(actions.isEmpty)
        ring.dismiss(restoreFocus: false)
    }

    func testAutomaticAndOpeningCancellationAndRepeatedCycles() async throws {
        let ring = try controller()
        var actions: [Command] = []
        ring.onChoose = { actions.append($0) }
        ring.openAndPerform(.lock)
        ring.dismiss(restoreFocus: false)
        for _ in 0..<8 {
            ring.open()
            ring.advance(by: -1)
            XCTAssertEqual(ring.state.selected, .dictation)
            ring.advance()
            XCTAssertEqual(ring.state.selected, .playPause)
            ring.dismiss(restoreFocus: false)
        }
        await settle(0.7)
        XCTAssertFalse(ring.isOpen)
        XCTAssertTrue(actions.isEmpty)
    }

    func testFocusLossCancelsConfirmation() async throws {
        let ring = try controller()
        var actions: [Command] = []
        ring.onChoose = { actions.append($0) }
        ring.open()
        ring.confirm(.approve)
        ring.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        await settle()
        XCTAssertTrue(actions.isEmpty)
        XCTAssertFalse(ring.isOpen)
    }

    func testKeyboardReversalUsesPresentedPosition() {
        let state = RingState()
        state.resetSelection(.playPause)
        state.select(.previous, direction: 1)
        state.presentedSelectionAngle = 15
        state.select(.lock, direction: -1)
        XCTAssertLessThan(state.selectionAngle, 15)
        XCTAssertEqual(state.selected, .lock)
    }

    func testPointerRetargetUsesPresentationAndKeepsLogicalIdentity() throws {
        let state = RingState()
        state.resetSelection(.playPause)
        state.select(.dictation, direction: 1)
        state.presentedSelectionAngle = 10
        state.select(.next)
        XCTAssertEqual(state.selectionAngle, 360.0 / 7, accuracy: 0.001)
        XCTAssertEqual(state.selected, .next)
    }

    func testResetSelectionRestoresCanonicalAngleAndClearsPresentation() {
        let state = RingState()
        state.resetSelection(.playPause)
        state.select(.previous, direction: -1)
        XCTAssertNotEqual(state.selectionAngle, 0)
        state.resetSelection(.dictation)
        XCTAssertNil(state.presentedSelectionAngle)
        XCTAssertEqual(state.selected, .dictation)
        XCTAssertEqual(state.selectionAngle, 6 * 360.0 / 7, accuracy: 0.001)
    }

    func testReselectingMovingCommandDoesNotPublishOrReverseItsFlight() {
        let state = RingState()
        state.resetSelection(.playPause)
        state.select(.dictation, direction: 1)
        let endpoint = state.selectionAngle
        state.presentedSelectionAngle = 20
        var changes = 0
        let subscription = state.objectWillChange.sink { changes += 1 }

        for direction in [0, 1, -1] { state.select(.dictation, direction: direction) }

        XCTAssertEqual(state.selectionAngle, endpoint, accuracy: 0.001)
        XCTAssertEqual(state.presentedSelectionAngle, 20)
        XCTAssertEqual(changes, 0, "Hover/confirmation of the current option must not restart its animation")
        withExtendedLifetime(subscription) {}
    }

    func testConfirmingHoveredLockDoesNotRepublishSelection() throws {
        let ring = try controller()
        ring.open()
        defer { ring.dismiss(restoreFocus: false) }
        ring.state.select(.lock)
        ring.state.presentedSelectionAngle = 90
        let endpoint = ring.state.selectionAngle
        var angleChanges = 0
        var selectionChanges = 0
        let angleSubscription = ring.state.$selectionAngle.dropFirst().sink { _ in angleChanges += 1 }
        let selectionSubscription = ring.state.$selected.dropFirst().sink { _ in selectionChanges += 1 }

        ring.confirm(.lock)

        XCTAssertEqual(ring.state.committing, .lock)
        XCTAssertEqual(ring.state.selectionAngle, endpoint, accuracy: 0.001)
        XCTAssertEqual(angleChanges, 0)
        XCTAssertEqual(selectionChanges, 0)
        withExtendedLifetime((angleSubscription, selectionSubscription)) {}
    }

    func testSelectionSoundPlaysOnceOnConfirmationAcrossReopen() async throws {
        var sounds = 0
        let ring = try controller { sounds += 1 }
        var actions: [Command] = []
        ring.onChoose = { actions.append($0) }
        ring.confirm(.lock)
        XCTAssertEqual(sounds, 0)
        ring.open()
        ring.state.select(.lock)
        ring.advance()
        XCTAssertEqual(sounds, 0, "Highlighting alone is silent")
        ring.state.choose?(.lock)
        ring.confirm(.next)
        ring.advance()
        XCTAssertEqual(sounds, 1)
        await settle()
        XCTAssertEqual(actions, [.lock])

        ring.open()
        ring.confirm(.next)
        XCTAssertEqual(sounds, 2)
        ring.dismiss(restoreFocus: false)
        await settle()
        XCTAssertEqual(sounds, 2)
        XCTAssertEqual(actions, [.lock], "Cancelling the press still cancels execution")
    }

    func testAutomaticLockConfirmsWithOneSoundAndNoSelectionRetarget() async throws {
        var sounds = 0
        let ring = try controller { sounds += 1 }
        var actions: [Command] = []
        ring.onChoose = { actions.append($0) }
        ring.openAndPerform(.lock)
        var selectedCommands: [Command?] = []
        let subscription = ring.state.$selected.dropFirst().sink { selectedCommands.append($0) }
        await settle(0.85)
        XCTAssertEqual(selectedCommands, [.lock])
        XCTAssertEqual(sounds, 1)
        XCTAssertEqual(actions, [.lock])
        XCTAssertFalse(ring.isOpen)
        withExtendedLifetime(subscription) {}
    }

    func testCancelledAutomaticLockStaysSilent() async throws {
        var sounds = 0
        let ring = try controller { sounds += 1 }
        ring.openAndPerform(.lock)
        ring.dismiss(restoreFocus: false)
        await settle(0.7)
        XCTAssertEqual(sounds, 0)
    }
}
