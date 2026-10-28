---
name: kfuzz-tick
description: Run one kernel-fuzzing decision tick for a cc-kfuzz campaign. Refreshes kfuzz/state/current.json, asks kfuzz-orchestrator for a decision, and performs exactly one action (dispatch a specialist, run a lever, schedule, or stop). Use for manual ticks and as the unit /cc-kfuzz:kfuzz-yolo chains.
argument-hint: "(no arguments)"
---
<!-- adapted from cc-fuzzer skills/tick/SKILL.md @ 478a126; see UPSTREAM.lock -->

One tick. The orchestrator decides; this main thread performs. No subagent can dispatch another, so every dispatch happens here.

## Steps

1. Run `kfuzz-update-current` (bare command, cc-kfuzz `bin/` is on PATH). If this thread cannot run Bash, dispatch `Agent(subagent_type: "cc-fuzzer:ops-runner", prompt: "Run kfuzz-update-current and report its output.")`.
2. Dispatch the orchestrator with a minimal prompt, no state pasted:
   `Agent(subagent_type: "cc-kfuzz:kfuzz-orchestrator", prompt: "Decide one tick. Campaign root: <abs path of cwd>.")`
3. Parse the last non-blank line of its reply. It is a `YOLO_NEXT:` directive in cc-fuzzer's grammar (`cat "$(kfuzz-ccf STATE_SCHEMA.md)"`, section "The `YOLO_NEXT:` next-action directive", if you have not read it this session).
4. Perform it:

| Directive | Action |
|---|---|
| `dispatch agent=<type> args="<a>"` | `Agent(subagent_type: "<type>", prompt: "<a>. Campaign root: <abs path>.")`. Read its `*_RESULT:` last line. Under YOLO, re-enter at step 1; manually, report and stop. |
| `run script="<cmd>"` | Run `<cmd>` with Bash (or via `cc-fuzzer:ops-runner`). Same re-entry rule. |
| `schedule delay=<n> prompt=<p>` | `ScheduleWakeup(delaySeconds=<n>, prompt="<p>", reason=<reason>)`. |
| `halt` / `done` / `inactive` | Stop. Do not schedule. Surface the reason and the next human step. |

5. Report: branch, action taken, the specialist's result line if any, next delay.

## Missing directive

If the orchestrator's reply has no `YOLO_NEXT:` line, do not re-dispatch it. Run `kfuzz-yolo-state next` and act on the line it prints.

## Stall

Redirect a stalled specialist with `SendMessage` first; re-dispatch with a fresh minimal prompt only if that fails. Never do the specialist's work on this thread.

## Hosted cloud VM

The VM pauses when idle, so long self-chained ticks do not survive there. Tick by hand or with `/loop`; keep `/cc-kfuzz:kfuzz-yolo` for the KVM runner.
