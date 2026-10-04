# Sourced by the hooks. Prints $2 as hook context for event $1 in the format the current CLI expects.
escape_for_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

emit() {
  local ctx
  ctx=$(escape_for_json "$2")
  # Claude Code wants the nested form; Copilot CLI (COPILOT_CLI=1) and others want top-level.
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -z "${COPILOT_CLI:-}" ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$ctx"
  else
    printf '{"additionalContext":"%s"}\n' "$ctx"
  fi
}
