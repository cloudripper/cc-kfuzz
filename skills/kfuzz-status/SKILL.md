---
name: kfuzz-status
description: Print kernel campaign status (manager liveness, coverage, crashes, findings, recommended branch) without invoking any agent. Cheap; safe between ticks.
argument-hint: "(no arguments)"
---
<!-- adapted from cc-fuzzer skills/fuzz-status/SKILL.md @ 478a126; see UPSTREAM.lock -->

Run, in one Bash call:

```bash
kfuzz-update-current >/dev/null && jq -r '
  "campaign   \(.campaign)  manager pid=\(.manager.pid) alive=\(.manager.alive) http=\(.manager.http)",
  "kernel     \(.kernel.out)  bzImage=\(.kernel.bzimage)  config_stale=\(.kernel.config_stale)  config=\(.config)",
  "coverage   cover=\(.coverage.cover // "-")  crashes_total=\(.coverage.crashes_total // "-")  samples=\(.coverage.samples)  plateau=\(.coverage.plateau)",
  "crashes    dirs=\(.crashes.dirs)  untriaged=\(.crashes.untriaged|length)  retry_repro=\(.crashes.retry_repro|length)",
  "findings   \(.findings.count)  pending_bisect=\(.findings.pending_bisect|length)",
  "infra      missing=\(.infra.missing|join(",") | if .=="" then "none" else . end)",
  "next       \(.recommendation.branch): \(.recommendation.reason)"' kfuzz/state/current.json
kfuzz-findings list | head -20
```

Print the output as-is. No analysis, no agent dispatch.
