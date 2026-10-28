---
name: kfuzz-repro
description: Triage one crash through the kernel verification pipeline - a syzbot bug (extid or URL, imported first) or an existing kfuzz/syz/crashes/<hash>. Works without fuzzing, so it suits the hosted VM.
argument-hint: "<syzbot extid | syzbot bug URL | crash hash>"
---

Arguments: `$ARGUMENTS`

1. If the argument is a syzbot extid (20 hex chars) or a `syzkaller.appspot.com/bug?extid=` URL: `kfuzz-import-syzbot <arg>`. The hash is `syzbot-<extid>`. Report the kernel git and commit it printed; that tree must be fetched for step 3 of the triager (`KRES_TREE`/`kres-fetch-kernel <ref>` for mainline-like trees, or a `git fetch <url> <commit>` into `/work/linux`).
2. Otherwise the argument must be a directory name under `kfuzz/syz/crashes/`.
3. Dispatch `Agent(subagent_type: "cc-kfuzz:kcrash-triager", prompt: "hash=<hash>. Campaign root: <abs cwd>.")`.
4. Report its `TRIAGE_RESULT` and, when confirmed, `kfuzz-findings get <id>`.
