#!/usr/bin/env bash
# Runs each hook under Claude, Copilot and unknown-platform env vars and checks the JSON output.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fails=0

check() { # name, jq expression that must be true
  if printf '%s' "$out" | jq -e "$2" >/dev/null 2>&1; then
    echo "ok   $1"
  else
    echo "FAIL $1"; fails=$((fails + 1))
  fi
}

run() { # hook, env...
  local hook="$1"; shift
  out=$(env -u CLAUDE_PLUGIN_ROOT -u COPILOT_CLI "$@" "$ROOT/hooks/$hook" </dev/null 2>&1)
}

for hook in session-start prompt-nudge; do
  case $hook in
    session-start) event=SessionStart; text='Never run `git commit`' ;;
    prompt-nudge)  event=UserPromptSubmit; text='uncommitted' ;;
  esac

  run "$hook" CLAUDE_PLUGIN_ROOT="$ROOT"
  check "$hook claude: nested additionalContext" \
    ".hookSpecificOutput.hookEventName == \"$event\" and (.hookSpecificOutput.additionalContext | contains(\"$text\")) and (has(\"additionalContext\") | not)"

  run "$hook" CLAUDE_PLUGIN_ROOT="$ROOT" COPILOT_CLI=1
  check "$hook copilot: top-level additionalContext" \
    "(.additionalContext | contains(\"$text\")) and (has(\"hookSpecificOutput\") | not)"

  run "$hook"
  check "$hook unknown: top-level additionalContext" \
    "(.additionalContext | contains(\"$text\"))"
done

run session-start CLAUDE_PLUGIN_ROOT="$ROOT"
for skill in design plan tdd debugging verify-and-handoff; do
  check "session-start lists skill $skill" ".hookSpecificOutput.additionalContext | contains(\"- $skill:\")"
done

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
