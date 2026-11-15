#!/usr/bin/env bash
# Checks the duty-ansible add-on: MCP launcher, hooks, manifests, skill/agent text, generated agents, validators.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fails=0

ok_or_fail() { # name, condition exit status
  if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}

check() { # name, jq expression that must be true for $out
  if [ -n "$out" ] && printf '%s' "$out" | jq -e "$2" >/dev/null 2>&1; then
    echo "ok   $1"
  else
    echo "FAIL $1"; fails=$((fails + 1))
  fi
}

fm()    { sed -n '2,/^---$/p' "$1" 2>/dev/null | sed '$d'; }  # frontmatter of a file
body()  { awk 'n >= 2; /^---$/ { n++ }' "$1" 2>/dev/null; }  # text after frontmatter
field() { fm "$1" | sed -n "s/^$2: *//p"; }
flat()  { tr '\n' ' ' < "$1" 2>/dev/null | sed 's/  */ /g'; }  # file on one line, to match across wrapped lines

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# 26.6.0, not newer: from 26.8.0 the bundled dist/ can't find agents.md, so
# ansible_content_best_practices fails ("Could not resolve resource path").
IMAGE='ghcr.io/ansible/devtools-mcp-server:26.6.0'

# --- MCP launcher: identical bash -c string in the three configs
LAUNCH_CLAUDE=$(jq -r '.mcpServers.ansible | select(.command == "bash" and .args[0] == "-c") | .args[1]' "$ROOT/.mcp.json" 2>/dev/null)
LAUNCH_COPILOT=$(jq -r '.mcpServers.ansible | select(.command == "bash" and .args[0] == "-c") | .args[1]' "$ROOT/.plugin/plugin.json" 2>/dev/null)
LAUNCH_AGY=$(jq -r '.mcpServers.ansible | select(.command == "bash" and .args[0] == "-c") | .args[1]' "$ROOT/mcp_config.json" 2>/dev/null)
L="$LAUNCH_CLAUDE"
[ -n "$L" ] && [ "$L" = "$LAUNCH_COPILOT" ] && [ "$L" = "$LAUNCH_AGY" ]
ok_or_fail "MCP launcher is the same bash -c string in .mcp.json, .plugin/plugin.json, mcp_config.json" $?

mkdir -p "$T/bin" "$T/ws"
cat > "$T/bin/docker" <<'STUB'
#!/bin/sh
# Stub docker: 'info' fails when STUB_INFO_FAIL=1; every call's args are recorded.
echo "$*" >> "$STUB_LOG"
[ "$1" = info ] && [ "${STUB_INFO_FAIL:-}" = 1 ] && exit 1
exit 0
STUB
chmod +x "$T/bin/docker"
if [ -n "$L" ]; then
  : > "$T/log"
  err=$(cd "$T/ws" && STUB_LOG="$T/log" STUB_INFO_FAIL=1 PATH="$T/bin:$PATH" bash -c "$L" 2>&1 >/dev/null); rc=$?
  [ $rc -ne 0 ] && [[ "$err" == *'needs Docker'* ]] && ! grep -q '^run' "$T/log"
  ok_or_fail "launcher without Docker: non-zero exit, 'needs Docker' on stderr, no docker run" $?
  : > "$T/log"
  (cd "$T/ws" && STUB_LOG="$T/log" PATH="$T/bin:$PATH" bash -c "$L" >/dev/null 2>&1); rc=$?
  [ $rc -eq 0 ] && grep -qxF "run -i --rm -v $T/ws:/workspace:ro -e WORKSPACE_ROOT=/workspace $IMAGE --stdio" "$T/log"
  ok_or_fail "launcher with Docker: execs docker run of the pinned image, cwd mounted read-only (:ro), WORKSPACE_ROOT, --stdio" $?
else
  ok_or_fail "launcher without Docker: non-zero exit, 'needs Docker' on stderr, no docker run" 1
  ok_or_fail "launcher with Docker: execs docker run of the pinned image, cwd mounted read-only (:ro), WORKSPACE_ROOT, --stdio" 1
fi

# --- hooks
runin() { # dir, stdin, hook, env... ; sets $out
  local dir="$1" in="$2" hook="$3"; shift 3
  out=$(cd "$dir" && printf '%s' "$in" | env -u CLAUDE_PLUGIN_ROOT -u COPILOT_CLI "$@" "$ROOT/hooks/$hook" 2>&1)
}
nothing() { # name
  [ -z "$out" ]; ok_or_fail "$1" $?
}

mkdir -p "$T/cfg" "$T/role/roles/web/tasks" "$T/galaxy" "$T/pb/playbooks" "$T/nested/infra/ansible/roles/web/tasks" \
  "$T/gvars/group_vars" "$T/onerole/tasks" "$T/onerole/meta" "$T/coll/ansible_collections/ns/c"
touch "$T/cfg/ansible.cfg" "$T/role/roles/web/tasks/main.yml" "$T/galaxy/galaxy.yml" "$T/pb/playbooks/site.yml" \
  "$T/nested/infra/ansible/roles/web/tasks/main.yml" "$T/gvars/site.yml" "$T/gvars/group_vars/all.yml" \
  "$T/onerole/tasks/main.yml" "$T/onerole/meta/main.yaml" "$T/coll/ansible_collections/ns/c/galaxy.yml"
# cfg, roles/ at the top and nested, galaxy.yml at the top and in a collection tree, playbooks/, group_vars/, a standalone role repo
for d in cfg role nested galaxy coll pb gvars onerole; do
  runin "$T/$d" '' session-start CLAUDE_PLUGIN_ROOT="$ROOT"
  check "session-start claude ($d): nested context names the ansible skill" \
    '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | contains("`ansible` skill") and contains("ansible agent")) and (has("additionalContext") | not)'
  runin "$T/$d" '' session-start CLAUDE_PLUGIN_ROOT="$ROOT" COPILOT_CLI=1
  check "session-start copilot ($d): top-level context names the ansible skill" \
    '(.additionalContext | contains("`ansible` skill")) and (has("hookSpecificOutput") | not)'
done
mkdir -p "$T/other/.github/workflows"
touch "$T/other/docker-compose.yml" "$T/other/.github/workflows/ci.yml"
runin "$T/other" '' session-start CLAUDE_PLUGIN_ROOT="$ROOT"
nothing "session-start: no output in a repo with only docker-compose.yml and .github/workflows/ci.yml"
mkdir -p "$T/k8s/charts/app/templates" "$T/k8s/rbac/roles" "$T/k8s/vars"
touch "$T/k8s/charts/app/values.yaml" "$T/k8s/charts/app/templates/deployment.yaml" "$T/k8s/rbac/roles/reader.yaml" "$T/k8s/vars/prod.yml"
runin "$T/k8s" '' session-start CLAUDE_PLUGIN_ROOT="$ROOT"
nothing "session-start: no output in a k8s/helm repo with rbac roles/ and vars/ YAML"
mkdir -p "$T/pruned/node_modules/x" "$T/pruned/.venv/lib" "$T/pruned/collections/ansible_collections/ns/coll"
touch "$T/pruned/node_modules/x/ansible.cfg" "$T/pruned/.venv/lib/ansible.cfg" "$T/pruned/collections/ansible_collections/ns/coll/galaxy.yml"
runin "$T/pruned" '' session-start CLAUDE_PLUGIN_ROOT="$ROOT"
nothing "session-start: no output when Ansible files sit only in node_modules, .venv or installed collections"
mkdir -p "$T/empty"
runin "$T/empty" '' session-start CLAUDE_PLUGIN_ROOT="$ROOT"
nothing "session-start: no output in an empty dir"

view() { # json
  runin "$T/empty" "$1" post-view CLAUDE_PLUGIN_ROOT="$ROOT" COPILOT_CLI=1
}
for p in /w/roles/web/tasks/main.yml /w/inventory/group_vars/all.yml /w/playbooks/site.yml; do
  view "{\"tool_name\":\"Read\",\"tool_input\":{\"path\":\"$p\"}}"
  check "post-view: $p gives context" '(.additionalContext | contains("`ansible` skill"))'
done
view '{"tool_name":"Read","tool_input":{"file_path":"/w/roles/web/handlers/main.yml"}}'
check "post-view: .tool_input.file_path role handler gives context" '(.additionalContext | contains("`ansible` skill"))'
for p in /w/.github/workflows/ci.yml /w/docker-compose.yml; do
  view "{\"tool_name\":\"Read\",\"tool_input\":{\"path\":\"$p\"}}"
  nothing "post-view: $p gives no output"
done
runin "$T/empty" '{"tool_name":"Read","tool_input":{"file_path":"/w/roles/web/tasks/main.yml"}}' post-view CLAUDE_PLUGIN_ROOT="$ROOT"
nothing "post-view claude env (COPILOT_CLI unset): role task file gives no output, the skill loads via paths"
view ''
nothing "post-view: empty stdin gives no output"

out=$(cat "$ROOT/hooks/hooks.json" 2>/dev/null)
check "hooks.json: SessionStart startup|clear|compact runs session-start" \
  '.hooks.SessionStart[0].matcher == "startup|clear|compact" and (.hooks.SessionStart[0].hooks[0].command | contains("${CLAUDE_PLUGIN_ROOT}/hooks/session-start"))'
check "hooks.json: exactly one PostToolUse entry, matcher Read, runs post-view (a second matcher double-nudges on Copilot)" \
  '(.hooks.PostToolUse | length == 1) and .hooks.PostToolUse[0].matcher == "Read" and (.hooks.PostToolUse[0].hooks | length == 1) and (.hooks.PostToolUse[0].hooks[0].command | contains("${CLAUDE_PLUGIN_ROOT}/hooks/post-view"))'
[ -f "$ROOT/hooks/emit.sh" ]
ok_or_fail "hooks/emit.sh exists (sourced, so not executable)" $?
for h in session-start post-view; do
  [ -f "$ROOT/hooks/$h" ] && [ -x "$ROOT/hooks/$h" ]
  ok_or_fail "hooks/$h exists and is executable" $?
done

# --- manifests
for m in .claude-plugin/plugin.json .plugin/plugin.json plugin.json; do
  out=$(cat "$ROOT/$m" 2>/dev/null)
  check "$m: name duty-ansible and description" '.name == "duty-ansible" and (.description | length > 0)'
  case $m in
    plugin.json) check "$m: agy schema" '."$schema" == "https://antigravity.google/schemas/v1/plugin.json"' ;;
    *) check "$m: version 0.1.1, author, MIT" '.version == "0.1.1" and .author.name == "Louka Vanhoucke" and .license == "MIT"' ;;
  esac
done
out=$(cat "$ROOT/.claude-plugin/plugin.json" 2>/dev/null)
check "claude manifest lists claude-agents/ansible.md" '.agents == ["./claude-agents/ansible.md"]'
out=$(cat "$ROOT/.plugin/plugin.json" 2>/dev/null)
check "copilot manifest points at copilot-agents and has mcpServers.ansible" '.agents == "./copilot-agents" and (.mcpServers.ansible.command == "bash")'

# --- skill and agent text
S="$ROOT/skills/ansible/SKILL.md" A="$ROOT/roles/ansible.md" R="$ROOT/rules/ansible.md"
[ "$(field "$S" name)" = ansible ] && field "$S" description | grep -q '^Use when working with Ansible' \
  && fm "$S" | grep -E '^paths:' | grep -qF '**/roles/**/*.yml' && fm "$S" | grep -E '^paths:' | grep -qF '**/playbooks/**/*.yml' \
  && fm "$S" | grep -E '^paths:' | grep -qF '**/group_vars/**' && fm "$S" | grep -E '^paths:' | grep -qF '**/ansible.cfg'
ok_or_fail "skill frontmatter: name ansible, description, paths for roles, playbooks, group_vars, ansible.cfg" $?
for f in "$S" "$A" "$R"; do
  n=${f#"$ROOT"/}
  nv=$(flat "$f" | sed -n 's/.*[Nn]ever run[: ]*\(.\{0,400\}\).*/\1/p')
  bad=0; [ -n "$nv" ] || bad=1
  for w in 'ansible-playbook' '--check' 'ad-hoc' 'ansible-navigator' 'ansible-pull' 'ansible-console' 'ansible-runner' 'publish' 'decrypt'; do grep -qiF -- "$w" <<<"$nv" || bad=1; done
  ok_or_fail "$n: the never-run wording forbids ansible-playbook (incl. --check), ad-hoc, navigator, pull, console, runner, galaxy publish, vault decrypt" $bad
done
for f in "$S" "$A"; do
  n=${f#"$ROOT"/}
  t=$(flat "$f")
  bad=0
  for w in ansible_navigator ade_setup_environment adt_check_env define_and_build_execution_env create_ansible_projects; do grep -qF "$w" <<<"$t" || bad=1; done
  grep -qiE 'never (call|use)' <<<"$t" || bad=1
  ok_or_fail "$n: names the MCP execution tools it must never call" $bad
  grep -qF 'start Docker' <<<"$t" && grep -qiE 'no (web|memory)|not.*(web|memory)|never.*(web|memory)' <<<"$t"
  ok_or_fail "$n: MCP unavailable means stop and say start Docker, no web/memory fallback" $?
  grep -qF 'FQCN' <<<"$t" && grep -qE 'ansible-lint[^.]{0,40}production|production[^.]{0,40}ansible-lint' <<<"$t"
  ok_or_fail "$n: requires FQCN and ansible-lint production profile" $?
done

readme="$ROOT/../../README.md"
nv=$(sed -n '/^## Optional: Ansible add-on/,/^## Develop/p' "$readme" | grep -i 'never runs' | head -1)
bad=0; [ -n "$nv" ] || bad=1
for w in 'ansible-playbook' '--check' 'ad-hoc' 'ansible-navigator' 'ansible-pull' 'ansible-console' 'ansible-runner' 'publish' 'decrypt'; do grep -qiF -- "$w" <<<"$nv" || bad=1; done
ok_or_fail "README add-on: never-runs list matches the skill (playbook incl. --check, ad-hoc, navigator, pull, console, runner, galaxy publish, vault decrypt)" $bad

# --- generated agents
for dir in claude-agents agents copilot-agents; do
  f="$ROOT/$dir/ansible.md"
  [ "$(field "$f" name)" = ansible ] && [ -n "$(field "$f" description)" ] && [ -n "$(body "$f")" ] && [ "$(body "$f")" = "$(body "$A")" ]
  ok_or_fail "$dir/ansible has name, description, body of roles/ansible.md" $?
done
fm "$ROOT/claude-agents/ansible.md" | grep -qx 'disallowedTools: Agent' && [ "$(field "$ROOT/claude-agents/ansible.md" model)" = inherit ] && [ -z "$(field "$ROOT/claude-agents/ansible.md" tools)" ]
ok_or_fail "claude agent: disallowedTools Agent, model inherit, no tools list (keeps MCP)" $?
[ -f "$ROOT/copilot-agents/ansible.md" ] && [ -z "$(field "$ROOT/copilot-agents/ansible.md" tools)" ] && [ -z "$(field "$ROOT/copilot-agents/ansible.md" model)" ]
ok_or_fail "copilot agent: no tools list (all tools incl. MCP), no model" $?
AGY_TOOLS='view_file list_dir find_by_name grep_search replace_file_content multi_replace_file_content write_to_file run_command command_status'
tools=$(field "$ROOT/agents/ansible.md" tools | tr -d '[],'); bad=0; [ -n "$tools" ] || bad=1
for t in $tools; do printf ' %s ' "$AGY_TOOLS" | grep -q " $t " || bad=1; done
ok_or_fail "agy agent lists only known agy tools" $bad
fm "$ROOT/agents/ansible.md" | grep -qx 'inheritMcp: true'
ok_or_fail "agy agent: inheritMcp true (reaches the MCP tools)" $?

mkdir -p "$T/gen"
"$ROOT/scripts/build-agents" "$T/gen" >/dev/null 2>&1 \
  && diff -r "$T/gen/agents" "$ROOT/agents" >/dev/null \
  && diff -r "$T/gen/claude-agents" "$ROOT/claude-agents" >/dev/null \
  && diff -r "$T/gen/copilot-agents" "$ROOT/copilot-agents" >/dev/null
ok_or_fail "generated agents are up to date (scripts/build-agents)" $?

# --- agy rule
[ "$(field "$R" trigger)" = glob ] && field "$R" globs | grep -qF 'roles/' && field "$R" globs | grep -qF 'playbooks/' && field "$R" globs | grep -qF 'ansible.cfg'
ok_or_fail "agy rule: trigger glob, globs for roles, playbooks, ansible.cfg" $?

# --- validators
if command -v claude >/dev/null; then
  out=$(claude plugin validate "$ROOT" 2>&1)
  # newer validate appends an advisory plugin-directory section whose warnings don't affect the result
  if [ $? -eq 0 ] && ! printf '%s\n' "$out" | sed -e '/^Plugin directory checks/,/^These plugin directory checks do not change the result below\.$/d' -e '/^The directory also runs a safety scan/d' | grep -qi 'warning'; then
    echo "ok   claude plugin validate"
  else
    echo "FAIL claude plugin validate"; printf '%s\n' "$out"; fails=$((fails + 1))
  fi
else
  echo "skip claude plugin validate (claude not installed)"
fi
if command -v agy >/dev/null; then
  out=$(agy plugin validate "$ROOT" 2>&1)
  if [ $? -eq 0 ] && printf '%s' "$out" | grep -q 'skills 1' && printf '%s' "$out" | grep -q 'agents 1' && printf '%s' "$out" | grep -q 'mcpServers 1'; then
    echo "ok   agy plugin validate"
  else
    echo "FAIL agy plugin validate"; printf '%s\n' "$out"; fails=$((fails + 1))
  fi
else
  echo "skip agy plugin validate (agy not installed)"
fi

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
