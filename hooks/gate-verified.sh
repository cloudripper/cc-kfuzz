#!/bin/bash
# hooks/gate-verified.sh -- PreToolUse on Write|Edit|MultiEdit|NotebookEdit|Bash.
# Nothing enters kfuzz/verified/ except through kfuzz-findings, mirroring cc-fuzzer's
# gate-findings.sh: a bundle there IS the claim that a crash was verified.
# Bash commands are split into simple commands (newline ; && || |); one is refused only when
# it writes a kfuzz/verified path: a redirection into one, or a file-writing command word
# (cp mv tee ... sed -i) with such a path among its arguments. Text that merely mentions the
# path (a heredoc body, a commit message) passes. A guard rail, not a sandbox: `cd` tricks pass.
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
V='kfuzz/verified'
case $tool in
  Write|Edit|MultiEdit|NotebookEdit)
    p=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' <<<"$IN")
    [[ $p =~ (^|/)kfuzz/verified(/|$) ]] && deny "$MSG" ;;
  Bash)
    c=$(jq -r '.tool_input.command // empty' <<<"$IN")
    [[ $c == *"$V"* ]] || exit 0
    redir="(^|[^0-9&<-])[0-9]*>>?[|]?[[:space:]]*[\"']?[^[:space:];&|]*$V"
    while IFS= read -r seg; do
      [[ $seg == *"$V"* ]] || continue
      [[ $seg =~ $redir ]] && deny "$MSG"
      # command word: skip leading env assignments and sudo/env/command/exec wrappers
      read -r -a w <<<"$seg" || continue
      i=0
      while [ $i -lt ${#w[@]} ] && [[ ${w[$i]} =~ ^([A-Za-z_][A-Za-z0-9_]*=.*|sudo|env|command|exec|nohup|setsid|time)$ ]]; do i=$((i+1)); done
      cmd=${w[$i]:-}; cmd=${cmd##*/}
      case $cmd in
        kfuzz-findings) ;;
        cp|mv|tee|install|rsync|ln|touch|mkdir|rm|rmdir|dd|truncate|patch|unzip|tar) deny "$MSG" ;;
        sed|perl) [[ " ${w[*]:$i} " =~ [[:space:]]-[a-zA-Z]*i ]] && deny "$MSG" ;;
      esac
    done < <(sed -E 's/(\&\&|\|\||;|\|)/\n/g' <<<"$c") ;;
esac
exit 0
