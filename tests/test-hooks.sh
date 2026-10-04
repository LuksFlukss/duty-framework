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
check "session-start forbids apply/deploy" '.hookSpecificOutput.additionalContext | contains("Never apply, deploy")'
run prompt-nudge CLAUDE_PLUGIN_ROOT="$ROOT"
check "prompt-nudge forbids apply/deploy" '.hookSpecificOutput.additionalContext | contains("No apply/deploy")'

run subagent-start CLAUDE_PLUGIN_ROOT="$ROOT"
check "subagent-start claude: nested additionalContext with rules" \
  '.hookSpecificOutput.hookEventName == "SubagentStart" and (.hookSpecificOutput.additionalContext | contains("Never run `git commit`") and contains("Never apply, deploy") and contains("report the question back"))'
out=$(cat "$ROOT/hooks/hooks.json")
check "hooks.json registers SubagentStart" '.hooks.SubagentStart[0].hooks[0].command | contains("subagent-start")'
for f in RULES.md skills/plan/SKILL.md; do
  if grep -qi 'hand.*to subagents' "$ROOT/$f"; then
    echo "ok   $f says when to hand work to subagents"
  else
    echo "FAIL $f says when to hand work to subagents"; fails=$((fails + 1))
  fi
done
if grep -q 'When you start a subagent' "$ROOT/RULES.md"; then
  echo "ok   rules tell main agent to pass rules to subagents"
else
  echo "FAIL rules tell main agent to pass rules to subagents"; fails=$((fails + 1))
fi

run session-start CLAUDE_PLUGIN_ROOT="$ROOT"
for skill in design plan tdd debugging verify-and-handoff team; do
  check "session-start lists skill $skill" ".hookSpecificOutput.additionalContext | contains(\"- $skill:\")"
done

for role in scout researcher builder refuter debugger; do
  f="$ROOT/agents/$role.md"
  fm=$(sed -n '2,/^---$/p' "$f" 2>/dev/null)
  if printf '%s' "$fm" | grep -q "^name: $role$" && printf '%s' "$fm" | grep -q '^description: ' && printf '%s' "$fm" | grep -q '^model: '; then
    echo "ok   agent $role has name, description, model"
  else
    echo "FAIL agent $role has name, description, model"; fails=$((fails + 1))
  fi
done
for role in scout researcher refuter debugger; do
  tools=$(sed -n 's/^tools: *//p' "$ROOT/agents/$role.md" 2>/dev/null)
  if [ -n "$tools" ] && ! printf '%s' "$tools" | grep -qE 'Edit|Write|Agent'; then
    echo "ok   agent $role can't edit or spawn"
  else
    echo "FAIL agent $role can't edit or spawn"; fails=$((fails + 1))
  fi
done

if command -v claude >/dev/null; then
  out=$(claude plugin validate "$ROOT" 2>&1)
  if [ $? -eq 0 ] && ! printf '%s' "$out" | grep -qi 'warning'; then
    echo "ok   claude plugin validate"
  else
    echo "FAIL claude plugin validate"; printf '%s\n' "$out"; fails=$((fails + 1))
  fi
fi

if command -v agy >/dev/null; then
  out=$(agy plugin validate "$ROOT" 2>&1)
  if [ $? -eq 0 ] && printf '%s' "$out" | grep -q 'skills *: 6 processed'; then
    echo "ok   agy plugin validate"
  else
    echo "FAIL agy plugin validate"; printf '%s\n' "$out"; fails=$((fails + 1))
  fi
  if grep -qx 'trigger: always_on' "$ROOT/rules/duty-framework.md" 2>/dev/null; then
    echo "ok   agy always_on rule"
  else
    echo "FAIL agy always_on rule"; fails=$((fails + 1))
  fi
else
  echo "skip agy plugin validate (agy not installed)"
fi

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
