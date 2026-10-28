# cc-fuzzer inventory (reuse map for cc-kfuzz)

Source: `cloudripper/cc-fuzzer` @ `478a12616bfcc8650d36d9ec2fbcd466f68d6e2f` (v0.49.1), read-only.
Classes: **reuse-as-is** (cc-kfuzz calls it unchanged), **adapt** (pattern copied, content rewritten; provenance in `UPSTREAM.lock`), **kernel-replace** (kernel needs a different implementation), **n/a**.

## Facts the design depends on

| Item | Value | Source |
|---|---|---|
| Plugin manifest name | `cc-fuzzer` | `.claude-plugin/plugin.json` |
| Manifest location | `.claude-plugin/plugin.json` (not repo root); `.claude-plugin/marketplace.json` lists one plugin, `source: "./"` | |
| Version | `0.49.1` | |
| Root marker used by `kfuzz-ccf` | `STATE_SCHEMA.md` + manifest name | |
| Core CLI | `bin/cc-fuzzer` → `python3 -m cc_fuzzer_core` (src/ on PYTHONPATH via `scripts/_lib/root.sh`) | |
| Root resolution in its scripts | `$CC_FUZZER_ROOT`, then `$CLAUDE_PLUGIN_ROOT`, then self | `scripts/_lib/root.sh` |
| Tested Claude Code | 2.1.285 (contract floor); Grep/Glob tools absent on Linux | `claude-code.contract.json` |

### `YOLO_NEXT` grammar (STATE_SCHEMA.md, "The `YOLO_NEXT:` next-action directive")

One directive per line, the literal last non-blank line of the orchestrator's return:

```
YOLO_NEXT: dispatch agent=<agent-type> args="<args>" reason="<why>"
YOLO_NEXT: run script="<script + args>" reason="<why>"
YOLO_NEXT: schedule delay=<n> prompt=<p> reason="<why>"      # delay clamped to [60, 3600]
YOLO_NEXT: orchestrator reason="<why>"
YOLO_NEXT: halt reason="<why>"
YOLO_NEXT: done reason="<why>"
YOLO_NEXT: inactive
```

Rules: the orchestrator decides only (no `Agent` tool in any agent); the main thread performs the directive; no subagent calls `ScheduleWakeup`.

### Scripts that write `fuzz/state/` files

| Writer | Files |
|---|---|
| `scripts/update-current.sh` | `current.json` (sole writer; orchestrator reads only this on WARM ticks) |
| `scripts/findings.sh` → `cc-fuzzer findings` | `findings.jsonl` (sole writer; append-only, in-place only for dedup fields) |
| `scripts/events.sh` | `events.jsonl` |
| `hooks/ledger-append.sh` (SubagentStop) | spend ledger in `events.jsonl` (`agent_call`) |
| `scripts/yolo-state.sh` | `fuzz-config.json:yolo` |
| `scripts/harness-set.sh` | `fuzz-config.json` harnesses |
| `scripts/write-harness-built.sh` | `harness-built.json` |
| `scripts/snapshot-coverage.sh`, `tick-coverage-roundup.sh`, `ceiling-probe.sh`, `find-delta-targets.sh`, `tick-briefing.sh` | `snapshots/*.json` |
| `scripts/preflight.sh` | `preflight.json` |
| `scripts/capture-nix-env.sh`, `nix-env-reconcile.sh` | `nix-env.json`, `nix-environment-issues.json` |
| `scripts/dictionaries.sh` | `harness-built.json:dict_files` |
| `scripts/campaign-header.sh` (caller redirects) | `header.txt` |
| `scripts/yolo-route.sh` | `next-directive.txt` |
| `scripts/reverify-after-rebuild.sh` | via `findings.sh stale-mark` |
| `scripts/detect-crashes.sh` (PostToolUse) | stages into `fuzz/crashes/new/` |

### Nix flake inputs (`flake.nix`)

| Input | URL | Cloud status |
|---|---|---|
| `nixpkgs` | `github:NixOS/nixpkgs/release-25.11` | 403 when the repo is not attached; override to `path:/opt/kres/nix` |
| `llm-agents` | `github:numtide/llm-agents.nix/7c2b15b...` (provides `claude-code`) | 403 as well; needs its own override (a local stub flake exposing `packages.x86_64-linux.claude-code`) |
| substituter | `https://cache.numtide.com` | must be allowed in network settings, else builds from source |

cc-fuzzer evaluates `import nixpkgs { inherit system; }`, so an override target must also be importable as a plain path. The kres setup script writes `/opt/kres/nix/default.nix`, which imports the tarball pinned in `flake.lock`. So `nix develop <cc-fuzzer> --override-input nixpkgs path:/opt/kres/nix` resolves nixpkgs; `llm-agents` still blocks it. cc-fuzzer's nix backend is n/a for kernel work, so this is only needed for userspace targets.

### Global hooks that also fire on cc-kfuzz work (both plugins loaded)

| Hook | Effect on cc-kfuzz | Action taken |
|---|---|---|
| `gate-findings.sh` (PreToolUse Write/Edit/MultiEdit/Bash) | **Denies any write whose path or command matches `(^|/)findings(/|$)`**, any directory prefix, not just `fuzz/` (`src/cc_fuzzer_core/gate.py:_dir_re`). Verified: a Write to `kfuzz/findings/x/report.txt` is refused. | Verified bundles live in **`kfuzz/verified/<id>/`**, not `kfuzz/findings/`. `UPSTREAM.lock` greps `FINDINGS_DIR = "findings"` so a change in the gate is reported. cc-kfuzz ships its own gate for `kfuzz/verified/`. |
| `detect-crashes.sh` (PostToolUse Bash) | No-op outside `fuzz/` (tested). | none |
| `gate-verify-build.sh` (PreToolUse Bash) | Allows syz-repro/syz-prog2c commands (tested). | none |
| `ledger-append.sh` (SubagentStop) | Exits 0, writes nothing without a `fuzz/` campaign (tested). | cc-kfuzz keeps its own `kfuzz/state/ledger.json` |
| `dedup-calls.sh` (PreToolUse + PostToolBatch) | Denies a repeated identical call in one response. Engine-agnostic. | none |
| `env-check.sh` (SessionStart) | Integrity check of cc-fuzzer itself. | `kfuzz-doctor` also runs `scripts/integrity-check.sh` |

## Agents (16)

| Agent | Model | Class | Notes for cc-kfuzz |
|---|---|---|---|
| `code-reviewer` | sonnet | reuse-as-is | Static review works on kernel C; feed kernel semgrep rules via `--sast-rules` |
| `code-reviewer-deep` | opus | reuse-as-is | Tier 3 taint pass |
| `planner-consult` | opus | reuse-as-is | Small briefing in, stay/redirect out; briefing file is ours |
| `ops-runner` | haiku | reuse-as-is | Runs bash levers when the main thread cannot (ctxctl); `kfuzz-tick` falls back to it |
| `query-analyst` | sonnet | reuse-as-is | Hypothesis-driven semgrep/CodeQL query; works on kernel trees |
| `fuzz-orchestrator` | sonnet | adapt | Keep decide-only + `YOLO_NEXT`; swap WARM branches for kernel ones → `kfuzz-orchestrator` |
| `crash-triager` | opus | adapt | Keep filter/replay/realistic-repro pipeline; ASan replay → syz-repro/prog2c/vng → `kcrash-triager` |
| `campaign-planner` | opus | adapt | Plan doc pattern → `kconfig-planner` (subsystem, config profile, `enable_syscalls`) |
| `reporting-agent` | opus | adapt (later) | Re-run every repro and render report; milestone after triage |
| `poc-builder` | opus | adapt (later) | Impact characterization; kernel version deferred |
| `harness-writer` | sonnet | kernel-replace | Kernel config + syzlang → `syzlang-writer`, `kconfig-planner` |
| `seed-generator` | haiku | kernel-replace | syzkaller corpus/`syz-db`; syzlang descriptions do this job |
| `mutator` | haiku | kernel-replace | syzkaller mutates from descriptions |
| `coverage-analyst` | sonnet | kernel-replace | KCOV via syz-manager `/cover`, `/rawcover`, `/metrics` → `kcov-analyst` |
| `concolic-executor` | haiku | n/a | SymCC |
| `nix-builder` | sonnet | n/a | nix backend |

## Skills (24)

| Skill | Class | cc-kfuzz counterpart |
|---|---|---|
| `fuzz-review` | reuse-as-is | call `/cc-fuzzer:fuzz-review --target-root /work/linux/<dir> --sast-rules <cc-kfuzz>/rules/semgrep/kernel` |
| `delta-sweep` | reuse-as-is | kernel diffs (stable backports, `git range`) |
| `delta` | adapt (later) | needs `fuzz/` campaign; kernel version would feed `enable_syscalls` |
| `campaign` | adapt | `kfuzz-campaign` |
| `tick` | adapt | `kfuzz-tick` |
| `yolo` | adapt | `kfuzz-yolo` |
| `fuzz-status` | adapt | `kfuzz-status` |
| `doctor` | adapt | `kfuzz-doctor` |
| `triage` | adapt | `kfuzz-repro` (one crash/syzbot bug through the triager) |
| `report` | adapt (later) | |
| `poc` | adapt (later) | |
| `fuzz-plan` | adapt | folded into `kfuzz-campaign` via `kconfig-planner` |
| `validate` | adapt (later) | `kfuzz-doctor` validates `kstate/v1` |
| `fuzz-run`, `fuzz-stop`, `resume-campaign`, `fuzz-reset` | kernel-replace | `kfuzz-launch start|stop|status` |
| `harness`, `seed`, `coverage`, `dictionaries` | kernel-replace | `syzlang-writer`, `kcov-analyst` |
| `concolic`, `nix-build`, `nix-cleanup` | n/a | |
| (none) | new | `kfuzz-bisect`, `kfuzz-patch` |

## Scripts (53) and hooks (6)

| Script | Class | Notes |
|---|---|---|
| `integrity-check.sh` | reuse-as-is | `kfuzz-doctor` runs it against cc-fuzzer |
| `blame-finding.sh` | reuse-as-is | git blame provenance; works on `/work/linux` |
| `check-seed-safety.sh` | reuse-as-is | destructive-payload scan, fine for syz programs |
| `gen-manifest.sh`, `enforce-readonly.sh`, `claude-code-contract.py`, `env-check.sh`, `doctor.sh` | reuse-as-is | upstream self-maintenance; read-only for us |
| `update-current.sh` | adapt | `bin/kfuzz-update-current` |
| `findings.sh` | adapt | `bin/kfuzz-findings` |
| `events.sh` | adapt (later) | event log |
| `status.sh` | adapt | `kfuzz-status` skill |
| `yolo-state.sh`, `yolo-route.sh` | adapt (later) | YOLO config/caps; kernel needs KVM runner first |
| `tick-briefing.sh` | adapt (later) | briefing for `planner-consult` |
| `campaign-header.sh` | adapt (later) | header digest |
| `check-campaign-state.sh` | adapt | folded into `kfuzz-update-current` (`campaign: none|stopped|running`) |
| `cross-ref-findings.sh`, `cve-context-build.sh`, `cve-lookup.py` | adapt (later) | CVE intel keyed by kernel subsystem |
| `run-fuzzer.sh`, `launch-fuzzer-slot.sh`, `stop-fuzzer.sh`, `kill-harness-processes.sh`, `check-slot-liveness.sh`, `robust-fuzz.sh` | kernel-replace | `kfuzz-launch` over `kres-syz-up` |
| `detect-crashes.sh`, `is-crash.sh`, `corpus-quarantine.sh` | kernel-replace | syz-manager owns `crashes/<hash>/` |
| `build-poc-repro.sh`, `reverify-after-rebuild.sh` | kernel-replace | syz-prog2c + vng |
| `snapshot-coverage.sh`, `tick-coverage-roundup.sh`, `ceiling-probe.sh` | kernel-replace | `/metrics` time series in `kfuzz-update-current` |
| `preflight.sh` | kernel-replace | `kres-doctor` + `kfuzz-doctor` |
| `harness-set.sh`, `write-harness-built.sh`, `dictionaries.sh`, `extract-cmplog-dict.sh`, `find-delta-targets.sh`, `oracle-smoke-test.sh`, `netem-harness.sh`, `reset-campaign.sh`, `code-review-run.sh` | kernel-replace or upstream-internal | |
| `install-symcc.sh`, `build-symcc-target.sh`, `run-concolic.sh`, `nix-build.sh`, `nix-cleanup.sh`, `capture-nix-env.sh`, `nix-env-reconcile.sh`, `campaign-init.sh` | n/a | |
| hooks: `gate-findings.sh` | reuse-as-is (pattern adapted) | see global hooks table; cc-kfuzz `hooks/gate-verified.sh` mirrors it |
| hooks: `dedup-calls.sh`, `ledger-append.sh`, `gate-verify-build.sh`, `sweep-gate.sh` | reuse-as-is / n/a | fire globally; harmless for kfuzz |

## Rules

| Path | Class |
|---|---|
| `rules/semgrep/c-cpp-memory.yml`, `toctou.yml` | reuse-as-is (generic C) |
| `rules/query-pack/{semgrep,codeql}` | reuse-as-is; kernel rules added in cc-kfuzz `rules/semgrep/kernel/` |
