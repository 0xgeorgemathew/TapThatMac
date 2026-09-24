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
            appropriateFor: nil, create: true).appendingPathComponent("TapThatX/Calibration", isDirectory: true)
    }) { self.directory = directory }

    var blocksActions: Bool { [.ready, .recording, .review].contains(stage) }
    var completedCount: Int { session?.trials.filter(\.confirmed).count ?? 0 }
    var step: CalibrationStep? {
        CalibrationStep.sequence.indices.contains(completedCount) ? CalibrationStep.sequence[completedCount] : nil
    }
    var canConfirm: Bool { stage == .review && review?.quality.usable == true }
    var floor: Double? { session?.candidateFloor }

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
            message = "Actions stay paused throughout calibration."; saveError = nil; applied = false
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
        prompt = "Get ready. Keep still."; stage = .recording
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
            prompt = "Get ready · \(max(1, Int(ceil(2.5 - elapsed))))"
        } else if step.activity.expectedContacts == 0 {
            prompt = step.activity == .quiet ? "Keep still" : "Use your keyboard and trackpad"
        } else {
            if cueTime == nil { cueTime = time; recorder?.cue(at: time) }
            if let cueTime, time - cueTime < 1.5 { prompt = "Tap now" }
            else {
                if !responseEnded { recorder?.endResponse(at: time); responseEnded = true }
                prompt = "Hands off · let the surface settle"
            }
        }
        // Allow the final sensor batch to arrive before inspecting coverage.
        if elapsed >= step.duration + 0.2 { finish(at: time) }
    }

    private func finish(at time: Double) {
        guard recorder != nil else { return }
        review = recorder?.finish(at: time); recorder = nil
        message = review?.quality.usable == true
            ? "Did you perform exactly the requested activity? Only confirm if you did."
            : "This recording needs another attempt."
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
            if count == CalibrationStep.sequence.filter({ $0.partition == .training }).count {
                next.candidateFloor = try CalibrationEvaluator.candidate(from: next.trials)
                if next.candidateFloor == nil { next.finished = true }
            }
            if count == CalibrationStep.sequence.count {
                guard let candidate = next.candidateFloor else { throw CalibrationError.incomplete }
                next.verificationPassed = try CalibrationEvaluator.verify(next.trials, frozenFloor: candidate)
                next.finished = true
            }
            try persist(next)
            session = next; review = nil; saveError = nil
            if next.finished {
                stage = next.verificationPassed ? .complete : .failed
                message = next.verificationPassed
                    ? "The suggested sensitivity passed this session’s separate verification round. You can apply it below."
                    : "No verified setting was found. Your current sensitivity is unchanged. Try a clearer contact or another placement, then start a new session."
            } else {
                stage = .ready
                message = next.candidateFloor == nil ? "Recording saved locally." : "A candidate is frozen. The next recordings check it without retuning."
            }
        } catch { saveError = "Could not finish this step: \(error.localizedDescription). Your recording is still here." }
    }

    func retry() {
        guard stage == .review, let trial = review, var next = session else { return }
        next.trials.append(trial)
        do {
            try persist(next); session = next; review = nil; saveError = nil; stage = .ready
            message = "Previous attempt saved as unconfirmed. Prepare to record this step again."
        } catch { saveError = "Could not save this attempt: \(error.localizedDescription). Retry when storage is available." }
    }

    @discardableResult func cancel(at time: Double) -> Bool {
        if stage == .recording { interrupt("Calibration was cancelled.", at: time) }
        guard var next = session else { stage = .idle; return true }
        if let review { next.trials.append(review) }
        next.finished = true
        do {
            try persist(next); session = nil; review = nil; recorder = nil; saveError = nil
            stage = .idle; message = applied ? "Session saved. Your applied sensitivity remains active." : "Session saved. Sensitivity is unchanged."
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
