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
check "claude manifest version 0.3.0" '.version == "0.3.0"'
out=$(cat "$ROOT/.claude-plugin/marketplace.json")
check "marketplace version 0.3.0" '.plugins[0].version == "0.3.0"'
out=$(cat "$ROOT/.plugin/plugin.json" 2>/dev/null)
check "copilot manifest points at copilot-agents" '.name == "duty-framework" and .agents == "./copilot-agents" and .version == "0.3.0"'

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

# Size label and mandatory refuter: rule text
has() { grep -qF -- "$2" "$ROOT/$1"; }
has RULES.md 'Size: small|medium|large|quick' && has RULES.md 'never skipped' && ! has RULES.md 'when that helps'
ok_or_fail "RULES.md asks for a Size: label and never skips the refuter" $?
grep '^- \*\*Medium\*\*' "$ROOT/RULES.md" | grep -q refuter
ok_or_fail "RULES.md medium tasks get a refuter review" $?
run prompt-nudge CLAUDE_PLUGIN_ROOT="$ROOT"
check "prompt-nudge mentions refuter and team" '.hookSpecificOutput.additionalContext | contains("refuter") and contains("team")'
field "$ROOT/skills/team/SKILL.md" description | grep -q refuter && body "$ROOT/skills/team/SKILL.md" | grep -qF 'never skipped for medium or large'
ok_or_fail "team skill makes the refuter mandatory for medium and large" $?
has skills/design/SKILL.md 'Size: small|medium|large|quick'
ok_or_fail "design skill asks for a Size: label" $?
has skills/plan/SKILL.md refuter && has skills/verify-and-handoff/SKILL.md refuter
ok_or_fail "plan and verify-and-handoff mention the refuter" $?
run subagent-start CLAUDE_PLUGIN_ROOT="$ROOT"
check "subagent-start tells subagents to skip the Size: label" '.hookSpecificOutput.additionalContext | ascii_downcase | contains("skip the `size:` label")'
out=$(cat "$ROOT/hooks/hooks.json")
check "hooks.json registers Stop without matcher" '(.hooks.Stop[0].hooks[0].command | contains("stop-gate")) and (.hooks.Stop[0] | has("matcher") | not)'

# stop-gate, against fixture transcripts
G=$(mktemp -d)
txt()  { jq -cn --arg t "$1" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}'; }
tool() { jq -cn --arg n "$1" --argjson i "$2" '{type:"assistant",message:{content:[{type:"tool_use",name:$n,input:$i}]}}'; }
W()    { tool "${2:-Write}" "{\"file_path\":\"${1:-/x/a.md}\"}"; }
TEAM() { tool Skill '{"skill":"duty-framework:team"}'; }
AG()   { tool "${2:-Agent}" "{\"subagent_type\":\"$1\"}"; }
U()    { echo '{"type":"user","message":{"content":[{"type":"text","text":"Size: small"}]}}'; }
PR()   { jq -cn --arg t "$1" '{type:"user",message:{role:"user",content:$t}}'; }
META() { echo '{"type":"user","isMeta":true,"message":{"content":[{"type":"text","text":"Size: small skill body"}]}}'; }
TR()   { echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}'; }
fx()   { f="$G/$1.jsonl"; shift; printf '%s\n' "$@" > "$f"; }
gate() { # fixture, last_assistant_message, stop_hook_active
  out=$(jq -cn --arg p "$G/$1.jsonl" --arg m "${2:-}" --argjson a "${3:-false}" \
    '{transcript_path:$p,last_assistant_message:$m,stop_hook_active:$a}' | CLAUDE_PLUGIN_ROOT="$ROOT" "$ROOT/hooks/stop-gate" 2>&1); rc=$?
}
blocks() { # name, fixture, [extra jq], [last msg], [stop_hook_active]
  gate "$2" "${4:-}" "${5:-false}"
  [ $rc -eq 0 ] || out=''
  check "stop-gate blocks: $1" ".decision == \"block\" and (.reason | startswith(\"duty-framework:\")) and (${3:-true})"
}
allows() { # name, fixture, [last msg]
  gate "$2" "${3:-}"
  [ $rc -eq 0 ] && { [ -z "$out" ] || printf '%s' "$out" | jq -e '(.decision // null) == null' >/dev/null 2>&1; }
  ok_or_fail "stop-gate allows: $1" $?
}
fx a "$(txt 'Size: large')" "$(U)" "$(W)"
blocks "large, edit, no team, no refuter" a '.reason | contains("team") and contains("refuter")'
blocks "stop_hook_active doesn't exit early" a true '' true
fx b "$(txt 'Size: large')" "$(TEAM)" "$(U)" "$(W)" "$(AG duty-framework:refuter)"
allows "large with team and refuter after the edit" b
fx c "$(txt 'Size: large')" "$(TEAM)" "$(AG duty-framework:refuter)" "$(W)"
blocks "large, edit after the refuter" c '.reason | contains("refuter")'
fx d "$(txt 'Size: medium')" "$(W)"
blocks "medium, edit, no refuter (team not required)" d '.reason | contains("refuter") and (contains("team") | not)'
fx e "$(txt 'Size: medium')" "$(W)" "$(AG duty-framework:refuter)"
allows "medium with refuter" e
fx f1 "$(txt 'Size: small')" "$(W)"; allows "small" f1
fx f2 "$(txt 'Size: quick')" "$(W)"; allows "quick" f2
fx f3 "$(txt 'hello')" "$(W)"; allows "no label" f3
fx g "$(txt 'Size: large')" "$(txt 'just a question')"; allows "large without edits" g
fx h "$(txt 'Size: medium')" "$(W /home/u/.claude/projects/x/memory/m.md)"; allows "medium, only writes under /.claude/" h
fx i1 "$(txt 'Size: medium')" "$(AG duty-framework:builder)"; blocks "medium, builder counts as edit" i1
fx i2 "$(txt 'Size: medium')" "$(AG duty-builder)"; blocks "medium, personal duty-builder counts as edit" i2
fx i3 "$(txt 'Size: medium')" "$(AG duty-builder)" "$(AG duty-refuter)"; allows "medium, personal duty-refuter" i3
fx j "$(txt 'Size: small')" "$(W)"
allows "last_assistant_message is ignored (medium there, small in transcript)" j 'Size: medium'
allows "last_assistant_message is ignored (medium there, no label in transcript)" f3 'Size: medium'
fx j2 "$(txt 'Size: medium')" "$(W)"
blocks "last_assistant_message without label keeps transcript label" j2 true 'All done.'
blocks "last_assistant_message is ignored (small there, medium in transcript)" j2 true 'Size: small'
fx k "$(txt 'Size: large')" "$(W)" "$(PR next)" "$(txt 'Size: small')" "$(W)"; allows "last label wins" k
allows "missing transcript" nope
fx m1 "$(txt 'Size: medium')" "$(W)" "$(AG duty-framework:refuter Task)"; allows "Task works like Agent (refuter)" m1
fx m2 "$(txt 'Size: medium')" "$(AG duty-framework:builder Task)"; blocks "Task works like Agent (builder)" m2
fx o1 "$(txt 'Size: medium')" "$(W /x/a.md Edit)"; blocks "Edit counts as edit" o1
fx o2 "$(txt 'Size: medium')" "$(W /x/a.ipynb NotebookEdit)"; blocks "NotebookEdit counts as edit" o2
# label only at the start of a text block; tolerant parsing
fx r1 "$(txt 'Size: large')" "$(W)" "$(txt 'Done. Size: small task, nothing else.')"
blocks "mid-text Size: mention doesn't reset the label" r1
blocks "mid-text Size: in last_assistant_message doesn't reset the label" a true 'Done. Size: medium task finished.'
fx r2 "$(txt 'Size: medium')" "$(W)" "$(txt 'Size: small|medium|large|quick is the format')"
blocks "quoted Size: format at block start doesn't count" r2
fx r3 "$(txt 'Size: large. Now Size: small')" "$(W)"
blocks "first label of a block wins (block start only)" r3
fx r4 "$(txt 'Done; as `Size: small|medium|large|quick` says')" "$(W)"
allows "quoted format mid-text is no label" r4
for l in '**Size:** medium' '**Size: medium**' '`Size: medium`' '  Size: Medium' '_Size:_ medium' '## Size: medium' '> Size: medium'; do
  fx r5 "$(txt "$l")" "$(W)"; blocks "label form: $l" r5
done
fx r6 "$(txt 'Size: large')" "$(W)" '{"type":"assistant","message":{"content":[{"type":"te' "$(U)"
blocks "malformed line doesn't switch the gate off" r6
fx r7 "$(txt 'Size: large')" "$(jq -cn '{type:"assistant",message:{content:[{type:"thinking",thinking:"Size: small"}]}}')" "$(W)"
blocks "thinking blocks are ignored" r7
fx r8 "$(TEAM)" "$(txt 'Size: large')" "$(W)" "$(AG duty-framework:refuter)"
blocks "team loaded before the label doesn't count" r8 '.reason | contains("team")'
fx r9 "$(txt 'Size: medium')" "$(tool NotebookEdit '{"notebook_path":"/x/n.ipynb"}')"
blocks "NotebookEdit with notebook_path counts as edit" r9
fx r10 "$(txt 'Size: medium')" "$(tool NotebookEdit '{"notebook_path":"/home/u/.claude/n.ipynb"}')"
allows "NotebookEdit under /.claude/ doesn't count" r10

# turns: a label counts only before the first edit of its turn
fx s1 "$(W)" "$(txt 'Size: medium — done')"
allows "label after an edit in the same turn is ignored" s1
fx s2 "$(txt 'Size: large')" "$(PR next)" "$(W)" "$(txt 'Size: medium — done')"
blocks "label after an edit is ignored; earlier turn label applies" s2 '.reason | contains("team")'
fx s3 "$(txt 'Size: medium')" "$(PR next)" "$(W)"
blocks "label from an earlier turn applies to later edits" s3
fx s4 "$(txt 'Size: medium')" "$(tool Skill '{"skill":"duty-framework:tdd"}')" "$(META)" "$(W)"
blocks "meta user entry (skill body) between label and edit" s4
fx s5 "$(txt 'Size: medium')" "$(W)" "$(META)" "$(txt 'Size: small now')"
blocks "meta user entry is no turn boundary" s5
fx s6 "$(txt 'Size: medium')" "$(W)" "$(TR)" "$(txt 'Size: small now')"
blocks "tool_result entry is no turn boundary" s6
for l in 'Size: small/medium/large/quick' 'Size: small | medium' 'Size: small, medium' '**Size:** small|medium'; do
  fx s7 "$(txt 'Size: medium')" "$(PR next)" "$(txt "$l")" "$(W)"; blocks "not a label: $l" s7
done
rm -rf "$G"

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
