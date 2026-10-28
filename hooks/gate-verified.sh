#!/bin/bash
# hooks/gate-verified.sh -- PreToolUse on Write|Edit|MultiEdit|NotebookEdit|Bash.
# Nothing enters kfuzz/verified/ except through kfuzz-findings, mirroring cc-fuzzer's
# gate-findings.sh: a bundle there IS the claim that a crash was verified.
# Fails open on unparsable input (the writer script is still the only documented path).
set -u
IN=$(cat 2>/dev/null) || exit 0
command -v jq >/dev/null || exit 0
tool=$(jq -r '.tool_name // empty' <<<"$IN" 2>/dev/null) || exit 0
deny() {
  jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",
    permissionDecisionReason:$r}}'
  exit 0
}
MSG="kfuzz/verified/ holds verified bundles and is written only by kfuzz-findings (add|attach). Work in kfuzz/work/<hash>/ and run kfuzz-findings."
case $tool in
  Write|Edit|MultiEdit|NotebookEdit)
    p=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' <<<"$IN")
    [[ $p =~ (^|/)kfuzz/verified(/|$) ]] && deny "$MSG" ;;
  Bash)
    c=$(jq -r '.tool_input.command // empty' <<<"$IN")
    [[ $c =~ kfuzz/verified ]] || exit 0
    # the sanctioned writer, as a single simple command
    if [[ $c =~ ^[[:space:]]*([^[:space:]]*/)?kfuzz-findings[[:space:]] ]] && ! [[ $c =~ [\;\&\|\>\`] ]] && ! [[ $c == *'$('* ]]; then
      exit 0
    fi
    if [[ $c =~ (\>|(^|[^[:alnum:]_-])(cp|mv|mkdir|tee|install|rsync|touch|ln|dd|rm|truncate|patch)([[:space:]]|$)|sed[[:space:]]+-i|git[[:space:]]+(am|apply|checkout)) ]]; then
      deny "$MSG"
    fi ;;
esac
exit 0
