---
name: kfuzz-patch
description: Draft and validate a kernel fix for one verified finding - kpatch-writer drafts, kpatch-validator runs checkpatch, sparse, coccicheck, rebuild and the reproducer gates; up to 3 rounds.
argument-hint: "<kf-id> [--rounds N]"
---

Arguments: `$ARGUMENTS`

1. `kfuzz-findings get <id>` must succeed. Check `git -C /work/linux config user.name` and `user.email` are set; the patch is authored and signed off as that identity, so ask the operator if either is missing.
2. Round (max `--rounds`, default 3):
   a. `Agent(subagent_type: "cc-kfuzz:kpatch-writer", prompt: "id=<id>. <previous gate failure output, if any>. Campaign root: <abs cwd>.")`
   b. `Agent(subagent_type: "cc-kfuzz:kpatch-validator", prompt: "id=<id>. Campaign root: <abs cwd>.")`
   c. `VALIDATE_RESULT` status `validated`: stop. `failed`: pass the failed gate and its log path to the next writer round.
3. Report the patch path (`kfuzz/verified/<id>/patch/`), the gate table, and the send command for the operator to run themselves: `git -C /work/linux send-email --to-cmd='./scripts/get_maintainer.pl --norolestats --nol' --cc-cmd='./scripts/get_maintainer.pl --norolestats --nom' <patch>` or `b4 send`. Never send it yourself.
