# CNN reassessment after the desk-detection fixes

A small temporal CNN is a reasonable experiment. It is not yet justified as a production replacement, and it will not repair sensor gaps, typing vetoes, gesture deadlines or sleeping hardware. Those are separate software and lifecycle concerns. The pre-CNN changes now expose both detector signals, correct reproducible timing/sensitivity faults, and require negative examples plus fresh calibration verification.

## Proposed role

Use a small 1D CNN to score short XYZ motion windows around candidate contacts, before the existing single/double gesture router. Its main task is intended contact versus incidental movement; light tap and knock may be auxiliary labels, but both produce the same accepted-contact event. Keep command execution, typing suppression, sleep handling and gesture pairing deterministic.

Compare it with the corrected detector and a small feature-based classifier using onset slope, pulse width, decay, band energy and axis relationships. A CNN earns inclusion only if it improves held-out desk recordings at the same false-action rate and acceptable latency. An RNN is an optional benchmark, not the starting dependency: bounded local impact windows do not obviously require recurrent state.

An initial engineering experiment could use 160–240 ms windows, a little pre-contact context, and two or three small temporal convolution layers. Window length and any resampling/filtering must be selected from measured recordings, not copied blindly. Use gravity-removed XYZ data with physical amplitude information retained; normalizing every window to unit amplitude would erase one useful cue. Keep raw timestamps and axes for replay.

The candidate gate must have high recall. A classifier cannot rescue contacts discarded by the current rise-rate or amplitude checks before it sees them. Measure candidate recall separately; train and assess a permissive proposal gate alongside the classifier. Multiple windows from one ringing impact must become one event. Account for observation-window delay as well as inference time.

This is motivated by [TapNet, CHI 2021](https://research.google/pubs/tapnet-the-design-training-implementation-and-applications-of-a-multi-task-learning-cnn-for-off-screen-mobile-input/), which demonstrates learned off-screen tap recognition from phone inertial sensors. Its accelerometer/gyroscope inputs, training population and phone mechanics differ from this app's Mac accelerometer-only desk signal. Its results are evidence of feasibility, not a transferable Mac accuracy estimate. The [paper](https://arxiv.org/html/2102.09087v1) also makes the distinction between candidate detection, observation time and classification cost useful for this design.

## Private data collection

Your no-command day is useful negative data. Use the computer normally, including typing, clicking, resting arms, moving the chair and placing objects. “No tapping” should mean no deliberate commands, not carefully avoiding ordinary desk contacts. Otherwise the negatives will be unusually clean.

Keep collection in a private development recorder, outside the shipping app, as requested. No such all-day recorder or CNN has been added in this change. The existing 15-second diagnostic buffer is insufficient for this experiment. A recorder should stream bounded chunks to disk, retain time/rate/gap metadata and setup labels, and run without triggering actions. Do not label negatives from the detector's own rejected events: save broad background context and independently identify any accidental intentional-command periods.

Collect intentional examples separately: light taps and knocks on the desk with a closed, externally displayed Mac; light taps and knocks on the Mac and desk with the Mac open. Include single taps used inside the ring, unequal pairs, natural cadence variation, several distances/positions, and different recording sessions. Both target gestures need coverage; light-tap positives alone are insufficient. Deliberately collect hard negatives such as a mug placement or leg bump even if they did not happen during the passive day.

One person's day is a useful personal prototype. It is not evidence of reliability across different desks, Mac models or users. For a general release, collect multiple people, desks, devices and days in both supported setups. Lap data is not a target class for this version.

Split complete days/sessions and setups before creating overlapping windows. Reserve later sessions for testing; for broader claims reserve users/devices/desks too. Do not randomly divide neighboring windows across train and test. Research on [overlapping-window evaluation in inertial recognition](https://pmc.ncbi.nlm.nih.gov/articles/PMC6891351/) shows how dependent windows can inflate apparent generalization. This motivates the grouped split, not a specific dataset-size requirement.

## Decision criteria

Score the whole continuous pipeline, including the ring state machine, rather than window classification accuracy alone. Report candidate recall, contact recall by gesture/setup, pair recall, false contacts, false ring advances and false actions per hour, plus median and tail latency. Preserve natural class imbalance in the evaluation streams; balanced training batches do not imply balanced real use.

Choose the acceptable false-action rate and recall target before threshold tuning. Tune only on validation sessions; use untouched sessions for the final comparison. Run the candidate model in a private action-free shadow mode first and inspect the disagreements. A quiet day alone does not establish a very low long-term false-positive rate.

If a compact feature model matches the CNN, keep the simpler model. If both fail on overlapping intentional and accidental signals, investigate richer context or a more distinctive command rhythm rather than increasing model size. On-device deployment comes after this evidence; model runtime availability is not the main uncertainty.
