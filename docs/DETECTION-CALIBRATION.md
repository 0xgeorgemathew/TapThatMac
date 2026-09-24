# Detection and calibration from first principles

TapThatX calibrates its deterministic pulse detector from fresh gestures on the current Mac. It does not import historical captures, train a general classifier, upload motion, or ask the user to label a dataset.

## Product contract

Calibration is an immersive, minimal interaction rather than a settings form. It is available on first run and from **Calibrate…** in Tap Tuning. The settings chrome disappears during the session.

The entire visible flow is:

1. One light tap.
2. Two light taps.
3. One natural tap.
4. Two natural taps.

Each gesture gets one visual indicator, a short countdown, a tap cue, and automatic captured feedback. A valid capture advances without a review screen. A missed or ambiguous gesture stays on the same step and offers one retry action. A qualifying profile is applied automatically at the end.

## What is measured

The accelerometer stream is collected only for the bounded four gesture windows. Each window begins 2.5 seconds before the cue, which gives the evaluator a local ambient baseline without asking for separate quiet, typing, chair, or table-bump exercises. The cue then remains open for 2.5 seconds so reaction time does not clip the second contact.

For every prompted window, replay must find:

- exactly the requested number of contacts inside the response window;
- valid pair timing for double taps;
- no additional accepted contacts outside the response window;
- continuous sensor delivery near 800 Hz;
- no typing over the requested gesture.

The detector combines a broad motion envelope with a short high-pass impulse path. The impulse path may operate below the broad motion floor because it must also pass stricter onset-speed and pulse-duration gates. Accepted contacts from either path are coalesced for 140 ms, covering the 90–105 ms chassis echo seen in local hardware traces without merging an ordinary human double tap.

The fitter searches a deliberately small set of amplitude floors, onset-speed gates, maximum pulse durations, and pair windows. It prefers the strictest profile that preserves all four gestures and rejects extra impacts in their surrounding baselines. Pair windows range from the default 450 ms to 700 ms, allowing calibration to preserve a comfortable light-tap cadence without slowing every user by default. The search is intentionally bounded because four gestures cannot justify a broad parameter grid.

## State and safety

System actions and ring routing remain blocked while calibration is ready, recording, or checking a gesture. Hiding the window, changing sensor configuration, pausing, losing Input Monitoring, missing samples, or delayed delivery invalidates the active capture. Existing detector settings remain unchanged unless all four gestures produce a candidate profile.

Sessions use unique local files under `~/Library/Application Support/TapThatX/Calibration/`. Each checkpoint records provenance, raw XYZ motion for that bounded window, cue timing, quality issues, and selected settings. Typed characters and audio are never recorded. Nothing is uploaded.

Schema version 4 adds the light-impulse threshold and learned pair cadence to the four-gesture flow. The replay tool retains support for earlier session shapes when they still reproduce under the current detector, but those legacy exercises are never shown in a new calibration.

## Limits

Positive gesture calibration can personalize contact amplitude and pulse shape, while the pre-cue baseline catches nearby ambient impacts. It cannot characterize every accidental movement on every surface. In particular, a movement that never occurs inside the four bounded windows cannot be learned from that session.

Physical validation still requires people to complete the flow across supported Macs, surfaces, placements, typing patterns, and accessibility settings. Automated tests cover generated gestures, missing and extra contacts, invalid pair timing, corrupt streams, persistence failures, interruption, legacy replay, and end-to-end state transitions. Generated signals do not establish real-world detection accuracy.
