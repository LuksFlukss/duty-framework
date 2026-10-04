#!/usr/bin/env bash
# Runs each hook under Claude, Copilot and unknown-platform env vars and checks the JSON output.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fails=0

check() { # name, jq expression that must be true
  if [ -n "$out" ] && printf '%s' "$out" | jq -e "$2" >/dev/null 2>&1; then
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
for skill in design plan tdd debugging verify-and-handoff team agents; do
  check "session-start lists skill $skill" ".hookSpecificOutput.additionalContext | contains(\"- $skill:\")"
done

ok_or_fail() { # name, condition exit status
  if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}
fm()   { sed -n '2,/^---$/p' "$1" 2>/dev/null | sed '$d'; }  # frontmatter of a file
body() { awk 'n >= 2; /^---$/ { n++ }' "$1" 2>/dev/null; }  # text after frontmatter
field() { fm "$1" | sed -n "s/^$2: *//p"; }

AGY_TOOLS='view_file list_dir find_by_name grep_search read_url_content search_web replace_file_content multi_replace_file_content write_to_file run_command command_status'
for role in scout researcher builder refuter debugger; do
  src="$ROOT/roles/$role.md"
  for dir in claude-agents agents copilot-agents; do
    f="$ROOT/$dir/$role.md"
    [ "$(field "$f" name)" = "$role" ] && [ -n "$(field "$f" description)" ]
    ok_or_fail "$dir/$role has name and description" $?
    [ -n "$(body "$f")" ] && [ "$(body "$f")" = "$(body "$src")" ]
    ok_or_fail "$dir/$role body matches roles/$role.md" $?
  done

  # Claude Code: session default model and effort (personalise with scripts/personalize)
  [ "$(field "$ROOT/claude-agents/$role.md" model)" = inherit ] && [ -z "$(field "$ROOT/claude-agents/$role.md" effort)" ]
  ok_or_fail "claude-agents/$role model is inherit, no effort" $?
  # Antigravity: tier 'inherit' (session default) and only native tool names
  [ "$(field "$ROOT/agents/$role.md" model)" = inherit ]
  ok_or_fail "agents/$role (agy) model is inherit" $?
  tools=$(field "$ROOT/agents/$role.md" tools | tr -d '[],')
  bad=0; [ -n "$tools" ] || bad=1
  for t in $tools; do printf ' %s ' "$AGY_TOOLS" | grep -q " $t " || bad=1; done
  ok_or_fail "agents/$role (agy) lists only known agy tools" $bad
  # Copilot: no model (session default)
  [ -z "$(field "$ROOT/copilot-agents/$role.md" model)" ] && [ -n "$(field "$ROOT/copilot-agents/$role.md" tools)" ]
  ok_or_fail "copilot-agents/$role has tools and no model" $?
done
for role in scout researcher refuter debugger; do
  ! field "$ROOT/claude-agents/$role.md" tools | grep -qE 'Edit|Write|Agent' && [ -n "$(field "$ROOT/claude-agents/$role.md" tools)" ]
  ok_or_fail "claude-agents/$role can't edit or spawn" $?
  ! field "$ROOT/agents/$role.md" tools | grep -qE 'replace_file_content|write_to_file|subagent'
  ok_or_fail "agents/$role (agy) can't edit or spawn" $?
  ! field "$ROOT/copilot-agents/$role.md" tools | grep -qE 'edit|agent'
  ok_or_fail "copilot-agents/$role can't edit or spawn" $?
done

tmp=$(mktemp -d)
"$ROOT/scripts/build-agents" "$tmp" >/dev/null 2>&1 \
  && diff -r "$tmp/agents" "$ROOT/agents" >/dev/null \
  && diff -r "$tmp/claude-agents" "$ROOT/claude-agents" >/dev/null \
  && diff -r "$tmp/copilot-agents" "$ROOT/copilot-agents" >/dev/null
ok_or_fail "generated agents are up to date (scripts/build-agents)" $?
rm -rf "$tmp"

out=$(cat "$ROOT/.claude-plugin/plugin.json")
check "claude manifest lists claude-agents" '[.agents[]] | sort == ["./claude-agents/builder.md","./claude-agents/debugger.md","./claude-agents/refuter.md","./claude-agents/researcher.md","./claude-agents/scout.md"]'
check "claude manifest version 0.2.0" '.version == "0.2.0"'
out=$(cat "$ROOT/.claude-plugin/marketplace.json")
check "marketplace version 0.2.0" '.plugins[0].version == "0.2.0"'
out=$(cat "$ROOT/.plugin/plugin.json" 2>/dev/null)
check "copilot manifest points at copilot-agents" '.name == "duty-framework" and .agents == "./copilot-agents" and .version == "0.2.0"'

# team skill: no fixed models, knows about personal agents
! grep -qE '^\| `[a-z]+` \| (haiku|sonnet|opus) \|' "$ROOT/skills/team/SKILL.md"
ok_or_fail "team skill has no fixed model column" $?
grep -q 'duty-<role>' "$ROOT/skills/team/SKILL.md" && grep -q '`agents` skill' "$ROOT/skills/team/SKILL.md"
ok_or_fail "team skill points to duty-<role> and the agents skill" $?

# scripts/personalize, against a fake HOME with fake model sources
T=$(mktemp -d); H="$T/home"; mkdir -p "$T/bin" "$H/.copilot" "$H/.claude/cache/model-catalog"
cat > "$T/bin/copilot" <<'FAKE'
#!/bin/sh
# Fake Copilot: model list, and Copilot's real errors for unsupported efforts. Logs every call.
echo "$*" >> "$(dirname "$0")/calls"
[ "$1 $2" = "help config" ] && { printf '%s\n' '  `model`: AI model to use.' '    - "claude-haiku-4.5"' '    - "gpt-5.4"' '  `theme`: colors.' '    - "dark"'; exit 0; }
m='' e=''
while [ $# -gt 0 ]; do case "$1" in --model) m="$2"; shift ;; --reasoning-effort) e="$2"; shift ;; esac; shift; done
case "$m:$e" in
  claude-haiku-4.5:?*) echo "Error: Model \"$m\" does not support reasoning effort configuration (requested: \"$e\")." >&2; exit 1 ;;
  gpt-5.4:max) echo "Error: Reasoning effort \"max\" is not supported for model \"gpt-5.4\"." >&2; exit 1 ;;
esac
echo ok
FAKE
chmod +x "$T/bin/copilot"
echo '{"catalog":{"config":{"models":[{"id":"claude-sonnet-5","thinking":{"effort_options":[{"id":"low"},{"id":"high"}]}},{"id":"claude-haiku-4-5","thinking":{"effort_options":null}}]}}}' > "$H/.claude/cache/model-catalog/x-cc.json"
echo '{"theme":"dark","subagents":{"agents":{"other:agent":{"model":"gpt-5.4"}}}}' > "$H/.copilot/settings.json"
P() { env -u XDG_CONFIG_HOME -u COPILOT_HOME HOME="$H" PATH="$T/bin:$PATH" "$ROOT/scripts/personalize" "$@"; }
lines() { printf '%s\n' "$1" | tr '\n' ' '; }
CS="$H/.copilot/settings.json" CA="$H/.claude/agents/duty-scout.md" GA="$H/.gemini/config/agents/duty-scout.md" CFG="$H/.config/duty-framework/agents.json"

[ "$(lines "$(P models copilot)")" = "claude-haiku-4.5 gpt-5.4 " ]
ok_or_fail "personalize models copilot (from copilot help config)" $?
m=$(P models claude); printf '%s\n' "$m" | grep -qx claude-sonnet-5 && printf '%s\n' "$m" | grep -qx sonnet
ok_or_fail "personalize models claude (catalog + aliases)" $?
[ "$(lines "$(P models agy)")" = "flash_lite flash pro " ]
ok_or_fail "personalize models agy (tiers only)" $?
[ "$(lines "$(P efforts claude claude-sonnet-5)")" = "low high " ] && [ -z "$(P efforts claude claude-haiku-4-5)" ] && [ -z "$(P efforts agy flash)" ] && P efforts copilot gpt-5.4 | grep -qx max
ok_or_fail "personalize efforts per tool and model" $?

P set copilot scout gpt-5.4 low >/dev/null 2>&1
out=$(cat "$CS"); check "personalize set copilot merges duty-framework:scout, keeps other settings" \
  '.theme == "dark" and .subagents.agents["other:agent"].model == "gpt-5.4" and .subagents.agents["duty-framework:scout"] == {"model":"gpt-5.4","effortLevel":"low"}'
P set claude scout claude-sonnet-5 high >/dev/null 2>&1
[ "$(field "$CA" name)" = duty-scout ] && [ "$(field "$CA" model)" = claude-sonnet-5 ] && [ "$(field "$CA" effort)" = high ] \
  && [ "$(field "$CA" tools)" = "Read, Grep, Glob" ] && [ "$(body "$CA")" = "$(body "$ROOT/roles/scout.md")" ]
ok_or_fail "personalize set claude writes ~/.claude/agents/duty-scout.md" $?
P set agy scout flash >/dev/null 2>&1
[ "$(field "$GA" name)" = duty-scout ] && [ "$(field "$GA" model)" = flash ] && [ -z "$(field "$GA" effort)" ] \
  && [ "$(field "$GA" tools)" = "$(field "$ROOT/agents/scout.md" tools)" ] && [ "$(body "$GA")" = "$(body "$ROOT/roles/scout.md")" ]
ok_or_fail "personalize set agy writes ~/.gemini/config/agents/duty-scout.md" $?
out=$(cat "$CFG" 2>/dev/null); check "personalize saves choices in ~/.config/duty-framework/agents.json" \
  '.claude.scout == {"model":"claude-sonnet-5","effort":"high"} and .copilot.scout == {"model":"gpt-5.4","effort":"low"} and .agy.scout == {"model":"flash"}'
P show claude | grep -E '^scout +claude-sonnet-5 +high' >/dev/null && P show claude | grep -E '^researcher +default' >/dev/null
ok_or_fail "personalize show claude" $?

bad=0
for args in "agy scout flash high" "agy scout claude-sonnet-5" "copilot scout nope" "claude scout claude-haiku-4-5 high" "claude nobody sonnet" "vim scout sonnet"; do
  P set $args >/dev/null 2>&1 && { echo "     accepted: set $args"; bad=1; }
done
ok_or_fail "personalize rejects invalid tool, role, model or effort" $bad

# Copilot efforts: checked once with Copilot itself, result remembered
calls() { grep -c -- "$1" "$T/bin/calls" 2>/dev/null || true; }
P set copilot scout gpt-5.4 max >/dev/null 2>&1; rc=$?
[ $rc -ne 0 ] && out=$(cat "$CFG") && [ "$(jq -c .copilot.scout <<<"$out")" = '{"model":"gpt-5.4","effort":"low"}' ]
ok_or_fail "personalize rejects an effort Copilot doesn't support, keeps the old choice" $?
e=$(P efforts copilot gpt-5.4); ! grep -qx max <<<"$e" && grep -qx high <<<"$e"
ok_or_fail "personalize efforts copilot drops a rejected effort" $?
P set copilot scout gpt-5.4 high >/dev/null 2>&1 && P set copilot scout gpt-5.4 high >/dev/null 2>&1
[ "$(calls 'reasoning-effort high')" = 1 ] && [ "$(jq -r '.subagents.agents["duty-framework:scout"].effortLevel' "$CS")" = high ]
ok_or_fail "personalize checks a Copilot effort once and remembers it" $?
! P set copilot scout claude-haiku-4.5 low >/dev/null 2>&1 && [ -z "$(P efforts copilot claude-haiku-4.5)" ]
ok_or_fail "personalize learns a Copilot model takes no effort" $?

echo stale >> "$CA"; P apply >/dev/null 2>&1
[ "$(body "$CA")" = "$(body "$ROOT/roles/scout.md")" ]
ok_or_fail "personalize apply refreshes personal copies" $?

P set claude scout default >/dev/null 2>&1 && P set agy scout default >/dev/null 2>&1 && P set copilot scout default >/dev/null 2>&1
[ ! -e "$CA" ] && [ ! -e "$GA" ]
ok_or_fail "personalize default removes claude/agy copies" $?
out=$(cat "$CS"); check "personalize default removes copilot override, keeps the rest" \
  '.theme == "dark" and .subagents.agents["other:agent"].model == "gpt-5.4" and (.subagents.agents | has("duty-framework:scout") | not)'
out=$(cat "$CFG" 2>/dev/null); check "personalize default clears saved choices" '[.claude.scout, .copilot.scout, .agy.scout] == [null, null, null]'
echo '{"theme":"dark"}' > "$CS"; P set copilot scout gpt-5.4 >/dev/null 2>&1; P set copilot scout default >/dev/null 2>&1
out=$(cat "$CS"); check "personalize default leaves no empty subagents block" '. == {"theme":"dark"}'
rm -rf "$T"

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
  if [ $? -eq 0 ] && printf '%s' "$out" | grep -q 'skills *: 7 processed' && printf '%s' "$out" | grep -q 'agents *: 5 processed'; then
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
