---
name: kfuzz-campaign
description: Start or resume a kernel fuzzing campaign in ./kfuzz - plan (subsystem, config, enable_syscalls), build the kernel, launch syz-manager, then tick. Auto-detects state.
argument-hint: "[subsystem or guidance text] [--fresh]"
---

Arguments: `$ARGUMENTS`

1. `/cc-kfuzz:kfuzz-doctor` checks 1-3 only. Stop on a FAIL.
2. If arguments contain guidance text and `kfuzz/guidance.md` does not exist, write it (this is operator guidance; agents read it, never write it).
3. If there is no `kfuzz/plan.md` or `--fresh` was given: dispatch `Agent(subagent_type: "cc-kfuzz:kconfig-planner", run_in_background: false, prompt: "mode=fresh. Campaign root: <abs cwd>.")`.
4. Loop `/cc-kfuzz:kfuzz-tick` while the directive is a `run` or `dispatch` of setup work (`kres-build -d`, `kfuzz-launch start`), at most 5 times. Kernel builds are detached: when the tick reports `done reason="kernel build in progress"`, tell the operator to re-run this skill or `/cc-kfuzz:kfuzz-tick` later (or `/loop 10m /cc-kfuzz:kfuzz-tick`).
5. Report `/cc-kfuzz:kfuzz-status`.

Without KVM the campaign runs under TCG (`kfuzz-host`; force it with `KFUZZ_ACCEL=tcg`). Say so once with the numbers from `kfuzz-host` (VMs, x10 slowdown), keep the plan narrow, and note that the hosted VM pauses when the session is idle, so syz-manager only runs while the session is active. Long broad campaigns belong on the KVM runner.
