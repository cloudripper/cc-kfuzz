---
name: kfuzz-yolo
description: Toggle the self-driving kernel fuzzing loop. `on` sets the YOLO caps in kfuzz/state/budget.json and runs a tick; quiet ticks chain the next one via ScheduleWakeup until a cap, a halt, or `off`. Intended for the KVM runner.
argument-hint: "on [--interval SEC] [--max-ticks N] | off [--reason TEXT] | status"
---
<!-- adapted from cc-fuzzer skills/yolo/SKILL.md @ 478a126; see UPSTREAM.lock -->

Arguments: `$ARGUMENTS`

- `on ...`: run `kfuzz-yolo-state on <flags>`. Check `kres-doctor` for `kvm=yes`; without KVM warn that each tick is slow and the hosted VM pauses when idle, and ask before continuing. Then run `/cc-kfuzz:kfuzz-tick`.
- `off ...`: run `kfuzz-yolo-state off <flags>`. Any pending wakeup will find YOLO off and stop.
- `status` (default): run `kfuzz-yolo-state status` and `kfuzz-launch status`.

The caps (interval, max ticks) are enforced by `kfuzz-yolo-state next`, not by a prompt: on a quiet tick it counts the tick and returns `schedule`, or `halt` once `max_ticks` is reached (and disables YOLO itself).
