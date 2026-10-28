# cc-kfuzz

Kernel backend for [cc-fuzzer](https://github.com/cloudripper/cc-fuzzer): syzkaller campaigns, crash triage, bisection and patch validation, driven by Claude Code agents with cc-fuzzer's control-plane conventions (decide-only orchestrator, `YOLO_NEXT` directives, single-writer state scripts).

cc-kfuzz is a sibling plugin. It loads next to an unmodified, pinned cc-fuzzer, declares it as a plugin dependency, and reaches into it only through `bin/kfuzz-ccf` plus the surface listed in `UPSTREAM.lock`.

## Load

Cloud environment (environment variables, not repo settings; needs Claude Code 2.1.280+):

```text
CLAUDE_CODE_PLUGIN_DIRS=/opt/kres/plugins/cc-fuzzer:/opt/kres/plugins/cc-kfuzz
CC_FUZZER_ROOT=/opt/kres/plugins/cc-fuzzer
```

Local or KVM runner:

```bash
claude --plugin-dir ~/src/cc-fuzzer --plugin-dir ~/src/cc-kfuzz
```

Both plugins show as `@inline` in `/plugin`. Run `/cc-kfuzz:kfuzz-doctor` first.

## What works

| Command | Result |
|---|---|
| `/cc-kfuzz:kfuzz-repro <syzbot extid>` | Imports the syzbot bug, reproduces it on the right tree with vng, records a verified bundle in `kfuzz/verified/<id>/` |
| `/cc-kfuzz:kfuzz-campaign [subsystem]` | Plans config + `enable_syscalls`, builds, launches syz-manager |
| `/cc-kfuzz:kfuzz-tick` | One decision: triage, repro retry, bisect, refocus, rebuild, restart, or sleep |
| `/cc-kfuzz:kfuzz-status` | Manager, coverage, crashes, findings; no agent |
| `/cc-kfuzz:kfuzz-bisect <id>` | Cause/fix commit, gated on the reproducer flipping |
| `/cc-kfuzz:kfuzz-patch <id>` | Draft fix plus checkpatch/sparse/coccicheck/build/repro gates |
| `/cc-kfuzz:kfuzz-yolo on` | Self-driving ticks with hard caps (KVM runner) |

Reused from cc-fuzzer unchanged: `/cc-fuzzer:fuzz-review --target-root /work/linux/<dir> --sast-rules <cc-kfuzz>/rules/semgrep/kernel`, `/cc-fuzzer:delta-sweep`, `cc-fuzzer:planner-consult`, `cc-fuzzer:ops-runner`. Full map: [docs/ccf-inventory.md](docs/ccf-inventory.md).

## Layout

```
.claude-plugin/plugin.json   name cc-kfuzz, dependencies ["cc-fuzzer"]
agents/                      kfuzz-orchestrator kconfig-planner syzlang-writer kcov-analyst
                             kcrash-triager kbisector kpatch-writer kpatch-validator
skills/kfuzz-*/              campaign tick status yolo repro bisect patch doctor
bin/                         on PATH while the plugin is enabled
  kfuzz-ccf                  resolve cc-fuzzer's root
  kfuzz-compat               check UPSTREAM.lock against the installed cc-fuzzer
  kfuzz-update-current       sole writer of kfuzz/state/current.json (+ coverage.jsonl)
  kfuzz-findings             sole writer of findings/dropped/annotations and kfuzz/verified/
  kfuzz-launch               syz-manager start|stop|status|focus
  kfuzz-import-syzbot        syzbot bug -> kfuzz/syz/crashes/syzbot-<extid>/
  kfuzz-yolo-state           sole writer of kfuzz/state/budget.json
hooks/                       SessionStart drift report; kfuzz/verified/ write gate
schema/kstate-v1.md          state layout, current.json, branches, record schemas
rules/semgrep/kernel/        kernel semgrep rules for cc-fuzzer's review tier
UPSTREAM.lock                the exact cc-fuzzer surface cc-kfuzz depends on
tests/run.sh                 offline tests (no kernel, VM or network)
```

State lives in `./kfuzz/` of the working repo, never in cc-fuzzer's `fuzz/`. Verified bundles are in `kfuzz/verified/` because cc-fuzzer's write gate refuses any path with a `findings` directory component (see the inventory).

## Test

```bash
bash tests/run.sh
```

```bash
claude plugin validate --strict .
```

## Bumping cc-fuzzer

1. Run `kfuzz-compat`. `MISSING`/`PATTERN GONE` is breaking; `NOTE: upstream <file> changed` lists adapted files to review.
2. On a full clone: `git -C cc-fuzzer diff <old>..<new> -- <src>` for each `adapted=` line; port what applies by hand.
3. Update `tested_ref` and each `blob=` (`git -C cc-fuzzer hash-object <src>`), run the tests, commit.

Never edit cc-fuzzer's files: its integrity check flags the drift and reinstalls drop the edits.
