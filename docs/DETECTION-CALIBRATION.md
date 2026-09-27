# Desk detection and calibration

TapThatX uses a deterministic pulse detector. The supported target is a Mac sitting on a desk: open, or closed while macOS is awake with an active external display. Light taps and knocks are both intentional inputs. Lap use and waking a sleeping Mac are outside this detector's scope. Lid angle alone cannot establish that a Mac is resting on a desk.

## Calibration contract

Choose **Calibrate…** in Live and select the physical setup. Save separate profiles for open-lid and closed-lid use, and select the appropriate profile in Live when switching. The setup label is manual; the app does not automatically identify the surface or lid state. Calibration should happen in the actual operating position, with the external display active for closed-lid use.

The guided flow takes about two minutes:

- Record everyday activity, including typing, resting hands, and placing an object on the desk.
- Record table and leg movement without deliberate command taps.
- Record one light tap, a light pair, one knock, and a knock pair.
- Repeat those six exercises as fresh verification recordings with the candidate settings held fixed.

The first six recordings fit the profile. The second six do not influence fitting. A missed intended contact or an accepted unwanted contact in usable verification data fails that session. A bad sensor capture can be retried; verification cannot silently refit the settings until it passes. Profiles that cannot separate the supplied examples are not applied. The previous settings remain active after failure or cancellation.

The UI advances usable captures automatically and applies a qualifying profile automatically. Labels come from the requested exercise and the user's participation, not independently observed contact timestamps. The main navigation is hidden during calibration; actions remain blocked during collection and review. Collection rejects interrupted streams, delayed or missing samples, and typing during positive gestures. Typing is allowed during negative activity. Negative replay deliberately disables the keyboard veto so it cannot conceal sensor false positives.

This flow learns to accept light taps AND knocks. It does not need to classify them as different commands or demand a clear strength difference between them.

## Detector and routing

The broad motion envelope and the short high-pass impulse path share pulse-shape checks and quiet rearming. The impulse path operates only below a configured floor of 0.0175 g. Its threshold can be below the broad motion floor, but it requires a sharper onset. Minimum configured amplitude is 0.002 g in both live settings and calibration. Contrast normalization respects that floor instead of imposing a hidden 0.0025 g minimum.

Contacts from the two paths are coalesced for 110 ms. This keeps the existing 90–105 ms echo examples suppressed while permitting generated 120–130 ms pairs. It is a bounded heuristic, not proof that every desk's resonance has ended at 110 ms. Pulse duration, rise rate, adaptive background gates, and quiet rearming remain necessary. Generated ringing sweeps guard against counting one decaying impact twice.

Pairing uses contact onset times. The gesture clock waits for any pulse still awaiting confirmation or delivery before expiring a possible pair; the former fixed 40 ms allowance alone was shorter than the supported 50 ms confirmation duration. The same rule is used in replay and the live app.

Inside the ring, a recognized first tap shows “Tap received” while awaiting a possible second tap. Selection still advances only when the pair window ends (450 ms by default, up to 700 ms after calibration). A double tap confirms the current selection. Advancing immediately would change which command that double tap selects. Keyboard-adjacent motion remains vetoed for 180 ms when typing suppression is enabled.

The fitter searches a bounded set of amplitude, rise-rate, pulse-duration and pair-window settings. It prefers the highest floor and strongest shape settings that preserve all training contacts and reject the training disturbances. Fresh verification tests that choice; no separation yields a failed calibration, not an accuracy claim.

## Graph

Low-range detail uses the existing nonlinear scale and preserves brief peaks in 20 ms display buckets. Cyan is the broad envelope; violet is the light-contact impulse. Gold dashes show the envelope gate; violet dots show the impulse gate. The solid adjustable gold line is the configured broad minimum. Hold and hover expose both signals and gates. A line crossing is not sufficient evidence that pulse shape, typing suppression and gesture timing also passed.

## Persistence and replay

Sessions are stored only in `~/Library/Application Support/TapThatX/Calibration/`. Unique files preserve raw XYZ samples, cue windows, quality information and settings. No characters, audio or network uploads are collected. Schema 5 / `desk-verified-profile-v5` records the new training/verification split.

`ReplayCaptures` understands the schema's actual step sequence. Older four-gesture sessions are training-only and cannot claim independent verification. Earlier extended sessions remain replayable when their frozen settings reproduce under the current detector. Algorithm changes can invalidate an older replay; that is reported rather than silently accepting it.

## Evidence and limits

Automated tests reproduce the hidden low-level contrast cutoff, fast-pair loss, and premature pair expiration, and check their corrections. They also cover echo suppression, weak/unequal contacts, pulse shapes, typing vetoes, held graph snapshots, calibration failure paths and frozen verification. These are generated-signal and software-state tests, not measurements of real desk reliability.

Amplitude, shock duration, quiet time and double-tap latency are separate controls in ST's [accelerometer tap-detection application note](https://www.st.com/resource/en/application_note/an4748-lis2ds12-alwayson-3d-accelerometer-stmicroelectronics.pdf). That supports checking timing and pulse shape before adding a learned classifier; it does not validate this app's numeric thresholds on Apple hardware.

Physical acceptance still requires recordings from each intended desk setup. Measure missed light taps, missed knocks, missed pairs, unintended ring advances, false openings/actions per hour and response latency. A short calibration does not cover an entire day of unwanted contacts. If an accidental and intentional contact produce effectively identical sensor data, neither a threshold nor a CNN can reliably infer intent from that data alone. See [the CNN reassessment](CNN-REASSESSMENT.md).
