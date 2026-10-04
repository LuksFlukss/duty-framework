# duty-framework

My working rules ([RULES.md](RULES.md)) loaded into every session of Claude Code, GitHub Copilot CLI and Antigravity CLI, plus five small skills. A lean take on [superpowers](https://github.com/obra/superpowers): no worktrees, no branches, no commits — all changes stay local for review.

- **Session start** injects `RULES.md` and the skill list (also after `/clear` and compaction).
- **Subagents** (Claude Code) get `RULES.md` too, with a note to report questions back instead of asking the user.
- **Every prompt** gets a one-line reminder: size the task, no git writes, verify before "done".
- **Skills:** `design`, `plan`, `tdd`, `debugging`, `verify-and-handoff`.

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

Claude Code stays on the installed `version` until it changes, so when you change the plugin, bump `version` in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` before pushing.

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

## Test

```bash
tests/test-hooks.sh
```
