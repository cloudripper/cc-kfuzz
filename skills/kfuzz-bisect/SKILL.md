---
name: kfuzz-bisect
description: Bisect the cause (or fix) commit of one verified kernel finding with its reproducer.
argument-hint: "<kf-id> [cause|fix] [good=<ref>] [bad=<ref>]"
---

Arguments: `$ARGUMENTS`

1. `kfuzz-findings get <id>` must succeed; stop otherwise.
2. `git -C /work/linux rev-parse --is-shallow-repository` prints `true`: tell the operator a full-history fetch is needed (`KRES_DEPTH=0 kres-fetch-kernel`, about 5 GB and several minutes) and ask before doing it.
3. Dispatch `Agent(subagent_type: "cc-kfuzz:kbisector", run_in_background: true, prompt: "id=<id> mode=<cause|fix> <good/bad if given>. Campaign root: <abs cwd>.")`. A bisect takes hours; say it started and end the turn. Its completion notification carries the result.
4. On that notification, report its `BISECT_RESULT` and `git -C /work/linux log -1 --format='%h %s' <commit>` for the culprit.
