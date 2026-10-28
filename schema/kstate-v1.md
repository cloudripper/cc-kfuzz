# kstate/v1

cc-kfuzz state, kept apart from cc-fuzzer's `fuzz/` so cc-fuzzer's validators never see foreign fields. Shapes mirror `fuzz/state/` (STATE_SCHEMA.md) so a later merge into an upstream engine seam is mechanical.

Root: `$KFUZZ_DIR` (default `$PWD/kfuzz`).

## Layout

```
kfuzz/
  plan.md                    kconfig-planner (campaign strategy; archived to docs/plan-<ts>.md on revise)
  guidance.md                operator steering (human-written; agents read, never write)
  docs/                      operator notes, archived plans
  configs/<profile>.config   exact kernel .config the manager ran with (kfuzz-launch start copies it)
  syz/                       syz-manager workdir: manager.cfg manager.pid manager.log crashes/<hash>/ corpus.db
  work/<hash>/               triage scratch (report.txt repro.syz repro.c decoded.txt run logs)
  verified/<id>/             verified bundle; written ONLY by kfuzz-findings (hooks/gate-verified.sh enforces)
  state/
    current.json             written ONLY by kfuzz-update-current; the one file the orchestrator reads per tick
    findings.jsonl           written ONLY by kfuzz-findings add
    dropped_crashes.jsonl    written ONLY by kfuzz-findings drop|dup
    annotations.jsonl        written ONLY by kfuzz-findings annotate (bisect/patch progress)
    coverage.jsonl           written ONLY by kfuzz-update-current (syz-manager /metrics samples)
    focus.json               written ONLY by kfuzz-launch focus ({"enable_syscalls":[...]})
    budget.json  ledger.json reserved (YOLO caps, spend), same role as cc-fuzzer's
```

Why `verified/` and not `findings/`: cc-fuzzer's PreToolUse gate (`gate-findings.sh`, `cc_fuzzer_core/gate.py`) refuses every write whose path has a `findings` directory component, under any parent. With both plugins loaded, `kfuzz/findings/<id>/` would be unwritable. `UPSTREAM.lock` greps the gate so a change upstream is reported.

## current.json

```json
{
  "schema": "kstate/v1",
  "engine": "syzkaller",
  "updated": "2026-10-28T17:00:00Z",
  "campaign": "none | stopped | running",
  "host": { "accel": "kvm | tcg", "requested": "auto", "kvm_present": false, "timeout_mult": 10,
            "slowdown": 10, "vms": 1, "procs": 2, "plateau_min": 240, "min_interval": 1800, "...": "see kfuzz-host" },
  "manager": { "pid": 1234, "alive": true, "http": "127.0.0.1:56741" },
  "kernel": { "out": "/work/out/syzkaller", "bzimage": true, "config_stale": false },
  "config": "syzkaller.config",
  "infra": { "syz_manager": true, "image": true, "missing": [] },
  "coverage": { "cover": 41234, "crashes_total": 7, "samples": 12, "plateau": false, "window_min": 60 },
  "crashes": { "dirs": 3, "untriaged": ["<hash>"], "retry_repro": ["<hash>"] },
  "findings": { "count": 1, "pending_bisect": ["kf-0001"] },
  "recommendation": { "branch": "triage", "reason": "1 untriaged crash(es)", "target": "<hash>" }
}
```

`host` is `kfuzz-host` verbatim: the one place acceleration is decided. Without a usable `/dev/kvm`, or with `KFUZZ_ACCEL=tcg`, everything runs under QEMU TCG: syzkaller scales its own timeouts x10 (`-accel tcg` in `qemu_args`), `kfuzz-vng --timeout` scales VM timeouts by `timeout_mult`, the plateau window grows to `plateau_min`, and YOLO needs `--allow-tcg` and ticks no faster than `min_interval`.

`recommendation.branch` is the deterministic default; the orchestrator may override it with a stated reason.

| Branch | Fires when (first match wins) | Default action |
|---|---|---|
| `rebuild_kernel` | manager down and bzImage missing, or `configs/<name>.config` differs from `<out>/.config` | `kres-build -d <out>` |
| `fix_infra` | manager down and syz-manager binary, rootfs image, or `kres-syz-up` missing | report what is missing; stop |
| `restart_manager` | manager down, prerequisites present (also: no campaign yet) | `kfuzz-launch start` |
| `triage` | a `syz/crashes/<hash>/` with no record in findings.jsonl or dropped_crashes.jsonl | `kcrash-triager` on `target` |
| `repro` | a hash dropped `no_repro` whose `log*` count grew by >= 3 since the drop, or (on a KVM host) a hash dropped `flaky`/`harness_artifact`/`no_repro` under TCG | `kcrash-triager` retry on `target` |
| `bisect` | a finding with no `bisect_status` annotation | `kbisector` on `target` |
| `refocus` | `/metrics` `syz_corpus_cover` flat for `window_min` minutes | `kcov-analyst`, then `kconfig-planner` (refocus) or `syzlang-writer` (`describe_syscalls`) |
| `sleep` | manager alive, nothing above | schedule next tick |

`describe_syscalls` is never emitted by the deterministic layer: on a plateau the orchestrator picks between `refocus` and `describe_syscalls` from the `kcov-analyst` report.

## findings.jsonl (`kfinding/v1`, append-only)

```json
{"schema":"kfinding/v1","id":"kf-0001","hash":"<syz crash dir>","ts":"...","title":"KASAN: use-after-free Read in foo",
 "class":"KASAN","subsystem":"net","kernel_ref":"v6.18-rc3-12-gabcdef","config":"syzkaller.config",
 "top_frames":["foo","bar"],"bundle":"kfuzz/verified/kf-0001","repro":{"syz":"repro.syz","c":"repro.c"}}
```

`class` ∈ KASAN KMSAN KCSAN UBSAN lockdep WARNING BUG hung_task rcu_stall other.

## dropped_crashes.jsonl

```json
{"schema":"kdrop/v1","hash":"...","ts":"...","reason":"no_repro","title":"...","logs":4,"note":"...","accel":"tcg","dup_of":null}
```

`reason` ∈ infra no_repro harness_artifact duplicate not_kernel flaky other. The newest record per hash wins.

## annotations.jsonl

```json
{"schema":"kannot/v1","id":"kf-0001","ts":"...","field":"bisect_status","value":"ok"}
```

`field` ∈ cause_commit fix_commit bisect_status patch_status upstream note. `bisect_status` ∈ ok failed skipped running; `patch_status` ∈ draft validated failed sent.

## Result lines

Every specialist ends with one parseable line, the last non-blank line of its reply:

| Agent | Line |
|---|---|
| kcrash-triager | `TRIAGE_RESULT: {"hash":"..","verdict":"confirmed|dropped|duplicate","id":"..","reason":".."}` |
| kbisector | `BISECT_RESULT: {"id":"..","status":"ok|failed|skipped","cause_commit":"..","fix_commit":".."}` |
| kpatch-writer | `PATCH_RESULT: {"id":"..","status":"draft|failed","patch":".."}` |
| kpatch-validator | `VALIDATE_RESULT: {"id":"..","status":"validated|failed","failed_gate":".."}` |
| syzlang-writer | `SYZLANG_RESULT: {"status":"ok|failed","files":[..],"cover_delta":N}` |
| kcov-analyst | `KCOV_RESULT: {"verdict":"refocus|describe_syscalls|stay","report":".."}` |
| kconfig-planner | `PLAN_RESULT: {"status":"ok|failed","profile":"..","enable_syscalls":N}` |

The orchestrator ends with a `YOLO_NEXT:` line in cc-fuzzer's grammar (STATE_SCHEMA.md).
