# TapThatX

<img src="docs/assets/tapthatx-app-icon.png" width="96" alt="TapThatX icon">

A native macOS menu bar app that turns deliberate double taps and knocks into actions. Built with Swift, SwiftUI and AppKit; no third-party package dependencies.

The current on-Mac detection is the working POC baseline. Command Ring supports repeated open/dismiss gestures, pointer and keyboard selection. Double-tap Lock opens the centered ring and selects Lock Mac. ChatGPT controls and tap-only ring navigation are experimental. Triple-tap recognition is disabled in production.

## Develop

Requires an Apple Silicon Mac, macOS 14+, and Xcode 16 or newer with a Swift 6 toolchain. The package deliberately uses Swift 5 language mode. Sensor support depends on the Mac's accelerometer and permissions; compiling does not establish hardware compatibility.

```sh
swift build
swift test
swift build -c release
open Package.swift
```

Open `Package.swift` in Xcode for editing and debugging. Use the bundled app for permission and helper testing; the command-line executable does not reproduce its signing identity or resources.

```sh
SIGNING_IDENTITY='Apple Development: Your Name (CERTIFICATE_ID)' \
TEAM_ID='YOURTEAMID' bash scripts/build-app.sh
open dist/TapThatX.app
```

Use a consistent signing identity and installation path to retain macOS permission grants. Supply your own certificate and team through the environment. Omitting them produces an ad-hoc development bundle that cannot use the signed helper. Building does not install or replace `/Applications/TapThatX.app`.

See [Contributing](CONTRIBUTING.md) for the development loop and [distribution](docs/DISTRIBUTION.md) for packaging.

## Try the baseline

The Permissions page opens on launch when access is missing and provides buttons for the relevant System Settings pages. Grant Accessibility and Input Monitoring when prompted on launch. Accessibility enables system actions; Input Monitoring enables suppression near typing. Direct sensor access is tried first; the signed helper may require approval in System Settings.

1. Open **Setup & Diagnostics** and keep **800 Hz** for the current detection baseline.
2. Watch the graph while tapping twice. Actions are paused while settings are visible.
3. Select **Command Ring**, enable actions and close settings to try repeated open/dismiss/open gestures.
4. After a missed interaction, immediately choose **Save last 15 seconds** from the menu.

The recent export includes bounded XYZ samples, key timestamps and diagnostic events. It saves locally under `~/Library/Application Support/TapThatX/`; it contains no typed characters or microphone recording and is never uploaded. Unsaved context is lost on quit. Calibration recordings also disable actions while recording. Simulated input always uses dry-run actions.

Lower sampling rates remain experimental; below 50 Hz is monitoring only. Reliable desk detection, left/right classification, broad hardware coverage and significant whole-app CPU savings at lower rates are not established. The graph displays motion, not proof that every peak qualifies as a gesture.

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/TapCore` | Sensor decoding, buffered input, pulse detection, gesture routing, replay and shared models |
| `Sources/TapThatX` | Menu bar app, settings, graph, command ring and action execution |
| `Sources/TapSensorHelper` | Authenticated sensor helper |
| `Sources/SensorProbe` | Read-only hardware diagnostic executable |
| `Sources/ReplayCaptures` | Labeled recording replay CLI |
| `Tests/TapCoreTests` | Deterministic regressions and curated recording fixtures |
| `Packaging` | Bundle metadata, app/menu icons and DMG artwork |
| `scripts` | Validation, app bundling and distribution |

[Detection investigation](docs/IMPULSE-INVESTIGATION.md) documents the baseline's evidence and limitations. Local prototypes, raw recordings and old builds are archived outside the repository; regression fixtures remain tracked.

## Attribution

Sensor report decoding and initialization were informed by [apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer). Its [MIT notice](docs/SENSOR_REFERENCE_LICENSE.txt) is preserved and bundled. This notice applies to the referenced work; this repository does not declare a project-wide open-source license.
