#!/usr/bin/env bash
# Checks the duty-terraform add-on: MCP launcher, hooks, manifests, skill/agent text, generated agents, validators.
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

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# --- MCP launcher: identical bash -c string in the three configs
LAUNCH_CLAUDE=$(jq -r '.mcpServers.terraform | select(.command == "bash" and .args[0] == "-c") | .args[1]' "$ROOT/.mcp.json" 2>/dev/null)
LAUNCH_COPILOT=$(jq -r '.mcpServers.terraform | select(.command == "bash" and .args[0] == "-c") | .args[1]' "$ROOT/.plugin/plugin.json" 2>/dev/null)
LAUNCH_AGY=$(jq -r '.mcpServers.terraform | select(.command == "bash" and .args[0] == "-c") | .args[1]' "$ROOT/mcp_config.json" 2>/dev/null)
L="$LAUNCH_CLAUDE"
[ -n "$L" ] && [ "$L" = "$LAUNCH_COPILOT" ] && [ "$L" = "$LAUNCH_AGY" ]
ok_or_fail "MCP launcher is the same bash -c string in .mcp.json, .plugin/plugin.json, mcp_config.json" $?
[[ "$L" == *'hashicorp/terraform-mcp-server:1.3.0'* ]] && [[ "$L" == *'--toolsets=registry'* ]]
ok_or_fail "MCP launcher pins the image and uses --toolsets=registry" $?
[ -n "$L" ] && [[ "$L" != *'terraform,'* ]] && [[ "$L" != *'registry-private'* ]] && ! grep -qE 'toolsets=([a-z-]+,)*all' <<<"$L"
ok_or_fail "MCP launcher enables no terraform, registry-private or all toolset" $?

mkdir -p "$T/bin"
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
  err=$(STUB_LOG="$T/log" STUB_INFO_FAIL=1 PATH="$T/bin:$PATH" bash -c "$L" 2>&1 >/dev/null); rc=$?
  [ $rc -ne 0 ] && [[ "$err" == *'needs Docker'* ]] && ! grep -q '^run' "$T/log"
  ok_or_fail "launcher without Docker: non-zero exit, 'needs Docker' on stderr, no docker run" $?
  : > "$T/log"
  STUB_LOG="$T/log" PATH="$T/bin:$PATH" bash -c "$L" >/dev/null 2>&1; rc=$?
  [ $rc -eq 0 ] && grep -qxF 'run -i --rm hashicorp/terraform-mcp-server:1.3.0 stdio --toolsets=registry' "$T/log"
  ok_or_fail "launcher with Docker: execs docker run of the pinned image, registry toolset" $?
else
  ok_or_fail "launcher without Docker: non-zero exit, 'needs Docker' on stderr, no docker run" 1
  ok_or_fail "launcher with Docker: execs docker run of the pinned image, registry toolset" 1
fi

# --- hooks
runin() { # dir, stdin, hook, env... ; sets $out
  local dir="$1" in="$2" hook="$3"; shift 3
  out=$(cd "$dir" && printf '%s' "$in" | env -u CLAUDE_PLUGIN_ROOT -u COPILOT_CLI "$@" "$ROOT/hooks/$hook" 2>&1)
}
nothing() { # name
  [ -z "$out" ]; ok_or_fail "$1" $?
}

mkdir -p "$T/tf" "$T/none/.terraform/modules/x" "$T/none/a/b/c/d" "$T/shallow/a/b"
touch "$T/tf/main.tf" "$T/none/.terraform/modules/x/main.tf" "$T/none/a/b/c/x.tf" "$T/none/a/b/c/d/y.tf" "$T/shallow/a/b/z.tf"
for d in tf shallow; do
  runin "$T/$d" '' session-start CLAUDE_PLUGIN_ROOT="$ROOT"
  check "session-start claude ($d): nested context names the terraform skill" \
    '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | contains("`terraform` skill") and contains("terraform agent")) and (has("additionalContext") | not)'
  runin "$T/$d" '' session-start CLAUDE_PLUGIN_ROOT="$ROOT" COPILOT_CLI=1
  check "session-start copilot ($d): top-level context names the terraform skill" \
    '(.additionalContext | contains("`terraform` skill")) and (has("hookSpecificOutput") | not)'
done
runin "$T/none" '' session-start CLAUDE_PLUGIN_ROOT="$ROOT"
nothing "session-start: no output without .tf (only in .terraform/ or deeper than depth 3)"
mkdir -p "$T/empty"
runin "$T/empty" '' session-start CLAUDE_PLUGIN_ROOT="$ROOT"
nothing "session-start: no output in an empty dir"

view() { # json
  runin "$T/empty" "$1" post-view CLAUDE_PLUGIN_ROOT="$ROOT" COPILOT_CLI=1
}
view '{"tool_name":"Read","tool_input":{"path":"/w/infra/main.tf"}}'
check "post-view: .tool_input.path .tf gives context" '(.additionalContext | contains("`terraform` skill"))'
view '{"tool_name":"Read","tool_input":{"path":"/w/infra/prod.tfvars"}}'
check "post-view: .tool_input.path .tfvars gives context" '(.additionalContext | contains("`terraform` skill"))'
view '{"tool_name":"Read","tool_input":{"file_path":"/w/infra/main.tf"}}'
check "post-view: .tool_input.file_path .tf gives context" '(.additionalContext | contains("`terraform` skill"))'
runin "$T/empty" '{"tool_name":"Read","tool_input":{"file_path":"/w/infra/main.tf"}}' post-view CLAUDE_PLUGIN_ROOT="$ROOT"
nothing "post-view claude env (COPILOT_CLI unset): .tf gives no output, the skill loads via paths"
runin "$T/empty" '{"tool_name":"view","tool_input":{"path":"/w/infra/main.tf"}}' post-view CLAUDE_PLUGIN_ROOT="$ROOT"
nothing "post-view claude env (COPILOT_CLI unset): view tool .tf gives no output"
view '{"tool_name":"Read","tool_input":{"path":"/w/app/main.py"}}'
nothing "post-view: .py gives no output"
view '{"tool_name":"Read","tool_input":{"path":"/w/infra/notes.tf.md"}}'
nothing "post-view: .tf.md gives no output"
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
  check "$m: name duty-terraform and description" '.name == "duty-terraform" and (.description | length > 0)' 
  case $m in
    plugin.json) check "$m: agy schema" '."$schema" == "https://antigravity.google/schemas/v1/plugin.json"' ;;
    *) check "$m: version 0.1.0, author, MIT" '.version == "0.1.0" and .author.name == "Louka Vanhoucke" and .license == "MIT"' ;;
  esac
done
out=$(cat "$ROOT/.claude-plugin/plugin.json" 2>/dev/null)
check "claude manifest lists claude-agents/terraform.md" '.agents == ["./claude-agents/terraform.md"]'
out=$(cat "$ROOT/.plugin/plugin.json" 2>/dev/null)
check "copilot manifest points at copilot-agents and has mcpServers.terraform" '.agents == "./copilot-agents" and (.mcpServers.terraform.command == "bash")'

# --- skill and agent text
S="$ROOT/skills/terraform/SKILL.md" A="$ROOT/roles/terraform.md"
[ "$(field "$S" name)" = terraform ] && [ -n "$(field "$S" description)" ] \
  && field "$S" description | grep -q '^Use when working with Terraform' \
  && fm "$S" | grep -E '^paths:' | grep -qF '**/*.tf' && fm "$S" | grep -E '^paths:' | grep -qF '**/*.tfvars'
ok_or_fail "skill frontmatter: name terraform, description, paths for *.tf and *.tfvars" $?
for f in "$S" "$A"; do
  n=${f#"$ROOT"/}
  line=$(grep -i -A2 'never run:' "$f" | head -3)
  bad=0
  for w in 'terraform plan' 'init' 'apply' 'destroy' 'import' 'state'; do grep -qiF -- "$w" <<<"$line" || bad=1; done
  ok_or_fail "$n: a 'Never run:' line forbids plan, init, apply, destroy, import, state" $bad
  grep -qF 'init -backend=false' "$f"
  ok_or_fail "$n: only init -backend=false is allowed" $?
  grep -qi 'plan command' "$f" && grep -qi 'wait' "$f"
  ok_or_fail "$n: hands the user the plan command and waits" $?
  grep -qF 'start Docker' "$f" && grep -qiE 'no (web|memory)|not.*(web|memory)|never.*(web|memory)' "$f"
  ok_or_fail "$n: MCP unavailable means stop and say start Docker, no web/memory fallback" $?
  grep -qi 'user re-run' "$f" || grep -qiE 'tell the user to re-run' "$f"
  ok_or_fail "$n: init flake means the user re-runs their init" $?
  grep -qF 'CHANGELOG.md' "$f" && grep -qF 'ls-remote --tags' "$f"
  ok_or_fail "$n: upgrades read the module CHANGELOG.md, tags via git ls-remote --tags" $?
  if [ "$f" = "$S" ]; then up=$(sed -n '/^## Upgrade providers or modules/,/^## Delegation/p' "$f"); else up=$(sed -n '/^- Upgrades:/,/^- Leave/p' "$f"); fi
  grep -qE 'provider_document_type[^.]*guides|type `guides`' <<<"$up"
  ok_or_fail "$n: upgrade section names search_providers provider_document_type guides (not just any 'guides')" $?
  pin=$(grep -ob -m1 -F 'version pin' <<<"$up" | head -1 | cut -d: -f1)
  ini=$(grep -ob -m1 -F 'init -backend=false' <<<"$up" | head -1 | cut -d: -f1)
  [ -n "$pin" ] && [ -n "$ini" ] && [ "$pin" -lt "$ini" ]
  ok_or_fail "$n: upgrade changes the version pin before init -backend=false" $?
  grep -qiE 'target.{0,60}CHANGELOG|CHANGELOG.{0,60}target' <<<"$up"
  ok_or_fail "$n: upgrade reads the target module's CHANGELOG.md" $?
done
for f in "$S" "$A" "$ROOT/rules/terraform.md"; do
  n=${f#"$ROOT"/}
  ! grep -qiE 'explicit OK|state` write|state writes' "$f" && grep -qF 'state` command' "$f" && grep -qF 'taint' "$f" && grep -qF 'workspace' "$f"
  ok_or_fail "$n: absolute safety rule (no 'explicit OK' or 'state writes' loophole, any 'terraform state' command, taint, workspace)" $?
done
# --- lock-file conflicts, -upgrade, half-finished upgrades
flat() { tr '\n' ' ' < "$1" | sed 's/  */ /g'; }  # file on one line, to match across wrapped lines
for f in "$S" "$A" "$ROOT/rules/terraform.md"; do
  n=${f#"$ROOT"/}
  flat "$f" | sed -n 's/.*[Nn]ever run[: ]*\(.\{0,260\}\).*/\1/p' | grep -qF -- '-upgrade'
  ok_or_fail "$n: the never-run wording forbids init -upgrade" $?
done
for f in "$S" "$A"; do
  n=${f#"$ROOT"/}
  t=$(flat "$f")
  grep -qF '.terraform.lock.hcl' <<<"$t" && grep -qF '.terraform/' <<<"$t" \
    && grep -qiE '(lock ?file|\.terraform\.lock\.hcl).{0,120}(stop|hand)|(stop|hand).{0,120}(lock ?file|\.terraform\.lock\.hcl)' <<<"$t" \
    && grep -qiE '(until|wait).{0,80}(user|they).{0,60}(continue|say)' <<<"$t"
  ok_or_fail "$n: lock-file conflict on init -backend=false stops, hands back to the user (.terraform/, .terraform.lock.hcl), waits for continue" $?
  ! grep -qE 'rm +(-[a-z]+ +)*[^ ]*\.terraform' "$f" && grep -qiE 'never delete (them|`?\.terraform)' <<<"$t"
  ok_or_fail "$n: never deletes .terraform/ or .terraform.lock.hcl itself (no rm command)" $?
  grep -qiE 'record.{0,80}(pin|\?ref=).{0,120}(lock ?file|\.terraform\.lock\.hcl)' <<<"$t" \
    && grep -qiE '(put|set).{0,40}(pin|\?ref=).{0,60}back' <<<"$t" \
    && grep -qiE "(don.t|not) use git|no git|without git" <<<"$t"
  ok_or_fail "$n: upgrade records the current pin and lock file state first, tells the user how to revert (pin put back, no git)" $?
done
readme="$ROOT/../../README.md"
nv=$(sed -n '/^## Optional: Terraform add-on/,/^## Develop/p' "$readme" | grep -i 'never runs' | head -1)
bad=0
for w in 'plan' 'init' '-upgrade' 'apply' 'destroy' 'import' 'state' 'taint' 'workspace'; do grep -qiF -- "$w" <<<"$nv" || bad=1; done
ok_or_fail "README add-on: never-runs list has plan, init, -upgrade, apply, destroy, import, state, taint, workspace" $bad
sed -n '/^## Optional: Terraform add-on/,/^## Develop/p' "$readme" | grep -qi 'lock' \
  && sed -n '/^## Optional: Terraform add-on/,/^## Develop/p' "$readme" | grep -qF '.terraform.lock.hcl'
ok_or_fail "README add-on: lock-file conflicts are handed back to the user" $?
! grep -iE 'changelog' "$S" | grep -qF 'get_module_details' && ! grep -iE 'changelog' "$A" | grep -qF 'get_module_details'
ok_or_fail "skill and role do not pair changelog with get_module_details on one line" $?

# --- generated agents
for dir in claude-agents agents copilot-agents; do
  f="$ROOT/$dir/terraform.md"
  [ "$(field "$f" name)" = terraform ] && [ -n "$(field "$f" description)" ] && [ -n "$(body "$f")" ] && [ "$(body "$f")" = "$(body "$A")" ]
  ok_or_fail "$dir/terraform has name, description, body of roles/terraform.md" $?
done
fm "$ROOT/claude-agents/terraform.md" | grep -qx 'disallowedTools: Agent' && [ "$(field "$ROOT/claude-agents/terraform.md" model)" = inherit ] && [ -z "$(field "$ROOT/claude-agents/terraform.md" tools)" ]
ok_or_fail "claude agent: disallowedTools Agent, model inherit, no tools list (keeps MCP)" $?
[ -f "$ROOT/copilot-agents/terraform.md" ] && [ -z "$(field "$ROOT/copilot-agents/terraform.md" tools)" ] && [ -z "$(field "$ROOT/copilot-agents/terraform.md" model)" ]
ok_or_fail "copilot agent: no tools list (all tools incl. MCP), no model" $?
AGY_TOOLS='view_file list_dir find_by_name grep_search replace_file_content multi_replace_file_content write_to_file run_command command_status'
tools=$(field "$ROOT/agents/terraform.md" tools | tr -d '[],'); bad=0; [ -n "$tools" ] || bad=1
for t in $tools; do printf ' %s ' "$AGY_TOOLS" | grep -q " $t " || bad=1; done
ok_or_fail "agy agent lists only known agy tools" $bad
fm "$ROOT/agents/terraform.md" | grep -qx 'inheritMcp: true'
ok_or_fail "agy agent: inheritMcp true (reaches the MCP tools)" $?

mkdir -p "$T/gen"
"$ROOT/scripts/build-agents" "$T/gen" >/dev/null 2>&1 \
  && diff -r "$T/gen/agents" "$ROOT/agents" >/dev/null \
  && diff -r "$T/gen/claude-agents" "$ROOT/claude-agents" >/dev/null \
  && diff -r "$T/gen/copilot-agents" "$ROOT/copilot-agents" >/dev/null
ok_or_fail "generated agents are up to date (scripts/build-agents)" $?

# --- agy rule
R="$ROOT/rules/terraform.md"
[ "$(field "$R" trigger)" = glob ] && field "$R" globs | grep -qF '*.tf' && field "$R" globs | grep -qF '*.tfvars'
ok_or_fail "agy rule: trigger glob, globs *.tf and *.tfvars" $?

# --- validators
if command -v claude >/dev/null; then
  out=$(claude plugin validate "$ROOT" 2>&1)
  if [ $? -eq 0 ] && ! printf '%s' "$out" | grep -qi 'warning'; then
    echo "ok   claude plugin validate"
  else
    echo "FAIL claude plugin validate"; printf '%s\n' "$out"; fails=$((fails + 1))
  fi
else
  echo "skip claude plugin validate (claude not installed)"
fi
if command -v agy >/dev/null; then
  out=$(agy plugin validate "$ROOT" 2>&1)
  if [ $? -eq 0 ] && printf '%s' "$out" | grep -q 'skills *: 1 processed' && printf '%s' "$out" | grep -q 'agents *: 1 processed' && printf '%s' "$out" | grep -q 'mcpServers *: 1 processed'; then
    echo "ok   agy plugin validate"
  else
    echo "FAIL agy plugin validate"; printf '%s\n' "$out"; fails=$((fails + 1))
  fi
else
  echo "skip agy plugin validate (agy not installed)"
fi

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
