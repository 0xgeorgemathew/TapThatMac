import Foundation
import Combine
import TapCore

/// UI transitions and local persistence; collection and scoring remain in TapCore.
final class CalibrationController: ObservableObject {
    enum Stage { case idle, ready, recording, review, complete, failed }
    @Published private(set) var stage: Stage = .idle
    @Published private(set) var prompt = ""
    @Published private(set) var progress = 0.0
    @Published private(set) var message = ""
    @Published private(set) var saveError: String?
    @Published private(set) var applied = false
    private(set) var session: CalibrationSession?
    private(set) var review: CalibrationTrial?
    private(set) var archiveURL: URL?
    private var recorder: CalibrationRecorder?
    private var cueTime: Double?
    private var responseEnded = false
    private let directory: () throws -> URL

    init(directory: @escaping () throws -> URL = {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("Tap That Mac/Calibration", isDirectory: true)
    }) { self.directory = directory }

    var blocksActions: Bool { [.ready, .recording, .review].contains(stage) }
    var completedCount: Int { session?.trials.filter(\.confirmed).count ?? 0 }
    var steps: [CalibrationStep] { CalibrationStep.sequence }
    var step: CalibrationStep? {
        steps.indices.contains(completedCount) ? steps[completedCount] : nil
    }
    var canConfirm: Bool { stage == .review && review?.quality.usable == true }
    var reviewMatchesExpectedGesture: Bool {
        guard canConfirm, var trial = review else { return false }
        trial.confirmed = true
        // Negative trials teach rejection; the unfitted detector must not veto
        // collecting the very disturbances it currently mistakes for taps.
        if trial.step.activity.expectedContacts == 0 { return true }
        // Always evaluate verification against the frozen profile, not a new fit.
        if trial.step.partition == .verification { return true }
        var permissive = DetectorSettings()
        permissive.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: DetectorSettings.minimumAmplitudeFloor)
        permissive.minimumRiseRate = 0.5
        permissive.impulseMinimumRiseRate = 1
        permissive.maximumPulseDuration = 0.05
        permissive.maximumTapInterval = 0.7
        return (try? CalibrationEvaluator.score(trial, settings: permissive).passed) == true
    }
    var floor: Double? { session?.candidateFloor }
    var candidateSettings: DetectorSettings? { session?.candidateSettings }

    var canRetrySave: Bool { saveError != nil && reviewMatchesExpectedGesture }

    func retrySave() {
        guard canRetrySave else { return }
        confirm()
    }

    /// A deliberate new opening starts over only after the previous profile was applied.
    /// The archived session and the active detector profile remain saved.
    func prepareForPresentation() {
        guard stage == .complete, applied else { return }
        session = nil; review = nil; recorder = nil; archiveURL = nil
        cueTime = nil; responseEnded = false; progress = 0; prompt = ""
        message = ""; saveError = nil; applied = false
        stage = .idle
    }

    func begin(context: CalibrationContext) {
        guard !blocksActions else { return }
        let fresh = CalibrationSession(context: context)
        do {
            let folder = try directory()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("session-\(fresh.id.uuidString).json")
            // Persist provenance before enabling collection. A new session never reuses an old name.
            try JSONEncoder().encode(fresh).write(to: url, options: .withoutOverwriting)
            archiveURL = url; session = fresh; recorder = nil; review = nil
            message = ""; saveError = nil; applied = false
            stage = .ready
        } catch { saveError = "Could not create the local session: \(error.localizedDescription)" }
    }

    func record(at time: Double) {
        guard stage == .ready, let step, let session else { return }
        guard session.trials.count < 48 else {
            message = "This session reached its recording limit. Start a new session."; stage = .failed; return
        }
        recorder = CalibrationRecorder(step: step, started: time)
        cueTime = nil; responseEnded = false; progress = 0; review = nil; saveError = nil
        prompt = "Get ready"; stage = .recording
    }
    func append(_ samples: [AccelerationSample], receivedAt: Double) {
        guard stage == .recording else { return }
        for sample in samples { recorder?.append(sample, receivedAt: receivedAt) }
    }
    func key(at time: Double) { recorder?.key(at: time) }
    func flag(_ issue: String) { recorder?.flag(issue) }

    func tick(at time: Double) {
        guard stage == .recording, let started = recorder?.started, let step else { return }
        let elapsed = time - started
        progress = min(1, max(0, elapsed / step.duration))
        if elapsed < 2.5 {
            prompt = "Get ready  \(max(1, Int(ceil(2.5 - elapsed))))"
        } else if step.activity.expectedContacts == 0 {
            switch step.activity {
            case .quiet: prompt = "Keep still"
            case .everydayMotion: prompt = "Type and move normally"
            case .surfaceBump: prompt = "Move your chair and nudge the table"
            default: prompt = step.activity.title
            }
        } else {
            if cueTime == nil { cueTime = time; recorder?.cue(at: time) }
            if let cueTime, time - cueTime < step.responseDuration { prompt = "Tap now" }
            else {
                if !responseEnded { recorder?.endResponse(at: time); responseEnded = true }
                prompt = "Got it"
            }
        }
        // Allow the final sensor batch to arrive before inspecting coverage.
        if elapsed >= step.duration + 0.2 { finish(at: time) }
    }

    private func finish(at time: Double) {
        guard recorder != nil else { return }
        review = recorder?.finish(at: time); recorder = nil
        message = review?.quality.usable == true ? "" : "The sensor stream was interrupted."
        stage = .review
    }

    func interrupt(_ reason: String, at time: Double) {
        guard blocksActions else { return }
        if stage == .recording {
            recorder?.flag(reason); finish(at: time)
        } else if stage == .ready {
            message = reason
        }
    }

    func confirm() {
        guard canConfirm, var trial = review, var next = session else { return }
        trial.confirmed = true; next.trials.append(trial)
        let count = next.trials.filter(\.confirmed).count
        do {
            let sessionSteps = CalibrationStep.sequence
            let trainingCount = sessionSteps.filter { $0.partition == .training }.count
            if count == trainingCount {
                next.candidateSettings = try CalibrationEvaluator.candidateSettings(
                    from: next.trials, expectedSteps: sessionSteps)
                next.candidateFloor = next.candidateSettings?.amplitudeFloor
                next.finished = next.candidateSettings == nil
            }
            if trial.step.partition == .verification, let frozen = next.candidateSettings {
                // A failed holdout ends this fit. Retrying until it passes would
                // hide natural variation and turn verification into more training.
                let passed = try CalibrationEvaluator.score(trial, settings: frozen).passed
                if !passed { next.finished = true }
                else if count == sessionSteps.count {
                    next.verificationPassed = try CalibrationEvaluator.verify(
                        next.trials, frozenSettings: frozen, expectedSteps: sessionSteps)
                    next.finished = true
                }
            }
            try persist(next)
            session = next; review = nil; saveError = nil
            if next.finished {
                stage = next.verificationPassed ? .complete : .failed
                message = next.verificationPassed
                    ? "Your taps are ready."
                    : "This profile could not preserve your taps while rejecting the recorded desk activity. Keep the Mac in its usual desk position and try a fresh session."
            } else {
                stage = .ready
                message = ""
            }
        } catch { saveError = "Could not finish this step: \(error.localizedDescription). Your recording is still here." }
    }

    func retry() {
        guard stage == .review, let trial = review, var next = session else { return }
        next.trials.append(trial)
        do {
            try persist(next); session = next; review = nil; saveError = nil; stage = .ready
            message = ""
        } catch { saveError = "Could not save this attempt: \(error.localizedDescription). Retry when storage is available." }
    }

    @discardableResult func cancel(at time: Double) -> Bool {
        if stage == .recording { interrupt("Calibration was cancelled.", at: time) }
        guard var next = session else { stage = .idle; return true }
        if let review { next.trials.append(review) }
        next.finished = true
        do {
            try persist(next); session = nil; review = nil; recorder = nil; saveError = nil
            stage = .idle; message = applied ? "Your tap profile remains active." : "Detector settings are unchanged."
            return true
        } catch {
            saveError = "Could not save before closing: \(error.localizedDescription). Your recordings remain in memory."
            return false
        }
    }

    func markApplied() { applied = true }

    private func persist(_ value: CalibrationSession) throws {
        guard let archiveURL else { throw CalibrationError.incomplete }
        // Atomic replacement updates only this unique session's checkpoint.
        try JSONEncoder().encode(value).write(to: archiveURL, options: .atomic)
    }
}
