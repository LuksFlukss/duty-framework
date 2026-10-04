# duty-framework

My working rules ([RULES.md](RULES.md)) loaded into every session of Claude Code, GitHub Copilot CLI and Gemini CLI, plus five small skills. A lean take on [superpowers](https://github.com/obra/superpowers): no worktrees, no branches, no commits — all changes stay local for review.

- **Session start** injects `RULES.md` and the skill list (also after `/clear` and compaction).
- **Every prompt** gets a one-line reminder: size the task, no git writes, verify before "done".
- **Skills:** `design`, `plan`, `tdd`, `debugging`, `verify-and-handoff`.

Gemini CLI has no hooks; it gets the same rules and skills through `GEMINI.md`, which is sent with every request.

## Install

Claude Code:

```bash
claude plugin marketplace add ~/duty-framework
claude plugin install duty-framework@duty-framework
# or per session: claude --plugin-dir ~/duty-framework
```

GitHub Copilot CLI:

```bash
copilot plugin marketplace add ~/duty-framework
copilot plugin install duty-framework@duty-framework
# or per session: copilot --plugin-dir ~/duty-framework
```

Gemini CLI:

```bash
ln -s ~/duty-framework ~/.gemini/extensions/duty-framework
gemini -l   # should list duty-framework
```

## Test

```bash
tests/test-hooks.sh
```
