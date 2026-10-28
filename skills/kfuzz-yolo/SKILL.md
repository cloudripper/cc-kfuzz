---
name: kfuzz-yolo
description: Toggle the self-driving kernel fuzzing loop. `on` sets the YOLO caps in kfuzz/state/budget.json and runs a tick; quiet ticks chain the next one via ScheduleWakeup until a cap, a halt, or `off`. Intended for the KVM runner.
argument-hint: "on [--interval SEC] [--max-ticks N] [--allow-tcg] | off [--reason TEXT] | status"
---
<!-- adapted from cc-fuzzer skills/yolo/SKILL.md @ 478a126; see UPSTREAM.lock -->

Arguments: `$ARGUMENTS`

- `on ...`: run `kfuzz-yolo-state on <flags>`. Under TCG (`kfuzz-host accel` = `tcg`) it refuses unless `--allow-tcg` is given, and raises the interval to `kfuzz-host min_interval`; with the flag, say once that ticks are slow and that a hosted VM pauses when idle. Then run `/cc-kfuzz:kfuzz-tick`.
- `off ...`: run `kfuzz-yolo-state off <flags>`. Any pending wakeup will find YOLO off and stop.
- `status` (default): run `kfuzz-yolo-state status` and `kfuzz-launch status`.

The caps (interval, max ticks) are enforced by `kfuzz-yolo-state next`, not by a prompt: on a quiet tick it counts the tick and returns `schedule`, or `halt` once `max_ticks` is reached (and disables YOLO itself).
