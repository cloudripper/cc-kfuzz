---
name: kfuzz-yolo
description: Toggle the self-driving kernel fuzzing loop. `on` sets the YOLO caps in kfuzz/state/budget.json and starts a self-paced /loop of /cc-kfuzz:kfuzz-tick; each tick schedules the next until a cap, a halt, or `off`.
argument-hint: "on [--interval SEC] [--max-ticks N] [--allow-tcg] | off [--reason TEXT] | status"
---
<!-- adapted from cc-fuzzer skills/yolo/SKILL.md @ 478a126; see UPSTREAM.lock -->

Arguments: `$ARGUMENTS`

- `on ...`: run `kfuzz-yolo-state on <flags>`. Under TCG (`kfuzz-host accel` = `tcg`) it refuses unless `--allow-tcg` is given, and raises the interval to `kfuzz-host min_interval`; with the flag, say once that ticks are slow and that a hosted VM pauses when idle. Then start the loop with `Skill(skill: "loop", args: "/cc-kfuzz:kfuzz-tick")`: a self-paced loop with no interval, so each tick's `schedule` directive sets the next delay through `ScheduleWakeup`, which Claude Code supports only inside a self-paced `/loop`.
- `off ...`: run `kfuzz-yolo-state off <flags>`. The next tick sees YOLO off and ends the loop with `ScheduleWakeup(stop: true)`; to end it at once, press Esc while the loop waits.
- `status` (default): run `kfuzz-yolo-state status` and `kfuzz-launch status`.

The caps (interval, max ticks) are enforced by `kfuzz-yolo-state next`, not by a prompt: on a quiet tick it counts the tick and returns `schedule`, or `halt` once `max_ticks` is reached (and disables YOLO itself). A self-paced loop expires after seven days and is not restored by `--resume`; run `on` again after a resume.
