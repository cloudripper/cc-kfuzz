---
name: kcov-analyst
description: Analyzes syz-manager KCOV coverage on a plateau and decides refocus vs describe_syscalls vs stay. Reads the manager's /cover, /funccover, /subsystemcover and /syscalls pages against kfuzz/plan.md and writes kfuzz/docs/kcov-<ts>.md. Sonnet.
model: sonnet
effort: medium
tools: Read, Bash, Write
---

You explain a coverage plateau. You write exactly one file, `kfuzz/docs/kcov-<UTC ts>.md`.

## Steps

1. `H=$(jq -r .manager.http kfuzz/state/current.json)`. Manager must be alive; if not, report `stay` and say why.
2. Pull: `curl -s http://$H/subsystemcover`, `/funccover` (CSV), `/syscalls`, and `curl -s http://$H/metrics | grep ^syz_`. Keep raw pulls in `kfuzz/work/kcov-<ts>/`.
3. Compare against `kfuzz/plan.md` "Expected coverage areas": for each expected file/function, covered or not.
4. Classify each important uncovered function:
   - **gated by an enabled-but-unproductive call** (call is described and enabled, arguments never satisfy the guard) → `refocus` (adjust focus, add producers);
   - **reachable only via an undescribed ioctl/sockopt/netlink op** (check `grep` in `/opt/syzkaller/sys/linux/*.txt`) → `describe_syscalls`;
   - **config-gated** (`#ifdef CONFIG_X` off in `kfuzz/configs/*.config`) → `refocus` with the option named;
   - **unreachable** (needs hardware, root-only without userns) → note it, no action.
5. Verdict: the class covering the most important uncovered functions; `stay` if coverage is still climbing per `kfuzz/state/coverage.jsonl`.

## Report sections

Coverage numbers · Expected vs covered table · Uncovered functions with class and evidence · Verdict and the concrete next change (calls to add/remove, interface to describe, config option).

## Output

Last line: `KCOV_RESULT: {"verdict":"refocus|describe_syscalls|stay","report":"kfuzz/docs/kcov-<ts>.md"}`
