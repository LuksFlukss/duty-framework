---
name: agents
description: Use when the user wants to personalise the role agents (scout, researcher, builder, refuter, debugger) - pick a model and effort per role for Claude Code, Copilot or agy; saved per user, kept between sessions.
---

# Agents: personalise model and effort per role

By default every role runs on the session's default model. This skill saves the
user's own choice per role and tool in `~/.config/duty-framework/agents.json`
and applies it. All reading and writing goes through the script; never edit the
config files by hand.

Script: `scripts/personalize` in this plugin (two levels up from this skill's
directory). Below it's written as `personalize`.

## Steps

1. **Tool.** Ask which tool to configure: `claude`, `copilot` or `agy`. Suggest
   the one you're running in.
2. **Current state.** Run `personalize show <tool>` and show the table.
3. **Roles.** Ask which roles to change. Untouched roles keep their setting.
4. **Per role, one question at a time:**
   - Model: run `personalize models <tool>` and offer those, plus `default`
     (the session's model). If the question UI only fits a few options, list
     every model in chat, offer 3 sensible picks plus `default`, and let the user
     type another.
   - Effort: run `personalize efforts <tool> <model>`. Empty output means that
     model takes no effort: skip the question. Otherwise offer those plus
     `default`.
   - Run `personalize set <tool> <role> <model> [effort]` and show its output.
     An error means the input was invalid: show it and ask again.
5. **Confirm.** Run `personalize show <tool>` again and show the table. Tell the
   user to start a new session so the tool loads the change.

## Per tool

- **copilot:** written to `~/.copilot/settings.json` under
  `subagents.agents["duty-framework:<role>"]`; the agent name stays the same.
  Copilot only reveals which efforts a model supports by trying, so the first
  time a model + effort is picked, `set` checks it with one tiny Copilot
  request and remembers the answer. Rejected efforts disappear from `efforts`.
- **claude, agy:** no per-agent override exists, so a personal copy
  `duty-<role>` is written (`~/.claude/agents/`, `~/.gemini/config/agents/`).
  The `team` skill uses `duty-<role>` when it exists.
- **agy** agents only take a tier (`flash_lite`, `flash`, `pro`) and no effort.

After a plugin update, run `personalize apply` so the personal copies pick up
the new role instructions.
