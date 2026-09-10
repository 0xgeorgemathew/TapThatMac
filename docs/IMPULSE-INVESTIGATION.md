# On-Mac consistency investigation — September 10, 2026

Historical investigation supporting the current baseline. References to `diagnostics/` below refer to local research artifacts archived outside the repository during cleanup; they are not build inputs. Regression fixtures and targeted tests remain versioned in `Tests/TapCoreTests`.

## Evidence and diagnosis

The supplied 10.383-second MOV contains 60 fps video and 48 kHz mono audio. Frames were inspected; audio was extracted and analyzed numerically, not directly listened to. A 5 ms RMS envelope identifies 26 prominent transients, commonly 165–215 ms apart within groups. These are acoustic events, not ground-truth accelerometer tap labels: the video does not show the hand, and some sounds could be key presses or other contacts.

A blue-sector image mask estimates ring visibility transitions at 1.367 s (hidden), 3.767 s (visible) and 8.200 s (hidden); it is visible initially. The ring stays unchanged through several acoustic groups. This supports investigating consistency but cannot distinguish detector rejection from typing suppression without raw sensor timestamps. Extracted frames, waveform peaks and transition measurements are in diagnostics/video-analysis.

The screenshots show unequal pulse strengths and settling tails. Three specific detector properties matter:

1. The existing 300 ms reference retains settling motion after a contact. A weaker second contact can partially cancel the signed residual before its magnitude is taken, or encounter an elevated noise threshold/unrearmed detector.
2. Timing the gesture from confirmation on the falling edge makes the apparent inter-tap gap depend on the two pulse widths. A 440 ms onset gap became an invalid >450 ms gap when the second pulse lasted longer. A targeted test failed before the fix and now passes.
3. Simply shortening the existing filter, or widening its recovery threshold, is insufficient. Experiments recovered synthetic taps but lost previously detected recordings or accepted table shaking/ringing. Those replacements were rejected.

## Research basis

ST describes tap recognition on a slope/high-pass signal with separate threshold, shock duration, quiet and double-tap timing windows:
https://www.st.com/resource/en/application_note/an4748-lis2ds12-alwayson-3d-accelerometer-stmicroelectronics.pdf
https://www.st.com.cn/resource/en/design_tip/dt0101-setting-up-singletap-and-doubletap-recognition-with-sts-mems-accelerometers-stmicroelectronics.pdf

Analog Devices likewise separates amplitude/duration from latency/window, and warns that overly small settings can recognize vibration echoes:
https://www.analog.com/media/en/technical-documentation/data-sheets/ADXL344.pdf

These establish useful design principles, not the right numeric parameters for this Mac. This app still consumes the Mac's existing sensor reports; it does not enable those vendors' hardware tap interrupts.

## Implementation

- Preserve the established knock-envelope detector.
- In the existing light-tap sensitivity range, add a 10 ms impulse reference with a stricter 3 g/s onset requirement. Its independent settling state can recognize a light second contact while the envelope is still recovering.
- Coalesce detections from both paths before gesture routing. The same physical contact must not become two taps.
- Route using the accepted onset timestamp, retaining falling-edge confirmation and typing suppression.
- Keep the prior 100 ms double-only recovery. No triple recognition was re-enabled.
- Log accepted path/onset/confirmation and per-path slow-onset/long-pulse rejection events locally. A rejection in one path does not imply the other path rejected the contact.
- Keep at most 12,000 XYZ samples and 1,024 key timestamps in memory. The menu's “Save last 15 seconds” exports that context and event log while ordinary actions remain enabled. No characters, microphone capture, automatic disk writes or uploads. Each export uses a unique filename and does not replace the calibration dataset.

The graph continues showing the original motion envelope. It is an overview, not a plot of both detector paths. The recent export is the source for diagnosing a missed interaction. Its initial 1.5 seconds need replay warmup, and initial filter state is reconstructed rather than serialized.

## Validation

51 tests pass, including:

- 27 asymmetric-pair scenarios spanning XYZ axes, polarity, three decay times and three second-tap strengths; all produce eight taps/four pairs. The preceding detector failed three scenarios.
- 16 single ringing-contact scenarios spanning 20–120 Hz and 30–200 ms decay, without false double-taps.
- Different pulse widths with a valid 440 ms onset gap.
- Previously recognized light-profile captures, repeated pairs and immediate echo rejection.
- Existing typing, moving-object, shaking, warmup, buffering and routing tests.
- Recent-context memory bounds, time ordering, expiry and invalid input handling.

Saved-data results: diagnostics/impulse-onset-replay.txt. Strong-knock counts are unchanged. At 0.008 g, one previously missed original chassis capture is recovered, and previously recognized captures remain recognized. The known 100 Hz light-profile shaking false positive remains. Desk and 10 Hz detection are not solved.

An optimized detector-only microbenchmark on 1.6 million samples measured 0.042 s CPU before and 0.062 s after (approximately 0.0021% versus 0.0031% of one core at 800 Hz). This is not whole-app CPU: sensor delivery, UI, event logging and the new memory buffer are outside that benchmark. No overall CPU reduction is claimed.

## Live acceptance

The remaining requirement is physical on-Mac consistency, not more parameter tuning. Use 800 Hz and the existing 0.008 g setting, close settings, and repeat ring open/dismiss cycles with trackpad and left/right contacts. If a cycle fails, immediately use “Save last 15 seconds”; the export includes the ordinary interaction rather than a separate calibration session. The video alone cannot validate this new detector or establish calibration-free behavior across surfaces.
