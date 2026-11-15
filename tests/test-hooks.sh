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

RUN_HOME=$(mktemp -d)
run() { # hook, env...
  local hook="$1"; shift
  out=$(env -u CLAUDE_PLUGIN_ROOT -u COPILOT_CLI -u COPILOT_HOME -u XDG_CONFIG_HOME HOME="$RUN_HOME" "$@" "$ROOT/hooks/$hook" </dev/null 2>&1)
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
run subagent-start CLAUDE_PLUGIN_ROOT="$ROOT"
check "subagent-start injects the sections that matter to a subagent" \
  '.hookSpecificOutput.additionalContext | contains("## Git: local changes only") and contains("## Real environments: read-only") and contains("## 3. Test first") and contains("## 4. Debug systematically") and contains("## 5. Best solution, not overcomplicated") and contains("## 6. Verify before claiming done")'
check "subagent-start keeps its intro lines" \
  '.hookSpecificOutput.additionalContext | contains("You are a subagent.") and contains("You can\u0027t talk to the user") and contains("The orchestrator\u0027s brief is the user\u0027s OK") and contains("never permission to change a real environment") and contains("Skip the `Size:` label and the team/refuter requirement")'
check "subagent-start leaves out the orchestrator-only sections" \
  '.hookSpecificOutput.additionalContext | (contains("## Match the process") or contains("## 1. Understand") or contains("## 2. Plan") or contains("## 7. Hand off") or contains("## Subagents") or contains("# How to work with me")) | not'
out=$(cat "$ROOT/hooks/hooks.json")
check "hooks.json registers SubagentStart" '.hooks.SubagentStart[0].hooks[0].command | contains("subagent-start")'

# Claude Code lists plugin skills itself, so session-start only lists them elsewhere
run session-start CLAUDE_PLUGIN_ROOT="$ROOT"
check "session-start claude: rules but no duplicate skill list" \
  '.hookSpecificOutput.additionalContext | contains("Never run `git commit`") and (contains("Skills (duty-framework)") | not)'
for cli in copilot unknown; do
  if [ $cli = copilot ]; then run session-start CLAUDE_PLUGIN_ROOT="$ROOT" COPILOT_CLI=1; else run session-start; fi
  for skill in design plan tdd debugging verify-and-handoff team agents explain prior-art; do
    check "session-start $cli lists skill $skill" ".additionalContext | contains(\"- $skill:\")"
  done
done

ok_or_fail() { # name, condition exit status
  if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}
[ -s "$RUN_HOME/.copilot/settings.json" ]
ok_or_fail "run() isolates HOME so session-start writes to RUN_HOME, not caller HOME" $?
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
  # Copilot: frontmatter has tools and no model (model/effort live in ~/.copilot/settings.json)
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
ver=$(jq -r '.version // empty' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null)
[[ $ver =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; ok_or_fail "claude manifest has a semver version ($ver)" $?
out=$(cat "$ROOT/.claude-plugin/marketplace.json")
check "marketplace duty-framework version matches the claude manifest" ".plugins[0].name == \"duty-framework\" and .plugins[0].version == \"$ver\" and (\"$ver\" != \"\")"
tf_version=$(jq -r .version "$ROOT/plugins/duty-terraform/.claude-plugin/plugin.json" 2>/dev/null)
check "marketplace lists duty-terraform at the add-on's manifest version" \
  ".plugins[1].name == \"duty-terraform\" and .plugins[1].source == \"./plugins/duty-terraform\" and (.plugins[1].version == \"$tf_version\") and (\"$tf_version\" != \"\")"
out=$(cat "$ROOT/plugins/duty-terraform/.plugin/plugin.json" 2>/dev/null)
check "duty-terraform copilot manifest version matches the claude manifest" ".version == \"$tf_version\" and (\"$tf_version\" != \"\")"
out=$(cat "$ROOT/.claude-plugin/marketplace.json")
an_version=$(jq -r .version "$ROOT/plugins/duty-ansible/.claude-plugin/plugin.json" 2>/dev/null)
check "marketplace lists duty-ansible at the add-on's manifest version" \
  ".plugins[2].name == \"duty-ansible\" and .plugins[2].source == \"./plugins/duty-ansible\" and (.plugins[2].version == \"$an_version\") and (\"$an_version\" != \"\")"
out=$(cat "$ROOT/plugins/duty-ansible/.plugin/plugin.json" 2>/dev/null)
check "duty-ansible copilot manifest version matches the claude manifest" ".version == \"$an_version\" and (\"$an_version\" != \"\")"
out=$(cat "$ROOT/.plugin/plugin.json" 2>/dev/null)
check "copilot manifest points at copilot-agents, same version" ".name == \"duty-framework\" and .agents == \"./copilot-agents\" and .version == \"$ver\" and (\"$ver\" != \"\")"

# scripts/bump, only ever against a copy (DUTY_ROOT)
BT=$(mktemp -d)
mkdir -p "$BT/.claude-plugin" "$BT/.plugin" "$BT/plugins/duty-terraform/.claude-plugin" "$BT/plugins/duty-terraform/.plugin" \
  "$BT/plugins/duty-ansible/.claude-plugin" "$BT/plugins/duty-ansible/.plugin"
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json .plugin/plugin.json plugins/duty-terraform/.claude-plugin/plugin.json plugins/duty-terraform/.plugin/plugin.json \
  plugins/duty-ansible/.claude-plugin/plugin.json plugins/duty-ansible/.plugin/plugin.json; do
  cp "$ROOT/$f" "$BT/$f"
done
bsum() { (cd "$BT" && cat .claude-plugin/plugin.json .plugin/plugin.json plugins/duty-terraform/.claude-plugin/plugin.json plugins/duty-terraform/.plugin/plugin.json \
  plugins/duty-ansible/.claude-plugin/plugin.json plugins/duty-ansible/.plugin/plugin.json | cksum); }
jv() { jq -r "$2" "$BT/$1"; }
before=$(bsum)
mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
chmod 640 "$BT/.claude-plugin/plugin.json" "$BT/.claude-plugin/marketplace.json" "$BT/plugins/duty-terraform/.claude-plugin/plugin.json"
chmod 664 "$BT/plugins/duty-terraform/.plugin/plugin.json"
tf_before=$(jv plugins/duty-terraform/.claude-plugin/plugin.json .version)
out=$(DUTY_ROOT="$BT" "$ROOT/scripts/bump" duty-terraform 7.8.9 2>&1); rc=$?
[ $rc -eq 0 ] && [ "$(jv plugins/duty-terraform/.claude-plugin/plugin.json .version)" = 7.8.9 ] \
  && [ "$(jv plugins/duty-terraform/.plugin/plugin.json .version)" = 7.8.9 ] \
  && [ "$(jv .claude-plugin/marketplace.json '.plugins[] | select(.name == "duty-terraform") | .version')" = 7.8.9 ]
ok_or_fail "bump duty-terraform sets its manifests and marketplace entry" $?
[ "$(jv .claude-plugin/marketplace.json '.plugins[] | select(.name == "duty-framework") | .version')" = "$ver" ] \
  && [ "$(jv .claude-plugin/plugin.json .version)" = "$ver" ] && [ "$(jv .plugin/plugin.json .version)" = "$ver" ] \
  && [ "$(jv plugins/duty-ansible/.claude-plugin/plugin.json .version)" = "$an_version" ] \
  && [ "$(jv .claude-plugin/marketplace.json '.plugins[] | select(.name == "duty-ansible") | .version')" = "$an_version" ]
ok_or_fail "bump duty-terraform leaves duty-framework and duty-ansible untouched" $?
printf '%s' "$out" | grep -q '7.8.9' && printf '%s' "$out" | grep -q "$tf_before"
ok_or_fail "bump prints what it changed (old and new version)" $?
[ "$(mode "$BT/.claude-plugin/marketplace.json")" = 640 ] && [ "$(mode "$BT/plugins/duty-terraform/.claude-plugin/plugin.json")" = 640 ] \
  && [ "$(mode "$BT/plugins/duty-terraform/.plugin/plugin.json")" = 664 ]
ok_or_fail "bump keeps the manifests' file mode (not mktemp's 0600)" $?
an_before=$(jv plugins/duty-ansible/.claude-plugin/plugin.json .version)
out=$(DUTY_ROOT="$BT" "$ROOT/scripts/bump" duty-ansible 4.5.6 2>&1); rc=$?
[ $rc -eq 0 ] && [ "$(jv plugins/duty-ansible/.claude-plugin/plugin.json .version)" = 4.5.6 ] \
  && [ "$(jv plugins/duty-ansible/.plugin/plugin.json .version)" = 4.5.6 ] \
  && [ "$(jv .claude-plugin/marketplace.json '.plugins[] | select(.name == "duty-ansible") | .version')" = 4.5.6 ] \
  && [ "$(jv plugins/duty-terraform/.claude-plugin/plugin.json .version)" = 7.8.9 ] && [ "$(jv .claude-plugin/plugin.json .version)" = "$ver" ]
ok_or_fail "bump duty-ansible sets its manifests and marketplace entry only (was $an_before)" $?
out=$(DUTY_ROOT="$BT" "$ROOT/scripts/bump" duty-framework 3.2.1 2>&1); rc=$?
[ $rc -eq 0 ] && [ "$(jv .claude-plugin/plugin.json .version)" = 3.2.1 ] && [ "$(jv .plugin/plugin.json .version)" = 3.2.1 ] \
  && [ "$(jv .claude-plugin/marketplace.json '.plugins[] | select(.name == "duty-framework") | .version')" = 3.2.1 ] \
  && [ "$(jv plugins/duty-terraform/.claude-plugin/plugin.json .version)" = 7.8.9 ] \
  && [ "$(jv .claude-plugin/marketplace.json '.plugins[] | select(.name == "duty-terraform") | .version')" = 7.8.9 ] \
  && [ "$(jv plugins/duty-ansible/.claude-plugin/plugin.json .version)" = 4.5.6 ] \
  && [ "$(jv .claude-plugin/marketplace.json '.plugins[] | select(.name == "duty-ansible") | .version')" = 4.5.6 ]
ok_or_fail "bump duty-framework sets its three files, not the add-ons" $?
jq -e . "$BT/.claude-plugin/marketplace.json" "$BT/.claude-plugin/plugin.json" "$BT/.plugin/plugin.json" >/dev/null 2>&1
ok_or_fail "bump leaves valid JSON" $?
after=$(bsum)
for args in "duty-framework 1.2" "duty-framework v1.2.3" "duty-framework 1.2.3.4" "duty-framework" "other-plugin 1.2.3" "" "duty-framework 1.2.3 extra"; do
  # shellcheck disable=SC2086
  out=$(DUTY_ROOT="$BT" "$ROOT/scripts/bump" $args 2>&1 >/dev/null); rc=$?
  [ $rc -eq 2 ] && printf '%s' "$out" | grep -qi usage && [ "$(bsum)" = "$after" ]
  ok_or_fail "bump rejects bad args with usage and exit 2, changing nothing: '$args'" $?
done
rm -rf "$BT"


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
P show copilot | grep -E '^scout +gpt-5.4 +low' >/dev/null \
  && P show copilot | grep -E '^researcher +claude-sonnet-5.5 +high' >/dev/null \
  && P show copilot | grep -E '^builder +gemini-4-argon +high' >/dev/null \
  && P show copilot | grep -E '^refuter +claude-opus-5.5 +high' >/dev/null \
  && P show copilot | grep -E '^debugger +gpt-6.1-sol +default' >/dev/null
ok_or_fail "personalize show copilot includes repo defaults for unset roles" $?

bad=0
for args in "set agy scout flash high" "set agy scout claude-sonnet-5" "set copilot scout nope" "set claude scout claude-haiku-4-5 high" "set claude nobody sonnet" "set vim scout sonnet" "apply vim" "apply copilot nobody" "apply copilot scout extra"; do
  P $args >/dev/null 2>&1 && { echo "     accepted: $args"; bad=1; }
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
out=$(cat "$CS"); check "personalize default restores copilot repo default, keeps the rest" \
  '.theme == "dark" and .subagents.agents["other:agent"].model == "gpt-5.4" and .subagents.agents["duty-framework:scout"] == {"model":"claude-haiku-5.5","effortLevel":"medium"}'
out=$(cat "$CFG" 2>/dev/null); check "personalize default clears saved choices" '[.claude.scout, .copilot.scout, .agy.scout] == [null, null, null]'
echo '{"theme":"dark"}' > "$CS"; P apply >/dev/null 2>&1
out=$(cat "$CS"); check "personalize apply writes copilot repo defaults for all roles" \
  '.theme == "dark" and .subagents.agents["duty-framework:scout"] == {"model":"claude-haiku-5.5","effortLevel":"medium"} and .subagents.agents["duty-framework:researcher"] == {"model":"claude-sonnet-5.5","effortLevel":"high"} and .subagents.agents["duty-framework:builder"] == {"model":"gemini-4-argon","effortLevel":"high"} and .subagents.agents["duty-framework:refuter"] == {"model":"claude-opus-5.5","effortLevel":"high"} and .subagents.agents["duty-framework:debugger"] == {"model":"gpt-6.1-sol"}'
rm -f "$H/.copilot/settings.json"
env -u CLAUDE_PLUGIN_ROOT -u XDG_CONFIG_HOME -u COPILOT_HOME HOME="$H" COPILOT_CLI=1 "$ROOT/hooks/session-start" </dev/null >/dev/null 2>&1
out=$(cat "$CS"); check "session-start under Copilot creates settings.json with all role defaults when missing" \
  '.subagents.agents["duty-framework:scout"] == {"model":"claude-haiku-5.5","effortLevel":"medium"} and .subagents.agents["duty-framework:researcher"] == {"model":"claude-sonnet-5.5","effortLevel":"high"} and .subagents.agents["duty-framework:builder"] == {"model":"gemini-4-argon","effortLevel":"high"} and .subagents.agents["duty-framework:refuter"] == {"model":"claude-opus-5.5","effortLevel":"high"} and .subagents.agents["duty-framework:debugger"] == {"model":"gpt-6.1-sol"}'
echo '{"theme":"dark","subagents":{"agents":{"duty-framework:scout":{"model":"gpt-5.4","effortLevel":"low"}}}}' > "$CS"
env -u CLAUDE_PLUGIN_ROOT -u XDG_CONFIG_HOME -u COPILOT_HOME HOME="$H" COPILOT_CLI=1 "$ROOT/hooks/session-start" </dev/null >/dev/null 2>&1
out=$(cat "$CS"); check "session-start under Copilot seeds missing role defaults without overwriting existing choice" \
  '.subagents.agents["duty-framework:scout"] == {"model":"gpt-5.4","effortLevel":"low"} and .subagents.agents["duty-framework:refuter"] == {"model":"claude-opus-5.5","effortLevel":"high"} and .subagents.agents["duty-framework:debugger"] == {"model":"gpt-6.1-sol"}'
echo '{invalid' > "$CS"
env -u CLAUDE_PLUGIN_ROOT -u XDG_CONFIG_HOME -u COPILOT_HOME HOME="$H" COPILOT_CLI=1 "$ROOT/hooks/session-start" </dev/null >/dev/null 2>&1
[ -z "$(find "$H/.copilot" -name 'settings.json.*' 2>/dev/null)" ]
ok_or_fail "session-start leaves no temp files when settings.json is malformed" $?
rm -f "$CS" "$CFG" "$CA" "$GA"
P apply >/dev/null 2>&1
[ ! -e "$CS" ] && P apply copilot >/dev/null 2>&1 && [ -s "$CS" ]
ok_or_fail "personalize apply with no args does not create ~/.copilot/settings.json; apply copilot does" $?
rm -rf "$T" "$RUN_HOME"

has() { grep -qF -- "$2" "$ROOT/$1"; }
TMPDIR_EXPLAIN=$(mktemp -d)
# explain skill: read-only walkthrough with size, diagrams, 3-5 suggestions, and an offer to save as Markdown
field "$ROOT/skills/explain/SKILL.md" name | grep -qx explain && field "$ROOT/skills/explain/SKILL.md" description | grep -qi 'explain'
ok_or_fail "explain skill has name and description" $?
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Size: small\nRepo size: large"}]}}' \
  '{"type":"user","message":{"role":"user","content":"yes, write FLOW.md"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Write","input":{"file_path":"FLOW.md","content":"x"}}]}}' > "$TMPDIR_EXPLAIN/t.jsonl"
out=$(printf '{"transcript_path":"%s"}' "$TMPDIR_EXPLAIN/t.jsonl" | CLAUDE_PLUGIN_ROOT="$ROOT" "$ROOT/hooks/stop-gate" 2>/dev/null)
! printf '%s' "$out" | grep -q '"block"'
ok_or_fail "stop-gate lets explain write FLOW.md after Size: small" $?
rm -rf "$TMPDIR_EXPLAIN"
# prior-art skill: search for existing tools before building, ask the user, never install what it finds
field "$ROOT/skills/prior-art/SKILL.md" name | grep -qx prior-art && field "$ROOT/skills/prior-art/SKILL.md" description | grep -qi 'existing'
ok_or_fail "prior-art skill has name and description" $?
run subagent-start CLAUDE_PLUGIN_ROOT="$ROOT"
check "subagent-start tells subagents to skip the Size: label" '.hookSpecificOutput.additionalContext | ascii_downcase | contains("skip the `size:` label")'
check "subagent-start: the orchestrator's brief counts as the user's OK" '.hookSpecificOutput.additionalContext | contains("The orchestrator\u0027s brief is the user\u0027s OK")'
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
  out=$(jq -cn --arg p "$G/$1.jsonl" --arg m "${2:-}" --argjson a "${3:-false}" --arg s "${GSESS:-}" \
    '{transcript_path:$p,last_assistant_message:$m,stop_hook_active:$a} + (if $s == "" then {} else {session_id:$s} end)' \
    | env -u DUTY_DEBUG CLAUDE_PLUGIN_DATA="${GDATA:-$G/nodata}" CLAUDE_PLUGIN_ROOT="$ROOT" "$ROOT/hooks/stop-gate" 2>&1); rc=$?
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
# background builder: no refuter needed until its task-notification (status any) arrives
BG()   { jq -cn --arg s "$1" --arg id "$2" --argjson b "${3:-\"true\"}" '{type:"assistant",message:{content:[{type:"tool_use",id:$id,name:"Agent",input:{subagent_type:$s,run_in_background:$b}}]}}'; }
DONE() { jq -cn --arg id "$1" --arg st "${2:-completed}" '{type:"attachment",attachment:{type:"queued_command",prompt:("<task-notification>\n<task-id>a1</task-id>\n<tool-use-id>\($id)</tool-use-id>\n<status>\($st)</status>\n</task-notification>")}}'; }
fx n1 "$(txt 'Size: medium')" "$(BG duty-builder b1)"; allows "medium, background builder still running" n1
fx n2 "$(txt 'Size: medium')" "$(BG duty-builder b1 true)"; allows "background builder, run_in_background as boolean" n2
fx n3 "$(txt 'Size: medium')" "$(BG duty-builder b1)" "$(DONE b1)"; blocks "medium, background builder reported back, no refuter" n3
fx n4 "$(txt 'Size: medium')" "$(BG duty-builder b1)" "$(DONE b1 failed)"; blocks "background builder failed counts as reported back" n4
fx n5 "$(txt 'Size: medium')" "$(BG duty-builder b1)" "$(DONE b1)" "$(AG duty-refuter)"; allows "background builder reported back, then refuter" n5
fx n6 "$(txt 'Size: medium')" "$(BG duty-builder b1)" "$(DONE b2)"; allows "notification for another task doesn't count" n6
fx n7 "$(txt 'Size: medium')" "$(BG duty-builder b1)" "$(DONE b1)" "$(BG duty-builder b2)"; allows "second background builder still running" n7
fx n8 "$(txt 'Size: medium')" "$(BG duty-builder b1)" "$(W)"; allows "edit while a background builder runs" n8
fx n9 "$(txt 'Size: medium')" "$(BG duty-builder b1 false)"; blocks "foreground builder (run_in_background false) unchanged" n9
# resumed session: the "stopped" notification carries only the task-id (the agentId from the launch result)
LR()   { jq -cn --arg id "$1" --arg ag "$2" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:$id,content:[{type:"text",text:("Async agent launched successfully.\nagentId: \($ag) (internal ID - do not mention to user.)")}]}]}}'; }
STOP() { jq -cn --arg ag "$1" '{type:"user",message:{role:"user",content:("<task-notification>\n<task-id>\($ag)</task-id>\n<status>stopped</status>\n<summary>Background agent didn'"'"'t finish before the previous session ended</summary>\n</task-notification>")}}'; }
fx p1 "$(txt 'Size: medium')" "$(BG duty-builder b1)" "$(LR b1 a1)" "$(STOP a1)"; blocks "background builder stopped on resume (task-id only) counts as reported back" p1
fx p2 "$(txt 'Size: medium')" "$(BG duty-builder b1)" "$(LR b1 a1)" "$(STOP a9)"; allows "task-id of another agent doesn't count" p2
fx p3 "$(txt 'Size: medium')" "$(BG duty-builder b1)" "$(LR b2 a1)" "$(STOP a1)"; allows "agentId from another launch doesn't count" p3
TWO()  { jq -cn '{type:"user",message:{role:"user",content:"<task-notification>\n<task-id>a1</task-id>\n<tool-use-id>b1</tool-use-id>\n<status>completed</status>\n</task-notification>\n<task-notification>\n<task-id>a2</task-id>\n<tool-use-id>b2</tool-use-id>\n<status>completed</status>\n</task-notification>"}}'; }
fx p4 "$(txt 'Size: medium')" "$(BG duty-builder b1)" "$(BG duty-builder b2)" "$(TWO)"; blocks "two notifications in one message both count" p4
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
fx r11 "$(txt 'Size: medium')" "$(W /home/u/proj/.copilot/agents/x.md)"
blocks "Write under /.copilot/ counts as edit" r11
for l in '{"type":7}' '{"type":["x"]}'; do
  fx r12 "$(txt 'Size: medium')" "$l" "$(W)"; blocks "line with non-string type doesn't switch the gate off: $l" r12
done
# resuming a refuter with SendMessage counts as a review: matched by the agentId from its result or its name
RF()   { jq -cn --arg id "$1" --arg s "${2:-duty-refuter}" --arg n "${3:-}" '{type:"assistant",message:{content:[{type:"tool_use",id:$id,name:"Agent",input:({subagent_type:$s} + (if $n == "" then {} else {name:$n} end))}]}}'; }
SM()   { tool SendMessage "{\"to\":\"$1\",\"message\":\"re-check\"}"; }
fx t1 "$(txt 'Size: medium')" "$(RF r1)" "$(LR r1 a1)" "$(W)" "$(SM a1)"
allows "SendMessage to a refuter's agentId after the last edit" t1
fx t2 "$(txt 'Size: medium')" "$(RF r1)" "$(LR r1 a1)" "$(W)" "$(SM a9)"
blocks "SendMessage to another agentId doesn't count" t2
fx t3 "$(txt 'Size: medium')" "$(RF r1 duty-refuter rev)" "$(W)" "$(SM rev)"
allows "SendMessage to a refuter's name after the last edit" t3
fx t4 "$(txt 'Size: medium')" "$(RF b1 duty-builder bob)" "$(LR b1 a1)" "$(W)" "$(SM a1)" "$(SM bob)"
blocks "SendMessage to a builder doesn't count" t4
fx t5 "$(txt 'Size: medium')" "$(RF r1)" "$(LR r1 a1)" "$(SM a1)" "$(W)"
blocks "SendMessage to a refuter before the last edit doesn't count" t5
# the agentId trailer comes last; an id quoted in the agent's report doesn't count
LRT()  { jq -cn --arg id "$1" --arg t "$2" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:$id,content:[{type:"text",text:$t}]}]}}'; }
fx t6 "$(txt 'Size: medium')" "$(RF b1 duty-builder)" "$(LR b1 bld1)" "$(RF r1)" "$(LRT r1 $'FINDINGS: builder agentId: bld1 left a bug\nagentId: ref1')" "$(W)" "$(SM bld1)"
blocks "SendMessage to an agentId quoted in a refuter report doesn't count" t6
fx t7 "$(txt 'Size: medium')" "$(RF r1)" "$(LRT r1 $'CONFIRMED; checked agentId: zz9\nagentId: ref1')" "$(W)" "$(SM ref1)"
allows "SendMessage to the refuter's trailer agentId counts" t7
# a refuter result without an agentId trailer gives no ref: a SendMessage without (or with null) to doesn't match it
for to in '' ',"to":null'; do
  fx t8 "$(txt 'Size: medium')" "$(RF r1)" "$(LRT r1 'Agent interrupted by user')" "$(W)" "$(tool SendMessage "{\"message\":\"re-check\"$to}")"
  blocks "SendMessage without a to after a refuter without agentId doesn't count${to:+ (to null)}" t8
done

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

# Copilot CLI: transcriptPath points at its events.jsonl; subagent events carry agentId or data.parentToolCallId
CT()   { jq -cn --arg t "$1" '{type:"assistant.message",data:{content:$t,toolRequests:[]}}'; }
CU()   { jq -cn --arg t "$1" '{type:"user.message",data:{content:$t}}'; }
CTOOL() { jq -cn --arg n "$1" --argjson a "$2" --arg id "${3:-c1}" '{type:"tool.execution_start",data:{toolCallId:$id,toolName:$n,arguments:$a}}'; }
CE()   { CTOOL "${2:-edit}" "{\"path\":\"${1:-/x/a.md}\"}"; }
CAG()  { CTOOL task "{\"agent_type\":\"$1\",\"prompt\":\"p\"${3:+,\"mode\":\"$3\"}}" "${2:-c1}"; }
CTEAM() { CTOOL skill '{"skill":"team"}'; }
CSUB() { printf '%s' "$1" | jq -c '.agentId = "s1"'; }   # wraps an event as a subagent's
COLD() { printf '%s' "$1" | jq -c '.data.parentToolCallId = "c1"'; }   # older subagent marker
CDONE() { jq -cn --arg t "subagent.${2:-completed}" --arg id "$1" '{type:$t,agentId:"s1",data:{toolCallId:$id}}'; }
cgate() { # fixture, stop_hook_active
  out=$(jq -cn --arg p "$G/$1.jsonl" --argjson a "${2:-false}" '{transcriptPath:$p,stop_hook_active:$a}' \
    | CLAUDE_PLUGIN_ROOT="$ROOT" COPILOT_CLI=1 "$ROOT/hooks/stop-gate" 2>&1); rc=$?
}
cblocks() { # name, fixture, [extra jq]
  cgate "$2"; [ $rc -eq 0 ] || out=''
  check "stop-gate copilot blocks: $1" ".decision == \"block\" and (.reason | startswith(\"duty-framework:\")) and (${3:-true})"
}
callows() { # name, fixture
  cgate "$2"
  [ $rc -eq 0 ] && { [ -z "$out" ] || printf '%s' "$out" | jq -e '(.decision // null) == null' >/dev/null 2>&1; }
  ok_or_fail "stop-gate copilot allows: $1" $?
}
fx ca "$(CU go)" "$(CT 'Size: medium')" "$(CE)"
cblocks "medium, edit, no refuter" ca '.reason | contains("refuter") and (contains("team") | not)'
fx cb "$(CU go)" "$(CT 'Size: medium')" "$(CE)" "$(CAG duty-framework:refuter)"
callows "medium with refuter" cb
fx cc "$(CU go)" "$(CT 'Size: large')" "$(CE)" "$(CAG duty-framework:refuter)"
cblocks "large without team skill" cc '.reason | contains("team")'
fx cd "$(CU go)" "$(CT 'Size: large')" "$(CTEAM)" "$(CE)" "$(CAG duty-framework:refuter)"
callows "large with team and refuter" cd
fx ce "$(CU go)" "$(CT 'Size: medium')" "$(CE /x/b.md create)"
cblocks "create counts as edit" ce
fx cf "$(CU go)" "$(CT 'Size: medium')" "$(CAG duty-framework:builder)"
cblocks "builder counts as edit" cf
fx cg "$(CU go)" "$(CT 'Size: medium')" "$(CAG duty-framework:scout)" "$(CSUB "$(CE)")" "$(COLD "$(CE)")"
callows "a subagent's own edits don't count as the main agent's" cg
fx ch "$(CU go)" "$(CT 'Size: medium')" "$(CE)" "$(CSUB "$(CU brief)")" "$(CSUB "$(CT 'Size: small')")"
cblocks "subagent prompt is no turn boundary, subagent text no label" ch
fx ci "$(CU go)" "$(CT 'Size: medium')" "$(CU next)" "$(CE)"
cblocks "label from an earlier turn applies" ci
fx cj "$(CU go)" "$(CE)" "$(CT 'Size: medium — done')"
callows "label after an edit in the same turn is ignored" cj
fx ck "$(CU go)" "$(CT 'Size: medium')" "$(CE /home/u/.copilot/session-state/x/plan.md)"
callows "edits under /.copilot/ don't count" ck
fx cl "$(CU go)" "$(CT 'Size: small')" "$(CE)"
callows "small" cl
fx cm "$(CU go)" "$(CT 'Size: medium')" "$(CAG duty-framework:builder b1 background)"
callows "background builder still running" cm
fx cn "$(CU go)" "$(CT 'Size: medium')" "$(CAG duty-framework:builder b1 background)" "$(CDONE b1)"
cblocks "background builder completed, no refuter" cn
fx co "$(CU go)" "$(CT 'Size: medium')" "$(CAG duty-framework:builder b1 background)" "$(CDONE b1 failed)"
cblocks "background builder failed counts as reported back" co
fx cp "$(CU go)" "$(CT 'Size: medium')" "$(CAG duty-framework:builder b1 background)" "$(CDONE b2)"
callows "completion of another subagent doesn't count" cp
# Copilot hands the block reason back as a user.message: no turn boundary, so a new label after it doesn't count
CBLK() { CU 'duty-framework: Size: medium task with edits but no refuter review after the last edit. Run a refuter subagent on the final changes (send back findings, max 2 rounds), then hand off.'; }
fx cq "$(CU go)" "$(CT 'Size: medium')" "$(CE)" "$(CBLK)" "$(CT 'Size: medium — reviewed it myself')"
cblocks "re-label after the block message doesn't reset the gate" cq
fx cr "$(CU go)" "$(CT 'Size: medium')" "$(CE)" "$(CBLK)" "$(CT 'Size: small')"
cblocks "Size: small after the block message doesn't reset the gate" cr
fx cs "$(CU go)" "$(CT 'Size: medium')" "$(CE)" "$(CBLK)" "$(CAG duty-framework:refuter)"
callows "refuter after the block message" cs
fx ct "$(CU go)" "$(CT 'Size: medium')" "$(CTOOL apply_patch '{"input":"*** Begin Patch\n*** Update File: /x/a\n"}')"
cblocks "apply_patch counts as edit" ct
fx cu "$(CU go)" "$(CT 'Size: medium')" "$(CTOOL apply_patch '{"input":"*** Begin Patch\n*** Update File: /home/u/.copilot/session-state/x/plan.md\n"}')"
callows "apply_patch under /.copilot/ doesn't count" cu
fx cv "$(CU go)" "$(CT 'Size: medium')" "$(CE)" '{"type":"weird","data":"str"}'
cblocks "event with non-object data doesn't switch the gate off" cv
# apply_patch: only the *** Add/Update/Delete File: lines name files; arguments may be {input} or a raw string
PATCH='*** Begin Patch\n*** Update File: /x/README.md\n@@\n- see ~/.copilot/settings.json\n+ see ~/.copilot/settings.json\n*** End Patch\n'
fx cw1 "$(CU go)" "$(CT 'Size: medium')" "$(CTOOL apply_patch "{\"input\":\"$PATCH\"}")"
cblocks "apply_patch that mentions /.copilot/ in its text counts as edit" cw1
fx cw2 "$(CU go)" "$(CT 'Size: medium')" "$(CTOOL apply_patch "\"$PATCH\"")"
cblocks "apply_patch with a raw string argument" cw2
fx cw3 "$(CU go)" "$(CT 'Size: medium')" "$(CTOOL apply_patch '{"input":"*** Begin Patch\n*** Add File: /home/u/.copilot/a.md\n+x\n*** Update File: /x/b.md\n*** End Patch\n"}')"
cblocks "apply_patch touching a file outside /.copilot/ counts" cw3
fx cw4 "$(CU go)" "$(CT 'Size: medium')" "$(CTOOL apply_patch '"*** Begin Patch\n*** Delete File: /home/u/.copilot/a.md\n*** Update File: /home/u/.copilot/b.md\n*** End Patch\n"')"
callows "apply_patch touching only /.copilot/ files" cw4
fx cw6 "$(CU go)" "$(CT 'Size: medium')" "$(CTOOL apply_patch '{"input":"*** Begin Patch\n*** Update File: /home/u/.copilot/a.md\n*** Move to: /x/a.md\n*** End Patch\n"}')"
cblocks "apply_patch moving a file out of /.copilot/ counts" cw6
fx cw5 "$(CU go)" "$(CT 'Size: medium')" "$(CTOOL apply_patch '{"input":"/home/u/.copilot/x"}')"
cblocks "apply_patch without file lines counts as edit" cw5
fx cx "$(CU go)" "$(CT 'Size: medium')" "$(CE /home/u/proj/.claude/x.md)"
cblocks "edit under /.claude/ counts in Copilot" cx
fx cy1 '{"type":7}' "$(CU go)" "$(CT 'Size: medium')" "$(CE)"
cblocks "line with non-string type before the first message" cy1
fx cy2 "$(CU go)" "$(CT 'Size: medium')" "$(CTOOL edit '"oops"')"
cblocks "edit with non-object arguments counts as edit" cy2
fx cy3 "$(CU go)" "$(CT 'Size: medium')" "$(CE)" "$(CTOOL task '"oops"')"
cblocks "task with non-object arguments doesn't switch the gate off" cy3
fx cy4 "$(CU go)" "$(CT 'Size: medium')" "$(CE)" "$(CTOOL task '{"agent_type":7}' c2)"
cblocks "task with non-string agent_type doesn't switch the gate off" cy4
fx cy5 "$(CU go)" '{"type":"assistant.message","data":{"content":7}}' "$(CT 'Size: medium')" "$(CE)"
cblocks "assistant message with non-string content doesn't switch the gate off" cy5
fx cw7 "$(CU go)" "$(CT 'Size: medium')" "$(CTOOL apply_patch '"*** Begin Patch\n*** Update File: /x/.copilot/a\n  *** Update File: /src/b\n*** End Patch\n"')"
cblocks "apply_patch with an indented file line" cw7
# Bash edits: edit-track records the ids of Bash calls that changed the tree; stop-gate counts those as edits
GD="$G/data"
TB() { jq -cn --arg id "$1" '{type:"assistant",message:{content:[{type:"tool_use",id:$id,name:"Bash",input:{command:"sed -i s/a/b/ f"}}]}}'; }
bashedits() { # session, ids...
  local s="$1"; shift; mkdir -p "$GD/sessions/$s"; printf '%s\n' "$@" > "$GD/sessions/$s/bash-edits"
}
bashedits sg1 X1
fx bx1 "$(txt 'Size: medium')" "$(TB X1)"
GSESS=sg1 GDATA=$GD blocks "medium, Bash call listed in bash-edits, no refuter" bx1 '.reason | contains("refuter")'
fx bx2 "$(txt 'Size: medium')" "$(TB X1)" "$(AG duty-framework:refuter)"
GSESS=sg1 GDATA=$GD; allows "medium, Bash edit then refuter" bx2
fx bx3 "$(txt 'Size: medium')" "$(TB X1)" "$(AG duty-framework:refuter)" "$(TB Y1)"
GSESS=sg1 GDATA=$GD; allows "medium, Bash call not in bash-edits after the refuter" bx3
fx bx4 "$(txt 'Size: medium')" "$(TB Y1)"
GSESS=sg1 GDATA=$GD; allows "medium, Bash call not in bash-edits is no edit" bx4
GSESS=sg-none GDATA=$GD; allows "medium, Bash id listed but session has no bash-edits" bx1
GSESS=sg1 GDATA=$G/other; allows "medium, bash-edits in another data dir doesn't count" bx1
bashedits sgodd X1
GSESS='sg/../odd' GDATA=$GD blocks "medium, session id sanitized to [A-Za-z0-9_-]" bx1 true
unset GSESS GDATA
# DUTY_DEBUG=1 appends one line per invocation to <data>/stop-gate.log; otherwise nothing is written
dbg() { # fixture, session, data dir, env...
  local f="$1" s="$2" d="$3"; shift 3
  out=$(jq -cn --arg p "$G/$f.jsonl" --arg s "$s" '{transcript_path:$p,session_id:$s}' \
    | env -u DUTY_DEBUG CLAUDE_PLUGIN_DATA="$d" CLAUDE_PLUGIN_ROOT="$ROOT" "$@" "$ROOT/hooks/stop-gate" 2>&1); rc=$?
}
dbg bx1 sg1 "$G/dbg0"
[ $rc -eq 0 ] && [ ! -e "$G/dbg0" ]; ok_or_fail "stop-gate without DUTY_DEBUG writes no log" $?
dbg bx1 sg1 "$GD" DUTY_DEBUG=1
check "stop-gate DUTY_DEBUG=1 still blocks on stdout" '.decision == "block"'
dbg bx2 sg1 "$GD" DUTY_DEBUG=1
[ $rc -eq 0 ] && [ -z "$out" ]; ok_or_fail "stop-gate DUTY_DEBUG=1 allow leaves stdout empty" $?
[ "$(wc -l < "$GD/stop-gate.log" 2>/dev/null)" = 2 ] && sed -n 1p "$GD/stop-gate.log" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T.* sg1 block: ' \
  && sed -n 2p "$GD/stop-gate.log" | grep -Eq ' sg1 allow'
ok_or_fail "stop-gate DUTY_DEBUG=1 logs one line per run: timestamp, session, block/allow" $?
mkdir -p "$G/ro/sessions/sg1"; printf 'X1\n' > "$G/ro/sessions/sg1/bash-edits"; chmod 500 "$G/ro"
dbg bx1 sg1 "$G/ro" DUTY_DEBUG=1
chmod 700 "$G/ro"
[ $rc -eq 0 ]; ok_or_fail "stop-gate DUTY_DEBUG=1 with unwritable log dir doesn't fail" $?
check "stop-gate DUTY_DEBUG=1 with unwritable log dir still blocks" '.decision == "block"'
# every exit path logs once, bad input included
printf 'not json' | env CLAUDE_PLUGIN_DATA="$G/dbg1" DUTY_DEBUG=1 "$ROOT/hooks/stop-gate" >/dev/null 2>&1; rc=$?
[ $rc -eq 0 ] && [ "$(wc -l < "$G/dbg1/stop-gate.log" 2>/dev/null)" = 1 ] && grep -Eq '^[0-9]{4}-.* - allow: bad input$' "$G/dbg1/stop-gate.log"
ok_or_fail "stop-gate DUTY_DEBUG=1 logs 'allow: bad input' on non-JSON input" $?
printf '{}' | env CLAUDE_PLUGIN_DATA="$G/dbg2" DUTY_DEBUG=1 "$ROOT/hooks/stop-gate" >/dev/null 2>&1; rc=$?
[ $rc -eq 0 ] && [ "$(wc -l < "$G/dbg2/stop-gate.log" 2>/dev/null)" = 1 ] && grep -q 'allow: no transcript$' "$G/dbg2/stop-gate.log"
ok_or_fail "stop-gate DUTY_DEBUG=1 logs once on input without a transcript" $?
rm -rf "$G"

# command-guard: PreToolUse on Bash, denies git writes and apply/deploy commands (Claude Code only)
guard() { # command, env...
  local c="$1"; shift
  out=$(jq -cn --arg c "$c" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}' \
    | env -u COPILOT_CLI -u DUTY_ALLOW_GIT_WRITE -u DUTY_ALLOW_APPLY CLAUDE_PLUGIN_ROOT="$ROOT" "$@" "$ROOT/hooks/command-guard" 2>&1); rc=$?
}
denies() { # group (git|apply), command, env...
  local g="$1" c="$2" var; shift 2
  [ "$g" = git ] && var=DUTY_ALLOW_GIT_WRITE || var=DUTY_ALLOW_APPLY
  guard "$c" "$@"
  [ $rc -eq 0 ] && [ -n "$out" ] && printf '%s' "$out" | jq -e --arg v "$var" '.hookSpecificOutput.hookEventName == "PreToolUse"
    and .hookSpecificOutput.permissionDecision == "deny"
    and (.hookSpecificOutput.permissionDecisionReason | startswith("duty-framework:") and contains($v))' >/dev/null 2>&1
  ok_or_fail "command-guard denies ($g): $c${*:+ [$*]}" $?
}
# apply/deploy commands ask (permission prompt) instead of denying; destructive ones carry a DESTRUCTIVE: marker
asks() { # command, env...
  local c="$1"; shift
  guard "$c" "$@"
  [ $rc -eq 0 ] && [ -n "$out" ] && printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"
    and .hookSpecificOutput.permissionDecision == "ask"
    and (.hookSpecificOutput.permissionDecisionReason | startswith("duty-framework:") and contains("DUTY_ALLOW_APPLY"))' >/dev/null 2>&1
  ok_or_fail "command-guard asks: $c${*:+ [$*]}" $?
}
asks_marked() { # yes|no (DESTRUCTIVE: marker expected), command
  local want="$1" c="$2"
  guard "$c"
  [ $rc -eq 0 ] && [ -n "$out" ] && printf '%s' "$out" | jq -e --arg w "$want" '.hookSpecificOutput.permissionDecision == "ask"
    and ((.hookSpecificOutput.permissionDecisionReason | startswith("duty-framework: DESTRUCTIVE:")) == ($w == "yes"))' >/dev/null 2>&1
  ok_or_fail "command-guard asks (destructive=$want): $c" $?
}
passes() { # command, env...
  local c="$1"; shift
  guard "$c" "$@"
  [ $rc -eq 0 ] && [ -z "$out" ]
  ok_or_fail "command-guard allows: $c${*:+ [$*]}" $?
}
for c in 'git commit -m x' 'git push' 'git push origin main --force' 'git merge main' 'git rebase main' 'git reset --hard' \
  'git stash' 'git stash pop' 'git cherry-pick abc' 'git revert abc' 'git checkout -- a.md' 'git restore a.md' \
  'git switch -c x' 'git checkout -b x' 'git branch x' 'git branch -D x' 'git branch -m y' 'git tag v1' \
  'gh pr create --fill' 'gh pr merge 1' 'git -C /x commit -m y' 'git -c user.name=a commit' '/usr/bin/git push' \
  'sudo git push' 'env A=1 git commit' 'A=1 B=2 git commit' 'time git push' 'git status && git commit -m x' \
  'ls; git push' 'true || git reset --hard' 'git diff | cat; git stash' $'git status\ngit commit' 'echo $(git push)' \
  'git commit -m "fix; push"' 'DUTY_ALLOW_GIT_WRITE=1 git commit' 'git -C "dir with space" push' \
  'git -c "user.name=A B" commit' $'git -C /x \\\n  commit -m y' 'git checkout -bfoo' 'git switch --create=foo' \
  'git push>out' 'sudo -u root git push' 'env -u FOO git push' 'nice -n 10 git push' 'timeout 60 git push' \
  'timeout -s KILL 60 git push' 'git -c user.email="a@b" commit -m x' 'git --git-dir="/r/.git" push' \
  'GIT_AUTHOR_NAME="A B" git commit -m x' "FOO='x' git push" 'git -C /repo switch -c x' 'git -C /repo branch -D x' \
  'git branch "quoted-name"'; do
  denies git "$c"
done
for c in 'terraform apply' 'terraform apply -auto-approve' 'terraform destroy' 'terraform import a.b id' \
  'terraform state rm a.b' 'terraform state mv a b' 'terraform state push f' 'terraform -chdir=infra apply' \
  'kubectl apply -f x.yaml' 'kubectl -n prod apply -f x' 'kubectl --context c delete pod x' 'kubectl create ns x' \
  'kubectl patch deploy x -p {}' 'kubectl replace -f x' 'kubectl scale deploy x --replicas=0' \
  'kubectl rollout restart deploy/x' 'kubectl apply --dry-run=none -f x' 'helm install a ./c' 'helm -n x upgrade a ./c' \
  'kubectl apply -f x.yaml --dry-run=false' 'helm upgrade x y --dry-run=false' 'kubectl apply -f x --dry-run=none' \
  'helm uninstall a' 'helm rollback a 1' 'terraform plan && terraform apply' 'DUTY_ALLOW_APPLY=1 terraform apply' \
  'kubectl -n "prod" apply -f x' "helm -n 'ns' upgrade a ./c" $'kubectl \\\n -n prod apply -f x' 'kubectl -v 6 apply -f x' \
  'kubectl --namespace="prod" apply -f x' 'helm --kube-context="c" upgrade r ch'; do
  asks "$c"
done
for c in 'git status' 'git diff HEAD' 'git log --oneline --grep=commit' 'git blame a.md' 'git show HEAD' 'git branch' \
  'git branch -a' 'git branch --list' 'git tag' 'git tag -l' 'git stash list' 'git -C /x status' 'git commit --dry-run' \
  'git push --dry-run' 'gh pr view 1' 'gh pr list' 'terraform plan -out=p' 'terraform validate' 'terraform fmt -recursive' \
  'terraform init -backend=false' 'terraform state list' 'terraform state show a.b' 'kubectl get pods -n x' \
  'kubectl -n prod describe pod x' 'kubectl diff -f x' 'kubectl apply --dry-run=client -f x' 'kubectl apply -f x --dry-run=client' 'kubectl apply -f x --dry-run=server' 'kubectl rollout status deploy/x' \
  'helm template a ./c' 'helm upgrade --dry-run a ./c' 'helm list' 'echo "git commit"' "grep -rn 'terraform apply' ." \
  'rg "kubectl delete" docs' 'ls -la' 'cat README.md | grep git' 'bash tests/test-hooks.sh' 'git tag -v v1' \
  'git tag --verify v1' 'terraform state mv -dry-run a b' 'git log > out.txt' 'timeout 60 git status' \
  'git branch --format="%(refname)"' 'git branch --sort "-committerdate"' 'git tag --sort "-v:refname"' \
  'git -C /repo switch main' 'git -C /repo branch' 'git -c color.ui=never branch'; do
  passes "$c"
done
# more apply/deploy tools: tofu, terragrunt, pulumi, package/image publishes, gh release, az, aws
for c in 'tofu apply' 'tofu destroy -auto-approve' 'tofu import a.b id' 'tofu state rm a.b' 'tofu state mv a b' 'tofu state push f' \
  'tofu -chdir=infra apply' 'terragrunt apply' 'terragrunt destroy' 'terragrunt import a.b id' 'terragrunt state rm a.b' \
  'terragrunt run-all apply' 'terragrunt run-all destroy' 'terragrunt run-all --terragrunt-non-interactive apply' \
  'terragrunt run --all apply' 'terragrunt run --all -- destroy' 'terragrunt --terragrunt-working-dir infra apply' \
  'pulumi up' 'pulumi up --yes' 'pulumi destroy' 'pulumi update' 'pulumi -C infra up' 'pulumi --stack prod destroy' \
  'npm publish' 'pnpm publish' 'yarn publish' 'yarn npm publish' 'npm publish --access public' \
  'docker push img:1' 'docker push registry.example.com/a/b:tag' \
  'gh release create v1 --notes x' 'gh -R o/r release create v1' \
  'az group delete -n x --yes' 'az vm create -g rg -n vm --image x' 'az vm update -g rg -n vm' 'az webapp restart -n w -g rg' \
  'az vm stop -n vm -g rg' 'az vm start -n vm -g rg' 'az keyvault purge --name kv' 'az role assignment create --role r' \
  'az account set --subscription s' 'az group lock add' 'az storage account delete -n delete -g rg' \
  'az --subscription s group delete -n x' 'az group delete --name=x' 'az vm show -n x -g y && az vm delete -n x -g y' \
  'aws s3 rm s3://b/k' 'aws s3 mv s3://a s3://b' 'aws s3 cp f s3://b/k' 'aws s3 sync . s3://b' 'aws s3 rb s3://b --force' \
  'aws s3api delete-bucket --bucket b' 'aws s3api put-object --bucket b --key k' 'aws ec2 terminate-instances --instance-ids i-1' \
  'aws iam create-user --user-name u' 'aws lambda update-function-code --function-name f' 'aws dynamodb put-item --table-name t' \
  'aws ec2 modify-instance-attribute --instance-id i' 'aws ec2 delete-security-group --group-id g' \
  'aws --region eu-west-1 ec2 terminate-instances --instance-ids i-1' 'aws --profile p s3 rm s3://b/k' \
  'aws --output json --query x iam delete-user --user-name u' 'aws --endpoint-url http://localhost:4566 s3 rb s3://b' \
  'aws sts get-caller-identity && aws s3 rm s3://b/k'; do
  asks "$c"
done
# az: only the command words (before the first option) count; aws: more write verbs, s3 direction; terragrunt -all, docker image push, gh release
for c in 'az vm start -g rg -n vm' 'az account set -s x' 'az group delete -n x' 'az --subscription s vm restart -n v' \
  'aws --color on s3 rm s3://x' 'aws --cli-read-timeout 5 ec2 delete-vpc --vpc-id x' 'aws --cli-connect-timeout 5 ec2 run-instances' \
  'aws --ca-bundle b.pem ec2 stop-instances --instance-ids i' 'aws --cli-binary-format raw-in-base64-out lambda invoke --function-name f out' \
  'aws ec2 run-instances --image-id x' 'aws ec2 start-instances --instance-ids i' 'aws ec2 stop-instances --instance-ids i' \
  'aws ec2 reboot-instances --instance-ids i' 'aws ec2 attach-volume --volume-id v' 'aws ec2 detach-volume --volume-id v' \
  'aws ec2 associate-address --instance-id i' 'aws ec2 disassociate-address --association-id a' 'aws ecs register-task-definition --family f' \
  'aws ecs deregister-task-definition --task-definition t' 'aws guardduty enable-organization-admin-account' 'aws guardduty disable-organization-admin-account' \
  'aws ec2 create-tags --resources r' 'aws ec2 tag-resource --r x' 'aws s3api untag-resource --x y' 'aws rds restore-db-instance-from-snapshot' \
  'aws ec2 import-image' 'aws ec2 revoke-security-group-ingress --group-id g' 'aws ec2 authorize-security-group-ingress --group-id g' \
  'aws ssm execute-command --x y' 'aws sqs send-message --queue-url q --message-body b' 'aws cloudformation deploy --template-file t --stack-name s' \
  'aws lambda invoke --function-name f out' 'aws sns publish --topic-arn t --message m' \
  'aws s3 mv s3://a ./local' 'aws s3 cp ./local s3://b/k --recursive' 'aws s3 cp --recursive . s3://b' 'aws s3 sync ./dir s3://b --exclude "*.log"' \
  'aws s3 sync s3://a s3://b' 'aws s3 cp s3://a/k s3://b/k' \
  'terragrunt apply-all' 'terragrunt destroy-all' 'terragrunt --terragrunt-working-dir infra apply-all' \
  'docker image push img:1' 'docker image push registry.example.com/a/b:tag' \
  'gh release delete v1' 'gh release upload v1 a.zip' 'gh release edit v1 --notes x' 'gh -R o/r release delete v1 -y'; do
  asks "$c"
done
for c in 'az group list' 'az account show' 'az vm show -n x -g y' 'az vm show -n delete -g rg' 'az vm show --name delete --resource-group rg' \
  'az group show -g update' 'az vm list -o table' 'az group list --query "[?name==\x27a\x27]" -o tsv' 'az account list --output json' \
  'az vm list --subscription create' 'az group list -l restart' 'az aks get-credentials -n c -g rg' 'az login' \
  'aws s3 ls' 'aws s3 ls s3://delete-me' 'aws ec2 describe-instances --region eu-west-1' 'aws sts get-caller-identity' \
  'aws s3api list-buckets' 'aws s3api get-object --bucket b --key k out' 'aws --profile delete-me s3 ls' \
  'aws --region eu-west-1 --output json ec2 describe-instances' 'aws ec2 describe-instances --query "Reservations[]"' \
  'aws configure set region eu-west-1' 'aws iam list-users --output text' \
  'npm install' 'npm test' 'npm pack' 'pnpm install' 'yarn install' 'npm publish --dry-run' 'docker build .' 'docker pull img' 'docker run --rm img' \
  'gh release list' 'gh release view v1' 'gh pr view 1' \
  'tofu plan' 'tofu validate' 'tofu fmt' 'tofu state list' 'tofu apply --dry-run' 'terragrunt plan' 'terragrunt run-all plan' \
  'terragrunt run --all plan' 'terragrunt hclfmt' 'pulumi preview' 'pulumi stack ls' 'pulumi up --dry-run' 'pulumi config get x' \
  'echo "az group delete"' "grep -rn 'aws s3 rm' ." 'ls delete-bucket' \
  'az storage blob list --container-name stop' 'az vm list --tag start' 'az monitor metrics list --metric restart' \
  'az vm list --resource-group rg --query "[?x]"' 'az network nsg rule list -g rg --nsg-name set' \
  'aws --color on s3 ls' 'aws --cli-read-timeout 5 ec2 describe-vpcs' 'aws s3 cp s3://b/k ./local' 'aws s3 sync s3://b ./dir' \
  'aws s3 cp s3://b/k - --region eu-west-1' 'aws s3 sync s3://b ./dir --exclude "*.log"' 'aws s3 cp f s3://b/k --dryrun' \
  'aws s3 rm s3://b/k --dryrun' 'aws s3 sync . s3://b --dry-run' \
  'aws ec2 describe-tags' 'aws ec2 describe-addresses' 'aws sqs receive-message --queue-url q' 'aws s3api get-bucket-tagging --bucket b' \
  'aws iam list-attached-user-policies --user-name u' 'aws ssm describe-instance-information' 'aws logs get-log-events --x y' \
  'terragrunt plan-all' 'terragrunt run-all plan' 'docker image ls' 'docker image pull img' 'docker image build .' \
  'gh release download v1' 'gh release create v1 --dry-run' 'gh release view v1'; do
  passes "$c"
done
# apply/deploy asks; destructive verbs and flags carry the DESTRUCTIVE: marker (one case per verb/form)
for c in 'terraform destroy' 'terraform apply -destroy' 'terraform apply -destroy=true' 'terraform state push f' 'kubectl delete pod x' \
  'helm uninstall a' 'az group delete -n x' 'az keyvault secret purge-deleted --name x' 'az vm reimage -g rg -n vm' 'az sql db restore -g rg -n d' \
  'az storage blob delete-batch -s c' 'az rest -m delete --url u' 'aws ec2 terminate-instances --instance-ids i' 'aws s3 sync . s3://b --delete' \
  'az vm start -g rg -n vm; az vm delete -g rg -n vm'; do
  asks_marked yes "$c"
done
for c in 'terraform apply' 'terraform apply -destroy=false' 'docker push img:1' 'az vm deallocate -g rg -n vm' 'az vm disk attach -g rg --vm-name vm -n d' \
  'az backup protection backup-now -g rg -v v -c vm -i vm' 'az vm run-command invoke -g rg -n vm --command-id X' \
  'az rest -m=put --url u' 'az rest -mpost --url u' 'az rest --method "put" --url u'; do
  asks_marked no "$c"
done
guard 'terraform apply; az vm run-command invoke -g rg -n vm --command-id X'
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("runs code on a real machine")' >/dev/null 2>&1
ok_or_fail "command-guard: invoke wording wins over a plain apply in the same line" $?
denies git 'az vm run-command invoke -g rg -n vm --command-id X; git commit -m x'
denies git 'git push; az vm delete -g rg -n vm'
passes 'az vm run-command invoke -g rg -n vm --command-id X' DUTY_ALLOW_APPLY=1
for c in 'az rest --url u' 'az rest -m get --url u' 'az vm run-command list -g rg --vm-name vm' 'az backup job list -g rg -v v' \
  'az vm show -n deallocate -g rg' 'az storage blob list --container-name delete-me' 'terraform plan -destroy'; do
  passes "$c"
done
passes 'tofu apply' DUTY_ALLOW_APPLY=1
passes 'az group delete -n x' DUTY_ALLOW_APPLY=1
passes 'aws s3 rm s3://b/k' DUTY_ALLOW_APPLY=1
passes 'npm publish' DUTY_ALLOW_APPLY=1
# ansible: runs against real hosts and Galaxy publishes ask (delete with the DESTRUCTIVE: marker); syntax checks,
# listings, help and local tools pass
for c in 'ansible-playbook site.yml' 'ansible-playbook -i inv site.yml --check --diff' 'ansible all -m ping' \
  "ansible web -m ansible.builtin.shell -a 'x' -b" 'ansible-navigator run site.yml -m stdout' 'ansible-navigator exec -- ls' \
  'ansible-pull -U url' 'sudo ansible-playbook x.yml' 'ansible-navigator --mode stdout run site.yml' \
  'ansible-navigator --log-file doc run site.yml' 'ansible-navigator exec -- psql -h db' 'ansible-console all' \
  'ansible-runner run . -p site.yml' 'ansible-galaxy collection publish ns-c-1.0.0.tar.gz' 'ansible-galaxy role import user repo' \
  'ansible-runner start . -p site.yml' 'ansible-runner worker --private-data-dir d'; do
  asks_marked no "$c"
done
asks_marked yes 'ansible-galaxy role delete user repo'
for c in 'ansible-playbook --syntax-check site.yml' 'ansible-playbook site.yml --list-tasks' 'ansible all --list-hosts' \
  'ansible --version' 'ansible-playbook -h' 'ansible-lint --fix' 'ansible-doc ansible.builtin.copy' \
  'ansible-galaxy collection install -r requirements.yml' 'ansible-navigator doc ansible.builtin.copy' \
  'ansible-navigator run site.yml --syntax-check' 'ansible-inventory --graph' \
  'ansible-navigator --mode stdout doc ansible.builtin.copy' 'ansible-runner --version'; do
  passes "$c"
done
passes 'ansible-playbook site.yml' DUTY_ALLOW_APPLY=1
asks 'pulumi up' DUTY_ALLOW_GIT_WRITE=1
denies git 'gh pr create --fill'
denies git 'git commit -m x' DUTY_ALLOW_APPLY=1
passes 'git commit -m x' DUTY_ALLOW_GIT_WRITE=1
passes 'git push' DUTY_ALLOW_GIT_WRITE=1
asks 'terraform apply' DUTY_ALLOW_GIT_WRITE=1
passes 'terraform apply' DUTY_ALLOW_APPLY=1
passes 'kubectl delete pod x' DUTY_ALLOW_APPLY=1
denies git 'git commit -m x' DUTY_ALLOW_GIT_WRITE=0
passes 'git commit -m x' COPILOT_CLI=1
out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/x","content":"git commit"}}' | CLAUDE_PLUGIN_ROOT="$ROOT" "$ROOT/hooks/command-guard" 2>&1); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ]; ok_or_fail "command-guard ignores other tools" $?
for bad in 'not json' '{"tool_name":"Bash","tool_input":{"command":7}}' '{"tool_name":"Bash","tool_input":"git push"}' ''; do
  out=$(printf '%s' "$bad" | CLAUDE_PLUGIN_ROOT="$ROOT" "$ROOT/hooks/command-guard" 2>&1); rc=$?
  [ $rc -eq 0 ] && [ -z "$out" ]; ok_or_fail "command-guard stays silent on malformed input: $bad" $?
done
T=$(mktemp -d)
out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push"}}' | PATH="$T" CLAUDE_PLUGIN_ROOT="$ROOT" /bin/bash "$ROOT/hooks/command-guard" 2>&1); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ]; ok_or_fail "command-guard without jq stays silent" $?
rm -rf "$T"
# Claude Code passes hook input on a socket, where opening /dev/stdin fails (ENXIO)
if command -v python3 >/dev/null; then
  out=$(env -u COPILOT_CLI -u DUTY_ALLOW_GIT_WRITE python3 - "$ROOT/hooks/command-guard" <<'PY'
import socket, subprocess, sys
a, b = socket.socketpair()
p = subprocess.Popen([sys.argv[1]], stdin=b, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
b.close()
a.sendall(b'{"tool_name":"Bash","tool_input":{"command":"git push"}}'); a.shutdown(socket.SHUT_WR)
sys.stdout.write(p.communicate()[0].decode())
PY
)
  check "command-guard reads its input from a socket" '.hookSpecificOutput.permissionDecision == "deny"'
else
  echo "skip command-guard socket input (python3 not installed)"
fi
out=$(cat "$ROOT/hooks/hooks.json")
check "hooks.json registers PreToolUse command-guard on Bash" \
  '.hooks.PreToolUse | any(.matcher == "Bash" and (.hooks[0].command | contains("command-guard")))'

out=$(cat "$ROOT/hooks/hooks.json")
check "hooks.json keeps command-guard on PreToolUse Bash when edit-track is added" \
  '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command] | any(contains("command-guard"))'
for ev in PreToolUse PostToolUse PostToolUseFailure; do
  check "hooks.json registers $ev edit-track on Bash" \
    ".hooks.$ev | any(.matcher == \"Bash\" and any(.hooks[]; .type == \"command\" and .command == \"\\\"\${CLAUDE_PLUGIN_ROOT}/hooks/edit-track\\\"\"))"
done

# edit-track: fingerprints the git tree around each Bash call and records the ids of calls that changed it
ETD=$(mktemp -d); ETR=$(mktemp -d); ETN=$(mktemp -d)
git -C "$ETR" init -q
git -C "$ETR" config user.email t@example.com; git -C "$ETR" config user.name t
echo one > "$ETR/a.txt"; echo two > "$ETR/b.txt"; echo three > "$ETR/c.txt"
git -C "$ETR" add . && git -C "$ETR" commit -q -m init
et() { # event, tool_use_id, cwd, env...
  local ev="$1" id="$2" cwd="$3"; shift 3
  out=$(jq -cn --arg e "$ev" --arg i "$id" --arg c "$cwd" \
    '{hook_event_name:$e,session_id:"es1",cwd:$c,tool_name:"Bash",tool_use_id:$i,tool_input:{command:"x"}}' \
    | env -u COPILOT_CLI CLAUDE_PLUGIN_DATA="$ETD" CLAUDE_PLUGIN_ROOT="$ROOT" "$@" "$ROOT/hooks/edit-track" 2>&1); rc=$?
  [ $rc -eq 0 ] && [ -z "$out" ]
}
recorded() { grep -qx "$1" "$ETD/sessions/es1/bash-edits" 2>/dev/null; }
et_case() { # name, expected (yes|no), id, event-after, command run between Pre and Post (in $ETR)
  local name="$1" want="$2" id="$3" post="$4" body="$5" good=0
  et PreToolUse "$id" "$ETR" || good=1
  ( cd "$ETR" && eval "$body" ) >/dev/null 2>&1
  et "$post" "$id" "$ETR" || good=1
  if [ "$want" = yes ]; then recorded "$id" || good=1; else ! recorded "$id" || good=1; fi
  [ -e "$ETD/sessions/es1/pre/$id" ] && good=1
  ok_or_fail "edit-track: $name" $good
}
et_case "sed -i style change of a tracked file is recorded" yes t1 PostToolUse "echo changed >> a.txt"
et_case "no change records nothing (path already in status, unchanged)" no t2 PostToolUse "git status >/dev/null; ls"
et_case "new untracked file is recorded" yes t3 PostToolUse "echo new > new.txt"
et_case "deleted tracked file is recorded" yes t4 PostToolUse "rm b.txt"
et_case "git add alone is not an edit" no t5 PostToolUse "git add a.txt"
et_case "modifying an already-modified file again is recorded" yes t6 PostToolUse "echo more >> a.txt"
et_case "same content, later mtime on an already-modified file is not recorded" no t6b PostToolUse "touch -d '2001-02-03 04:05:06' a.txt"
et_case "reverting a file to HEAD (path leaves status) is recorded" yes t7 PostToolUse "git show HEAD:a.txt > a.txt; git add a.txt"
et_case "PostToolUseFailure records like PostToolUse" yes t8 PostToolUseFailure "echo x >> c.txt; false"
et_case "PostToolUseFailure with no change records nothing" no t9 PostToolUseFailure "false"
et_case "rename is recorded" yes t10 PostToolUse "git mv c.txt d.txt"
et_case "git add of the untracked file alone is not an edit" no t11 PostToolUse "git add new.txt"
# contents, not stat data or status: commits and same-content rewrites are no edits
et_case "git commit of dirty files is not an edit" no t12 PostToolUse "git add -A; git commit -q -m dirty"
et_case "modifying a clean tracked file is recorded" yes t13 PostToolUse "echo clean >> a.txt"
et_case "rewriting a dirty file with identical content (cat x > x) is not recorded" no t14 PostToolUse "cp a.txt a.bak; cat a.bak > a.txt; rm a.bak"
et_case "touching a dirty file is not recorded" no t15 PostToolUse "touch a.txt"
et_case "reverting a dirty file to HEAD content is recorded" yes t16 PostToolUse "git show HEAD:a.txt > a.txt"
et_case "no change on a clean tree records nothing" no t17 PostToolUse "ls"
et_case "a file whose name has spaces is recorded" yes t18 PostToolUse "echo x > 'with space.txt'"
et_case "a file whose name has a newline neither fails nor is recorded as a crash" no t19 PostToolUse "printf x > \"\$(printf 'a\\nb')\"; rm -f a?b"
# Pre records which repo it looked at: Post's own cwd is not consulted
ETB=$(mktemp -d); git -C "$ETB" init -q; echo b > "$ETB/b.txt"
git -C "$ETB" config user.email t@example.com; git -C "$ETB" config user.name t; git -C "$ETB" add . && git -C "$ETB" commit -q -m init
echo dirtyB >> "$ETB/b.txt"
et PreToolUse x1 "$ETR"; et PostToolUse x1 "$ETB"
! recorded x1; ok_or_fail "edit-track: Pre in repo A, Post cwd in dirty repo B, no edits: not recorded" $?
et PreToolUse x2 "$ETR"; echo more >> "$ETR/a.txt"; et PostToolUse x2 "$ETB"
recorded x2; ok_or_fail "edit-track: edit in repo A with Post cwd in repo B is recorded" $?
rm -rf "$ETB"
# a path listed twice in `git status` (staged delete + untracked, rename origin + new file) must not look like an edit
ETR_MAIN=$ETR
ETR=$(mktemp -d); git -C "$ETR" init -q
git -C "$ETR" config user.email t@example.com; git -C "$ETR" config user.name t
echo one > "$ETR/f"; echo two > "$ETR/a"; git -C "$ETR" add . && git -C "$ETR" commit -q -m init
git -C "$ETR" rm -q --cached f
et_case "path twice in status (git rm --cached, file kept): no-op is not recorded" no d1 PostToolUse "true"
et_case "path twice in status (git rm --cached, file kept): change to the file is recorded" yes d2 PostToolUse "echo more >> f"
rm -rf "$ETR"; ETR=$(mktemp -d); git -C "$ETR" init -q
git -C "$ETR" config user.email t@example.com; git -C "$ETR" config user.name t
echo one > "$ETR/f"; echo two > "$ETR/a"; git -C "$ETR" add . && git -C "$ETR" commit -q -m init
git -C "$ETR" mv a b; echo new > "$ETR/a"
et_case "rename origin plus new file at the old name: no-op is not recorded" no d3 PostToolUse "true"
et_case "rename origin plus new file at the old name: change to the new file is recorded" yes d4 PostToolUse "echo more >> a"
rm -rf "$ETR"; ETR=$ETR_MAIN
# stale pre files (no Post ever came, e.g. a denied call) are removed on the next Pre; fresh ones stay
mkdir -p "$ETD/sessions/es1/pre"; touch "$ETD/sessions/es1/pre/fresh"; touch -d '3 days ago' "$ETD/sessions/es1/pre/stale"
et PreToolUse leak1 "$ETR"
[ ! -e "$ETD/sessions/es1/pre/stale" ] && [ -e "$ETD/sessions/es1/pre/fresh" ] && [ -e "$ETD/sessions/es1/pre/leak1" ]
ok_or_fail "edit-track: Pre deletes pre files older than a day, keeps newer ones" $?
rm -f "$ETD/sessions/es1/pre/fresh" "$ETD/sessions/es1/pre/leak1"
et PostToolUse nopre "$ETR"
[ $? -eq 0 ] && ! recorded nopre; ok_or_fail "edit-track: Post without a Pre file records nothing" $?
et PreToolUse "../evil" "$ETR"; et PostToolUse "../evil" "$ETR"
[ ! -e "$ETD/sessions/es1/pre/..evil" ] && [ -z "$(ls "$ETD/sessions/es1/pre" 2>/dev/null)" ]; ok_or_fail "edit-track: tool_use_id sanitized, Pre file removed" $?
# not a git repo, Copilot, malformed input: silent, nothing written
ETD0=$ETD; ETD=$ETN
mkdir -p "$ETN/plain"
et PreToolUse n1 "$ETN/plain"; et PostToolUse n1 "$ETN/plain"
[ $? -eq 0 ] && [ ! -e "$ETN/sessions" ] && [ -z "$(ls -A "$ETN" | grep -v '^plain$')" ]; ok_or_fail "edit-track: non-git cwd writes nothing, silent exit 0" $?
et PreToolUse n2 "$ETR" COPILOT_CLI=1
[ $? -eq 0 ] && [ ! -e "$ETN/sessions" ]; ok_or_fail "edit-track: COPILOT_CLI=1 writes nothing" $?
for bad in 'not json' '' '7' '{}' '{"hook_event_name":"PreToolUse","session_id":"s","cwd":"/nonexistent/x","tool_use_id":"i"}' \
  '{"hook_event_name":"PreToolUse","session_id":"///","cwd":"'"$ETR"'","tool_use_id":"i"}' \
  '{"hook_event_name":"PreToolUse","session_id":"s","cwd":"'"$ETR"'"}' '{"hook_event_name":"PreToolUse","session_id":7,"cwd":"'"$ETR"'","tool_use_id":[]}'; do
  out=$(printf '%s' "$bad" | env -u COPILOT_CLI CLAUDE_PLUGIN_DATA="$ETN" "$ROOT/hooks/edit-track" 2>&1); rc=$?
  [ $rc -eq 0 ] && [ -z "$out" ] && [ ! -e "$ETN/sessions" ]; ok_or_fail "edit-track stays silent and writes nothing on malformed input: $bad" $?
done
ETD=$ETD0
T=$(mktemp -d)
out=$(printf '%s' '{"hook_event_name":"PreToolUse","session_id":"s","cwd":"'"$ETR"'","tool_use_id":"i"}' | PATH="$T" CLAUDE_PLUGIN_DATA="$ETN" /bin/bash "$ROOT/hooks/edit-track" 2>&1); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && [ ! -e "$ETN/sessions" ]; ok_or_fail "edit-track without jq stays silent" $?
rm -rf "$T" "$ETD" "$ETR" "$ETN"
# end to end: edit-track Pre/Post, then stop-gate reads what it recorded
EE=$(mktemp -d); EED=$(mktemp -d); EER="$EE/repo"; mkdir "$EER"
git -C "$EER" init -q; git -C "$EER" config user.email t@example.com; git -C "$EER" config user.name t
echo one > "$EER/f.txt"; git -C "$EER" add . && git -C "$EER" commit -q -m init
eehook() { # event
  jq -cn --arg e "$1" --arg c "$EER" '{hook_event_name:$e,session_id:"S",cwd:$c,tool_name:"Bash",tool_use_id:"X",tool_input:{command:"sed -i s/one/two/ f.txt"}}' \
    | env -u COPILOT_CLI CLAUDE_PLUGIN_DATA="$EED" "$ROOT/hooks/edit-track" >/dev/null 2>&1
}
eehook PreToolUse; sed -i.bak 's/one/two/' "$EER/f.txt" && rm -f "$EER/f.txt.bak"; eehook PostToolUse
eetx() { jq -cn --arg id X '{type:"assistant",message:{content:[{type:"tool_use",id:$id,name:"Bash",input:{command:"sed -i s/one/two/ f.txt"}}]}}'; }
{ txt 'Size: medium'; eetx; } > "$EE/t.jsonl"
eestop() { jq -cn --arg p "$EE/t.jsonl" '{transcript_path:$p,session_id:"S"}' | env CLAUDE_PLUGIN_DATA="$EED" "$ROOT/hooks/stop-gate" 2>&1; }
out=$(eestop)
check "end to end: Bash edit seen by edit-track blocks the stop gate" '.decision == "block" and (.reason | contains("refuter"))'
AG duty-framework:refuter >> "$EE/t.jsonl"
out=$(eestop)
[ -z "$out" ]; ok_or_fail "end to end: a refuter call after the Bash edit lets the stop gate allow" $?
rm -rf "$EE" "$EED"

# state dir defaults to ${TMPDIR:-/tmp}/duty-framework without CLAUDE_PLUGIN_DATA
ETT=$(mktemp -d); ETR2=$(mktemp -d); git -C "$ETR2" init -q; echo a > "$ETR2/f"
for ev in PreToolUse PostToolUse; do
  [ $ev = PostToolUse ] && echo b >> "$ETR2/f"
  printf '{"hook_event_name":"%s","session_id":"d1","cwd":"%s","tool_use_id":"k1"}' "$ev" "$ETR2" \
    | env -u COPILOT_CLI -u CLAUDE_PLUGIN_DATA TMPDIR="$ETT" "$ROOT/hooks/edit-track" >/dev/null 2>&1
done
grep -qx k1 "$ETT/duty-framework/sessions/d1/bash-edits" 2>/dev/null; ok_or_fail "edit-track default state dir is \$TMPDIR/duty-framework/sessions/<id>" $?
rm -rf "$ETT" "$ETR2"

# newer `claude plugin validate` appends an advisory plugin-directory section whose warnings
# (e.g. a missing icon) don't affect the result; drop it before looking for warnings
strip_advisory() { sed -e '/^Plugin directory checks/,/^These plugin directory checks do not change the result below\.$/d' -e '/^The directory also runs a safety scan/d'; }
ADV='Plugin directory checks for /x. The plugin directory is the catalog that plugins are submitted to.

â  Found 1 plugin directory warning:

  â¯ .claude-plugin/plugin.json icon: No icon (ICON_MISSING).

These plugin directory checks do not change the result below.

The directory also runs a safety scan and a policy review that this command does not.
'
okout=$(printf 'Validating marketplace manifest: /x/m.json\n\n%b\n\xe2\x9c\x94 Validation passed\n' "$ADV")
badout=$(printf 'Validating plugin manifest: /x/p.json\n\n\xe2\x9a\xa0 Found 1 warning:\n\n  \xe2\x9d\xaf name: odd\n\n%b\n\xe2\x9c\x94 Validation passed with warnings\n' "$ADV")
badafter=$(printf '%b\n\xe2\x9a\xa0 Found 1 warning:\n  x\n' "$ADV")
! printf '%s\n' "$okout" | strip_advisory | grep -qi warning
ok_or_fail "validate filter: only the advisory warning passes" $?
printf '%s\n' "$badout" | strip_advisory | grep -qi warning
ok_or_fail "validate filter: a manifest warning before the advisory still fails" $?
printf '%s\n' "$badafter" | strip_advisory | grep -qi warning
ok_or_fail "validate filter: a warning after the advisory still fails" $?
printf '%s\n' "$okout" | grep -qi warning
ok_or_fail "validate filter: sample really contains the advisory warning unfiltered" $?
if command -v claude >/dev/null; then
  out=$(claude plugin validate "$ROOT" 2>&1)
  if [ $? -eq 0 ] && ! printf '%s' "$out" | strip_advisory | grep -qi 'warning'; then
    echo "ok   claude plugin validate"
  else
    echo "FAIL claude plugin validate"; printf '%s\n' "$out"; fails=$((fails + 1))
  fi
fi

if command -v agy >/dev/null; then
  out=$(agy plugin validate "$ROOT" 2>&1)
  if [ $? -eq 0 ] && printf '%s' "$out" | grep -q 'skills 9' && printf '%s' "$out" | grep -q 'agents 5'; then
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

# duty-terraform add-on has its own tests
if out=$("$ROOT/plugins/duty-terraform/tests/test-terraform.sh" 2>&1); then
  echo "ok   duty-terraform tests"
else
  echo "FAIL duty-terraform tests"; printf '%s\n' "$out" | grep -v '^ok'; fails=$((fails + 1))
fi
if out=$("$ROOT/plugins/duty-ansible/tests/test-ansible.sh" 2>&1); then
  echo "ok   duty-ansible tests"
else
  echo "FAIL duty-ansible tests"; printf '%s\n' "$out" | grep -v '^ok'; fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
