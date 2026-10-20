# Detection and wheel plan

Detection planning has been replaced by [the first-principles calibration design](DETECTION-CALIBRATION.md). Old capture-based conclusions and dataset requirements have been withdrawn. The independent wheel plan below is retained.

## 3. Smooth wheel animation without the long wraparound

### Problem statement

The wheel should move smoothly between selections. Reaching the final item and advancing to the first should cross the adjacent boundary, not sweep backward through the rest of the wheel. Working interpretation: retain circular navigation; fix its visual travel rather than stop navigation at the last item. Polish should include rapid input, direction changes, opening, selection confirmation, and dismissal.

### Existing evidence and likely cause

`Sources/TapThatMac/RadialPanelController.swift` rotates a highlighted `Sector(index: 0)` by the selected command's normalized index angle. There are currently seven commands. The last-to-first change is approximately 308.57° → 0°; numeric interpolation can travel backward by 308.57° instead of forward by 51.43°. This is a code-based diagnosis; it has not been verified in a live recording during this planning task.

`Command.advancing` already wraps logical selection correctly. Selection changes originate in keyboard/tap advancement, hover, pointer confirmation, and automatic action presentation. A broad selection-driven spring animates the view; automatic actions use delayed callbacks, and commit uses a separate press delay guarded by an opening token.

### Proposed solution, in order

1. **Separate selection from rotation.** Keep the selected command as the source of truth for actions and accessibility. Maintain a continuous visual target angle for the outline. Forward navigation adds one sector sweep; reverse navigation subtracts one. Example with seven commands: 308.57° → 360° → 411.43°. Do not normalize to zero during an active animation.
2. **Make navigation intent explicit.** Route all selection changes through a small focused method. Sequential navigation preserves its requested direction across the boundary. Hover, pointer choice, and automatic selection use the nearest equivalent target angle. For a canonical target angle, choose a delta in [-180°, 180°], with a documented deterministic tie rule. Derive sweep from command count rather than hardcoding seven.
3. **Handle interrupted motion.** New input updates logical selection immediately and retargets the active animation continuously; do not queue a delayed animation per input. Test rapid multi-step movement and reversal. Direct jumps should start from the currently presented angle where the animation mechanism permits; if a target-only approach causes visible detours under interruption, use the smallest supported presentation-state solution. Normalize accumulated angles only while hidden or with an equivalent nonanimated rebase that cannot cause a jump.
4. **Polish locally.** Scope animation to the outline, selected icon treatment, and opening/press effects instead of attaching unrelated changes to a single broad spring. Start by evaluating roughly 180–240 ms settling with little overshoot; choose final values through physical preview. Keep labels legible and avoid unnecessary layout or backdrop reconstruction. Audit central symbol replacement and opening animation under Reduce Motion; preserve Reduce Transparency.
5. **Preserve command correctness.** Keep the existing single/double routing window and opening-token cancellation. Animation completion must never independently trigger an action after dismissal, focus loss, reset, or reopening. Ensure a direct pointer choice confirms the intended command even when the highlight is in transit. If adding a short exit fade, make the panel noninteractive immediately and invalidate callbacks before visual teardown; do not alter command dispatch timing incidentally.
6. **Verify both geometry and perception.** Test circular angle math separately; review the actual ring at normal and high refresh rates where available. Record preview with keyboard/pointer input first to isolate rendering from sensor delays, then test physical taps. Do not claim smoothness from a passing unit test alone.

### Acceptance

- Last → first and first → last each travel exactly one sector in the requested direction. Repeated complete revolutions never produce a reverse full-wheel sweep.
- Direct selection uses the shortest arc; test the half-turn tie policy with an even test command count.
- Rapid advancement, hover during motion, direction reversal, and automatic presentation settle on the correct command without snapping, delayed backlog, or stale state on reopen.
- Escape, focus loss, lifecycle reset, and dismissal during commit execute no pending command. Successful confirmation executes exactly once.
- Reduce Motion removes spatial travel and unnecessary symbol motion; selection remains clear. Reduce Transparency continues working.
- Inspect frame pacing during repeated preview interaction; report hardware, refresh rate, and observed stutters. Distinguish the intentional 450 ms single-tap pairing wait from animation latency; changing that wait is outside this task.

### Executable prompt 3 — wheel motion and wraparound

```text
In this repository, implement only section 3 of
 docs/DETECTION-AND-WHEEL-PLAN.md. Follow AGENTS.md and preserve unrelated edits.
Inspect RadialPanelController.swift, Command.advancing, AppModel ring routing,
and existing tests. Verify current SwiftUI/AppKit animation APIs through
Context7 if available, otherwise official Apple documentation.
Fix wraparound using continuous visual rotation separate from logical command
selection. Preserve direction for tap/keyboard steps; use nearest-angle travel
for hover, pointer, and automatic selection. Centralize selection updates in a
small method. Handle rapid retargeting, reversal, and reopen without animation
backlogs or angle normalization jumps. Polish scoped highlight/open/press
animations and assess dismissal. Preserve ring appearance, command ordering,
action mappings, gesture timing, accessibility, and cancellation semantics.
Add meaningful tests for angle wrapping, multiple revolutions, shortest paths,
ties, and pending-command cancellation where testable. Run swift build and
swift test. Preview actual motion with keyboard/pointer then sensor input;
check Reduce Motion/Transparency, rapid inputs, automatic actions, Escape,
focus loss, and reopen. Do not execute destructive commands merely to test
animation; use preview or a test action recorder. If visual/hardware validation
is unavailable, report it explicitly instead of claiming buttery smoothness.
Update this plan with implementation details and validation evidence. Do not
change detection or its thresholds in this task.
```

