---
name: kfuzz-doctor
description: Diagnose a cc-kfuzz setup - cc-fuzzer drift against UPSTREAM.lock, cc-fuzzer file integrity, kernel toolchain and syzkaller prerequisites, KVM, and kfuzz/state consistency. Read-only.
argument-hint: "(no arguments)"
---
<!-- adapted from cc-fuzzer skills/doctor/SKILL.md @ 478a126; see UPSTREAM.lock -->

Read-only. Run each check and report a table of check, result, fix.

1. `kfuzz-ccf` and `kfuzz-compat`: cc-fuzzer found, surface OK. On `MISSING`/`PATTERN GONE`/`NAME`, cc-kfuzz is incompatible with the installed cc-fuzzer: name the lock line and the fix (pin `CC_FUZZER_REF` to `tested_ref` in the setup script, or update cc-kfuzz). `NOTE` lines are informational.
2. `bash "$(kfuzz-ccf scripts/integrity-check.sh)"`: cc-fuzzer files unmodified.
3. `kres-doctor`: toolchain, `kvm=`, `/work/linux`, syz-manager, rootfs image, `CLAUDE_CODE_PLUGIN_DIRS`, nix.
4. `echo "$CLAUDE_CODE_PLUGIN_DIRS"` lists both plugin dirs (cloud) or the session was started with two `--plugin-dir` flags.
5. If `kfuzz/` exists: `kfuzz-update-current`, then check that every `kfuzz/verified/<id>/` has `.verified` and `meta.json` and a matching line in `kfuzz/state/findings.jsonl` (and the reverse), and that every `*.jsonl` line parses (`jq -c . <file> >/dev/null`).
6. Stale manager: `manager.pid` present but process dead while `campaign` is `stopped` is normal; report it only if the operator expects it running.

Never modify anything; suggest commands instead.
