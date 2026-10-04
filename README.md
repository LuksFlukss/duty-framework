# duty-framework

My working rules ([RULES.md](RULES.md)) loaded into every session of Claude Code, GitHub Copilot CLI and Antigravity CLI, plus small skills and a team of role subagents. A lean take on [superpowers](https://github.com/obra/superpowers): no worktrees, no branches, no commits — all changes stay local for review.

- **Session start** injects `RULES.md` and the skill list (also after `/clear` and compaction).
- **Subagents** (Claude Code) get `RULES.md` too, with a note to report questions back instead of asking the user.
- **Every prompt** gets a one-line reminder: size the task, no git writes, verify before "done".
- **Skills:** `design`, `plan`, `tdd`, `debugging`, `verify-and-handoff`, `team` (orchestrate the role agents on large tasks), `agents` (personalise their model and effort).
- **Role agents** on all three CLIs: `scout`, `researcher`, `builder`, `refuter`, `debugger`.

Antigravity CLI doesn't use the hooks; it gets the same rules through an `always_on` rule (`rules/duty-framework.md`, which includes `RULES.md`) that is sent with every request, and loads the same skills.

## Install

Claude Code:

```bash
claude plugin marketplace add LuksFlukss/duty-framework
claude plugin install duty-framework@duty-framework
```

GitHub Copilot CLI:

```bash
copilot plugin marketplace add LuksFlukss/duty-framework
copilot plugin install duty-framework@duty-framework
```

Antigravity CLI:

```bash
git clone https://github.com/LuksFlukss/duty-framework ~/duty-framework
agy plugin install ~/duty-framework
agy plugin list   # should list duty-framework
```

Local checkout instead of GitHub (Claude, Copilot): replace `LuksFlukss/duty-framework` with the path, e.g. `~/duty-framework`, or load it per session with `--plugin-dir ~/duty-framework` (Claude, Copilot).

## Update

After updating, start a new session: plugins load at session start.

Claude Code:

```bash
claude plugin marketplace update duty-framework
claude plugin update duty-framework@duty-framework
```

Claude Code stays on the installed `version` until it changes, so when you change the plugin, bump `version` in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` and `.plugin/plugin.json` before pushing.

GitHub Copilot CLI:

```bash
copilot plugin marketplace update duty-framework
copilot plugin update duty-framework
```

Antigravity CLI (installs a copy, so reinstall after pulling):

```bash
git -C ~/duty-framework pull
agy plugin uninstall duty-framework && agy plugin install ~/duty-framework
```

Personalised agents: run `scripts/personalize apply` after any update so your personal copies pick up the new role instructions.

## Agents

Five role agents, used by the `team` skill: `scout` (finds code), `researcher` (checks facts), `builder` (implements test-first), `refuter` (re-checks the work), `debugger` (root cause only). By default every role runs on the session's default model.

| CLI | Agent name | Loaded from |
|-----|------------|-------------|
| Claude Code | `duty-framework:<role>` | `claude-agents/` (listed in `.claude-plugin/plugin.json`) |
| Copilot CLI | `duty-framework:<role>` | `copilot-agents/` (set in `.plugin/plugin.json`) |
| Antigravity | `<role>` | `agents/` (the only folder it reads) |

### Personalise model and effort

Ask for the `agents` skill ("personalise my agents"). It walks one CLI at a time: shows each role's current model and effort, then asks for the roles you want to change, with the models that CLI offers. Choices are saved per user in `~/.config/duty-framework/agents.json` and kept between sessions; start a new session to load them.

The skill drives `scripts/personalize`, which you can also run directly:

```bash
scripts/personalize models copilot                 # models to pick from
scripts/personalize efforts copilot gpt-5.4        # efforts that model supports
scripts/personalize show claude                    # current choice per role
scripts/personalize set copilot builder gpt-5.4 high
scripts/personalize set claude builder default     # back to the session default
scripts/personalize apply                          # after a plugin update
```

How each CLI gets your choice:

- **Copilot:** its own per-agent setting in `~/.copilot/settings.json` (`subagents.agents["duty-framework:<role>"]`). Copilot only reveals which efforts a model supports by trying, so the first pick of a model + effort costs one tiny Copilot request; the answer is remembered in `~/.config/duty-framework/copilot-efforts.json`.
- **Claude Code, Antigravity:** no per-agent override exists, so a personal copy `duty-<role>` is written to `~/.claude/agents/` or `~/.gemini/config/agents/`. The `team` skill uses it when present. Antigravity agents take only a tier (`flash_lite`, `flash`, `pro`) and no effort.

Personal copies hold the role instructions from when they were written; run `scripts/personalize apply` after updating the plugin.

## Develop

- Role instructions live in `roles/<role>.md`. Don't edit `agents/`, `claude-agents/` or `copilot-agents/` by hand: run `scripts/build-agents` to regenerate them (the per-CLI frontmatter is in that script). The tests fail if they're out of date.
- When releasing, bump `version` in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` and `.plugin/plugin.json`.

## Test

```bash
tests/test-hooks.sh
```

Runs the hooks under each CLI's environment, checks the generated agents and manifests, and exercises `scripts/personalize` against a throwaway HOME with a fake `copilot` (your real config is never touched).
