---
name: kfuzz-tick
description: Run one kernel-fuzzing decision tick for a cc-kfuzz campaign. Refreshes kfuzz/state/current.json, asks kfuzz-orchestrator for a decision, and performs exactly one action (dispatch a specialist, run a lever, schedule, or stop). Use for manual ticks and as the unit /cc-kfuzz:kfuzz-yolo loops.
argument-hint: "(no arguments)"
---
<!-- adapted from cc-fuzzer skills/tick/SKILL.md @ 478a126; see UPSTREAM.lock -->

One tick. The orchestrator decides; this main thread performs. cc-kfuzz agents carry no `Agent` tool, so every dispatch happens here, one per tick.

The `kfuzz-watch` plugin monitor runs in every session and stays silent until a `kfuzz/` campaign exists here: new crashes, a syz-manager exit, or a finished kernel build arrive as notifications. Treat each such notification as a request to run this skill again.

## Steps

1. Run `kfuzz-update-current` (bare command, cc-kfuzz `bin/` is on PATH). If this thread cannot run Bash, dispatch `cc-fuzzer:ops-runner` in the foreground to run it.
2. Dispatch the orchestrator **in the foreground** (`run_in_background: false`): its directive is the next step, and subagents started from the main conversation otherwise default to the background. Minimal prompt, no state pasted:
   `Agent(subagent_type: "cc-kfuzz:kfuzz-orchestrator", run_in_background: false, prompt: "Decide one tick. Campaign root: <abs path of cwd>.")`
3. Parse the last non-blank line of its reply. It is a `YOLO_NEXT:` directive in cc-fuzzer's grammar (`cat "$(kfuzz-ccf STATE_SCHEMA.md)"`, section "The `YOLO_NEXT:` next-action directive", if you have not read it this session).
4. Perform it:

| Directive | Action |
|---|---|
| `dispatch agent=<type> args="<a>"` | `Agent(subagent_type: "<type>", prompt: "<a>. Campaign root: <abs path>.")`. Foreground for `kcrash-triager`, `kconfig-planner`, `kcov-analyst`, `syzlang-writer` (minutes to an hour). Background for `kbisector` (hours): report that it started and end the tick; its completion notification carries the `BISECT_RESULT` line, and the next tick picks up from state. Read each specialist's `*_RESULT:` last line. |
| `run script="<cmd>"` | Run `<cmd>` with Bash (or via `cc-fuzzer:ops-runner`). Levers such as `kres-build -d` and `kfuzz-launch start` detach and return at once. |
| `schedule delay=<n> prompt=<p>` | Inside a self-paced `/loop` (YOLO): `ScheduleWakeup(delaySeconds=<n>, prompt=<the loop's prompt>, reason=<reason>)`. Outside a loop: report the suggested delay and stop; `kfuzz-watch` notifications bring the next tick. |
| `halt` / `done` / `inactive` | Stop. Inside a self-paced `/loop`, end it with `ScheduleWakeup(stop: true)` for `halt` and `inactive`; for `done`, schedule the next iteration at `kfuzz-host min_interval`. Surface the reason and the next human step. |

5. Report: branch, action taken, the specialist's result line if any, next delay.

## Missing directive

If the orchestrator's reply has no `YOLO_NEXT:` line, do not re-dispatch it. Run `kfuzz-yolo-state next` and act on the line it prints.

## Stall

Redirect a stalled specialist with `SendMessage` first; re-dispatch with a fresh minimal prompt only if that fails. Never do the specialist's work on this thread.

## Hosted cloud VM

The VM pauses when idle, so long loops do not survive there. Tick by hand, on `kfuzz-watch` notifications, or with `/loop`. `/cc-kfuzz:kfuzz-yolo on --allow-tcg` works there too while the session stays active.
