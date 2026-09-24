# Detection and calibration from first principles

## Starting point

An accelerometer measures motion, not intent or touch. A useful detector must distinguish a deliberate contact from background motion, confirm it promptly, avoid counting the same mechanical response twice, and preserve the timing of separate contacts. No amplitude threshold alone establishes intent. A light contact that does not produce a distinguishable signal cannot be recovered by turning up sensitivity indefinitely.

Old collected fixtures, their dependent tests, and the capture-based audit/investigation have been removed. None of those recordings is an input to this implementation. Synthetic tests describe explicit conditions and expected software behavior; they are not evidence of physical accuracy.

## Principles for improving detection

1. **Separate measurement from decisions.** Capture raw timestamped XYZ independently of the detector, including periods when it detects nothing. Otherwise the detector chooses its own training examples and misses become invisible.
2. **Observe both positive and negative examples.** Light taps and knocks establish useful signal variation; quiet and ordinary keyboard/trackpad movement constrain sensitivity. Positive-only calibration encourages false activations.
3. **Keep labels independent.** The user knows what they attempted. The UI provides a response window, and the user confirms the activity afterward. A detected peak never becomes its own label. These are interval labels with uncertainty, not exact onset annotations.
4. **Keep distinct contacts and echoes separate.** A contact has onset, duration, and decay. Refractory timing must not substitute for pulse-shape evidence, and stronger first contacts must not hide weaker second contacts. Check singles and pairs independently.
5. **Use time, not nominal sample counts.** Missing or delayed samples can erase an onset or distort a pulse. Reject poor collection rather than inventing interpolated evidence. Collection-rate requirements are engineering constraints, not claims that a rate guarantees recognition.
6. **Separate fitting from checking.** Select parameters using training recordings. Freeze them before independent recordings. Never retry alternative settings against the verification round until one passes.
7. **Measure user-visible mistakes.** Extra single events matter when a ring is open; false doubles can execute commands. Evaluate both. Count agreement without event-window agreement is insufficient.
8. **Make failure useful.** If no setting separates contacts and background, preserve the current setting and report that result. Do not silently relax quality checks or claim successful calibration.

## Implemented guided calibration

Open **Calibration** in settings. The user chooses Laptop or Desk and describes the support/placement. Calibration requires a real sensor near 800 Hz, Input Monitoring, and a visible settings window. It never starts from a historical recording or imported dataset.

The 16-step sequence is:

- Training: quiet background, everyday movement, three separate light contacts, three separate knocks.
- Verification: new quiet/background movement recordings, two new light contacts, two new knocks, a light pair, and a knock pair.

Negative trials last 10 seconds. Contact trials last 6.5 seconds: a 2.5-second preparation interval, a 1.5-second visual response window, and settling time. Actual cue/response-end times are recorded. There is no sound or haptic cue that could itself vibrate the sensor. The user explicitly confirms the intended activity or retries after each trial. Extra, premature, or missed physical contacts should be retried even when collection quality passes.

This is a short personalization check, not an independently validated accuracy benchmark. Verification is a later round within the same session; release-level evaluation still needs different days, users, devices, and placements. The visual cue is timestamped when the UI model changes, not when a display photon appears, so it is deliberately a broad interval label rather than a latency measurement.

### Collection integrity

`CalibrationRecorder` collects before production sample-age and detection gates. It bounds each trial to 12,000 samples and 2,048 key markers. It rejects invalid values, duplicate/reversed time, incomplete beginning/end, rate outside 700–900 Hz, gaps above 20 ms, delivery delays above 200 ms, delayed tap prompts, typing during positive trials, and interrupted recordings. Known dropped/rejected reports invalidate the trial; helper queue overflow now contributes to that counter.

Sensor/input changes, pausing, lifecycle resets, hidden calibration, and loss of keyboard monitoring interrupt active collection. Changing input/rate/sensitivity midway requires returning to the captured configuration or starting a new session. System actions and ring routing stay blocked while calibration is ready, recording, or awaiting review, even if the settings window closes. Pending actions are invalidated when calibration begins.

Quality acceptance means the stream is suitable for evaluation. It does not establish that the activity actually occurred. User confirmation is separately required.

### Personal sensitivity selection

The current pulse detector remains the baseline algorithm. This implementation improves how its sensitivity is chosen for the individual, rather than substituting an unvalidated general classifier.

Training tries a small, declared set of amplitude floors within existing supported limits. Each setting is tested independently, because the existing onset/decay/recovery rules need not behave monotonically with the floor. The highest qualifying floor is selected as an amplitude rejection margin; this does not prove that it has the best real-world false-positive rate.

A qualifying setting must produce exactly the requested number of contacts inside each confirmed response window, no additional contacts elsewhere after replay warmup, and zero accepted contacts in negative trials. The first 1.5 seconds reconstruct filter state and are not scored. Keyboard suppression is disabled during calibration scoring so it cannot conceal false sensor events in the negative examples. The user's normal typing-suppression preference is not changed.

The candidate is frozen after eight confirmed training trials. Verification uses the remaining eight new trials, including pairs with valid router timing. A failed verification ends the session without changing sensitivity. It is not reused for additional tuning. Successful verification offers **Use this sensitivity**; application is explicit and uses the existing persisted sensitivity setting. The applied session ID is stored for provenance. A change in surface or support needs a new calibration; this is not an automatic desk/lid classifier.

### Storage and provenance

Each session records a UUID, date, schema/detector version, device/OS, input, requested rate, initial settings, surface, placement, raw samples, observed rate/gaps/delivery delay, actual cue windows, keyboard timing, quality reasons, confirmation, partition, selected floor, and verification result.

Files are stored locally under `~/Library/Application Support/TapThatX/Calibration/session-<UUID>.json`. New sessions never reuse an old filename. Each confirmation or retry atomically checkpoints that session. Failed/unconfirmed attempts remain distinguishable and are excluded from fitting. Failed saves retain the pending trial and block progression. At most 48 attempts are retained per session. Cancellation and normal shutdown attempt to save partial work; a process crash can lose the current unconfirmed recording, while prior checkpoints remain. There is no automatic training from saved sessions, no upload, no microphone, and no recorded characters.

The existing diagnostic recordings pane is explicitly separate. Its exports now use unique filenames; they cannot qualify as guided calibration input.

`ReplayCaptures <session.json>` checks the versioned guided format, reproduces the frozen candidate, and reports matched/unexpected events and valid pairs. Old count-only exports are rejected. Replaying is diagnostic, never a command executor.

## Next algorithm experiments

These are hypotheses derived from the problem, not implemented or validated improvements:

- **Noise estimation independent of candidate acceptance:** estimate a bounded background distribution so prolonged movement can be recognized without letting a few strong contacts inflate the baseline. Compare robust quantiles or clipped energy with explicit adaptation/recovery times. Require both a minimum physical amplitude and contrast above local noise.
- **Separate sensitivity from pulse shape:** distinguish candidate-start amplitude from falling-edge confirmation and rearming. A user asking for lighter contacts should not implicitly request a different duration or echo policy. Introduce these independently and inspect their effects on fresh recordings.
- **Short-window shape evidence:** compare onset slope, energy concentration, pulse width and decay rather than a single derivative sample. Use a short bounded window; larger spectral or learned models need evidence that these simpler features cannot separate the classes.
- **Sample-rate-aware processing:** explicitly define the high-pass residual and its gain across observed sample intervals. Cancel candidates across missing evidence. Evaluate sampling phase and jitter mathematically and synthetically before physical lower-rate testing.
- **Shared live/replay event ordering:** use source time, delivery time, keyboard timing, and a processed-data watermark consistently. Keep action dispatch separate so delayed callbacks cannot produce stale commands.
- **Performance:** first measure delivery latency, main-thread stalls, allocations and sensor wakeups. Arithmetic micro-optimization is worthwhile only if it is a measured bottleneck; lowering sensor rate can discard the very transient being detected.

For each experiment: declare a failure it should address, add deterministic tests for its invariant, collect a new independent session set, freeze parameters before evaluation, and compare missed contacts, false singles/doubles, duplicates, pair completion, and confirmation/action latency. Predeclare acceptable false-action and latency budgets. Keep failed results. Do not re-label data to agree with the detector or market short-session success as universal reliability.

## Validation boundary

Automated tests exercise clean and corrupt streams, cue and typing contamination, independent labels, extra/misplaced contacts, missing steps, fitting/verification separation, pair timing, interruption, persistence failures, unique archives and end-to-end controller transitions using generated signals. Physical performance must be assessed by a person completing the new flow on the target hardware. No old recorded dataset establishes a detection claim here.

UI and persistence use existing SwiftUI/Foundation APIs and no new dependencies. Context7 was unavailable in this session; [Apple's ProgressView documentation](https://developer.apple.com/documentation/swiftui/progressview) and [Data writing options](https://developer.apple.com/documentation/foundation/nsdata/writingoptions) were consulted as the official fallback.
