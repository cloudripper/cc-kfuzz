---
name: kbisector
description: Finds the cause commit (and, for an older tree, the fix commit) of one verified kernel finding by git bisect with its C reproducer. Gated on the reproducer flipping at the reported commit. Use on the bisect branch or /cc-kfuzz:kfuzz-bisect.
model: sonnet
effort: high
tools: Read, Bash, Write
---

You bisect ONE finding (args: `id=<kf-id> [mode=cause|fix] [good=<ref>] [bad=<ref>]`).

## Rules

- Records only through `kfuzz-findings annotate|attach`. Scratch: `kfuzz/work/bisect-<id>/`.
- First `kfuzz-findings annotate <id> bisect_status running`.
- Needs full history: if `git -C /work/linux rev-parse --is-shallow-repository` is `true`, stop with `bisect_status skipped` and say "refetch with KRES_DEPTH=0 kres-fetch-kernel" (about 5 GB; ask before doing it).
- Every build is detached (`kres-build -d <out>`; poll `<out>/build.status`). Use a dedicated out dir `/work/out/bisect` with the finding's config (`kfuzz/verified/<id>/` meta `config`, from `kfuzz/configs/`), and keep only it plus the campaign dir (disk is tight).

- Wait on detached work (`kres-build -d`, syz-repro, vng runs) with the Bash tool's `run_in_background` on `kfuzz-wait <log or status file> '<regex>' <seconds at KVM speed>` (e.g. `kfuzz-wait <out>/build.status '^(ok|FAILED)'`), which notifies you when it exits; never a foreground `sleep` loop. Detach with `setsid nohup` anything that must outlive you, since your own background commands stop when your run ends.

## Test step (`kfuzz/work/bisect-<id>/test.sh`, used by `git bisect run`)

1. `make olddefconfig` with the finding's config, build bzImage; build failure → exit 125 (skip).
2. Boot with `kfuzz-vng --timeout 300 -r <bzImage> --user root -- "timeout $((120*$(kfuzz-host timeout_mult))) ./repro"` and run `repro` (static, from the bundle's `repro.c`) three times.
3. Crash with the same class and top frame → exit 1 (bad); clean → exit 0 (good); boot failure → exit 125.

## Steps

1. **Gate:** run the test at `bad` (default: the finding's `kernel_ref`) and confirm it is bad. If not, `bisect_status failed`, reason "does not reproduce at reported commit".
2. Pick `good`: the last release tag before `bad` that tests good (try up to three older tags).
3. `git bisect start <bad> <good> && git bisect run kfuzz/work/bisect-<id>/test.sh` (detached, log to `bisect.log`). Cap at 20 steps. Under TCG (`kfuzz-host accel`) a step is a build plus three slow boots, roughly 20-40 minutes: state the estimate (steps ≈ log2 of the commit range) up front, and prefer `kres-nix kernel` builds for refs you will test more than once.
4. Confirm the result: the culprit tests bad, its parent tests good. Otherwise `failed`.
5. `kfuzz-findings attach <id> kfuzz/work/bisect-<id>/bisect.log`, `kfuzz-findings annotate <id> cause_commit <sha>` (or `fix_commit` in fix mode), then `bisect_status ok`.
6. `git bisect reset` always, even on failure.

## Output

Last line: `BISECT_RESULT: {"id":"<id>","status":"ok|failed|skipped","cause_commit":"<sha or empty>","fix_commit":"<sha or empty>"}`
