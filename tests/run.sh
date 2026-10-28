#!/bin/bash
# tests/run.sh -- offline tests for cc-kfuzz bin/ and hooks/. No kernel, VM or network needed.
# Copies tests/fixtures/kfuzz to a temp dir and drives every branch of kfuzz-update-current,
# the kfuzz-findings writer, the verified/ gate, and kfuzz-compat against cc-fuzzer.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); PATH=$ROOT/bin:$PATH
T=$(mktemp -d); trap 'kill $LIVE 2>/dev/null; rm -rf "$T"' EXIT
export KFUZZ_DIR=$T/kfuzz KFUZZ_KERNEL_OUT=$T/out KFUZZ_SYZKALLER=$T/syzkaller KFUZZ_IMAGE=$T/image/rootfs.img
cp -a "$ROOT/tests/fixtures/kfuzz" "$KFUZZ_DIR"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1${2:+: $2}"; }
branch() { kfuzz-update-current | jq -r .branch; }
expect() { local b; b=$(branch); [ "$b" = "$2" ] && ok "$1 -> $2" || bad "$1" "got $b, want $2"; }

# stub infrastructure (kres-syz-up on PATH, syz-manager binary, image, built kernel)
mkdir -p "$T/stub" "$T/syzkaller/bin" "$T/image" "$T/out/arch/x86/boot"
printf '#!/bin/sh\nexit 0\n' > "$T/stub/kres-syz-up"; chmod +x "$T/stub/kres-syz-up"; PATH=$T/stub:$PATH
touch "$T/syzkaller/bin/syz-manager"; chmod +x "$T/syzkaller/bin/syz-manager"; touch "$T/image/rootfs.img"
echo 'CONFIG_KCOV=y' > "$T/out/.config"; touch "$T/out/arch/x86/boot/bzImage"

# 1. dead manager
echo 999999 > "$KFUZZ_DIR/syz/manager.pid"
expect "dead pid" restart_manager
# 2. live manager, one untriaged crash
sleep 600 & LIVE=$!; echo $LIVE > "$KFUZZ_DIR/syz/manager.pid"
export KFUZZ_METRICS_FILE=$T/metrics; printf 'syz_corpus_cover 100\nsyz_crash_total 1\n' > "$KFUZZ_METRICS_FILE"
expect "live pid + crash" triage
jq -e '.crashes.untriaged==["abc123"] and .coverage.cover==100' "$KFUZZ_DIR/state/current.json" >/dev/null \
  && ok "current.json fields" || bad "current.json fields"
# 3. infra and kernel branches (manager down)
kill $LIVE; wait $LIVE 2>/dev/null
rm "$T/syzkaller/bin/syz-manager"; expect "no syz-manager" fix_infra
touch "$T/syzkaller/bin/syz-manager"; chmod +x "$T/syzkaller/bin/syz-manager"
echo 'CONFIG_KCOV=n' > "$KFUZZ_DIR/configs/syzkaller.config"; expect "config drift" rebuild_kernel
cp "$T/out/.config" "$KFUZZ_DIR/configs/syzkaller.config"; expect "config match" restart_manager
sleep 600 & LIVE=$!; echo $LIVE > "$KFUZZ_DIR/syz/manager.pid"

# 4. writer: drop, then repro retry after recurrence
kfuzz-findings drop abc123 no_repro "one attempt" >/dev/null && ok "drop" || bad "drop"
expect "dropped no_repro" sleep
for i in 1 2 3; do touch "$KFUZZ_DIR/syz/crashes/abc123/log$i"; done
expect "recurred 3x" repro
# 5. writer: add validates, then bisect is pending
W=$KFUZZ_DIR/work/abc123; mkdir -p "$W"
cat > "$T/f.json" <<EOF
{"title":"KASAN: use-after-free Read in foo","class":"KASAN","subsystem":"net","kernel_ref":"v6.18","config":"syzkaller.config","work_dir":"$W"}
EOF
kfuzz-findings add abc123 "$T/f.json" >/dev/null 2>&1 && bad "add without repro.c accepted" || ok "add rejects incomplete bundle"
echo report > "$W/report.txt"; echo 'r0 = openat()' > "$W/repro.syz"; echo 'int main(){}' > "$W/repro.c"
jq '.class="nope"' "$T/f.json" > "$T/bad.json"
kfuzz-findings add abc123 "$T/bad.json" >/dev/null 2>&1 && bad "bad class accepted" || ok "add rejects bad class"
id=$(kfuzz-findings add abc123 "$T/f.json") && [ "$id" = kf-0001 ] && ok "add -> $id" || bad "add" "$id"
[ -f "$KFUZZ_DIR/verified/kf-0001/repro.c" ] && [ -f "$KFUZZ_DIR/verified/kf-0001/meta.json" ] && ok "bundle copied" || bad "bundle copied"
kfuzz-findings add abc123 "$T/f.json" >/dev/null 2>&1; [ $? = 3 ] && ok "duplicate add refused" || bad "duplicate add refused"
expect "finding without bisect" bisect
kfuzz-findings annotate kf-0001 bisect_status bogus >/dev/null 2>&1 && bad "bad bisect_status accepted" || ok "annotate validates"
kfuzz-findings annotate kf-0001 bisect_status ok >/dev/null
kfuzz-findings annotate kf-0001 cause_commit deadbeef >/dev/null
[ "$(kfuzz-findings get abc123 | jq -r .cause_commit)" = deadbeef ] && ok "get folds annotations" || bad "get folds annotations"
echo log > "$T/b.log"; kfuzz-findings attach kf-0001 "$T/b.log" bisect.log >/dev/null && ok "attach" || bad "attach"
kfuzz-findings attach kf-0001 "$T/b.log" ../x >/dev/null 2>&1 && bad "attach traversal accepted" || ok "attach refuses traversal"
expect "all done" sleep

# 6. plateau: a sample older than the window with the same cover
jq -cn '{ts:((now|floor)-7200), cover:100, crashes:1}' > "$KFUZZ_DIR/state/coverage.jsonl"
expect "flat 2h" refocus
printf 'syz_corpus_cover 150\n' > "$KFUZZ_METRICS_FILE"; expect "cover grew" sleep

# 7. gate
g() { jq -cn --arg t "$1" --arg k "$2" --arg v "$3" '{tool_name:$t, tool_input:{($k):$v}}' | "$ROOT/hooks/gate-verified.sh"; }
denied() { [ -n "$(g "$@")" ]; }
denied Write file_path "$KFUZZ_DIR/verified/kf-0001/x" && ok "gate: Write denied" || bad "gate: Write"
denied Bash command "cp x kfuzz/verified/kf-0001/" && ok "gate: cp denied" || bad "gate: cp"
denied Bash command "echo x > kfuzz/verified/a" && ok "gate: redirect denied" || bad "gate: redirect"
denied Bash command "kfuzz-findings attach kf-0001 a.log; rm -rf kfuzz/verified" && ok "gate: chained denied" || bad "gate: chained"
denied Bash command "kfuzz-findings attach kf-0001 kfuzz/work/a/bisect.log" && bad "gate: writer" || ok "gate: writer allowed"
denied Bash command "cat kfuzz/verified/kf-0001/repro.c" && bad "gate: read" || ok "gate: read allowed"
denied Write file_path "$KFUZZ_DIR/work/abc123/notes" && bad "gate: work/" || ok "gate: work/ allowed"

# 8. compat against the real cc-fuzzer, and a broken lock
if kfuzz-ccf >/dev/null 2>&1; then
  kfuzz-compat >/dev/null && ok "compat vs $(kfuzz-ccf)" || bad "compat" "$(kfuzz-compat)"
  printf 'require=does/not/exist\n' > "$T/lock"
  KFUZZ_LOCK=$T/lock kfuzz-compat >/dev/null && bad "compat missing file" || ok "compat flags missing file"
else echo "skip compat (cc-fuzzer not found)"; fi

# 9. kernel semgrep rules: each rule fires on the fixture
if command -v semgrep >/dev/null; then
  got=$(semgrep --config "$ROOT/rules/semgrep/kernel" --metrics=off --json --quiet "$ROOT/tests/fixtures/semgrep/kernel.c" 2>/dev/null \
        | jq -r '[.results[].check_id | split(".") | last] | unique | join(" ")')
  for r in kernel-alloc-mul-overflow kernel-copy-from-user-unchecked kernel-get-put-user-unchecked kernel-use-after-kfree; do
    [[ " $got " == *" $r "* ]] && ok "semgrep $r" || bad "semgrep $r" "$got"
  done
else echo "skip semgrep (not installed)"; fi

echo "passed=$pass failed=$fail"; [ $fail = 0 ]
