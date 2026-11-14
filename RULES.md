# How to work with me

## Git: local changes only
- Never run `git commit`, `merge`, `push`, `stash`, `reset`, `checkout -- <file>`, or create branches/PRs. Read-only git (`status`, `diff`, `log`, `blame`) is fine.
- Leave all changes uncommitted; I review and write my own commit messages.
- In Claude Code a hook blocks git writes and shows a permission prompt for apply/deploy commands (deletes marked `DESTRUCTIVE:`); if it blocks something I asked for, tell me instead of working around it.

## Real environments: read-only
- Never apply, deploy, publish or otherwise change anything outside the working copy without my explicit permission, with any tool: infrastructure (`terraform apply`/`destroy`, `kubectl apply`/`delete`, `helm install`/`upgrade`), cloud CLIs, database migrations or writes, package publishes, releases.
- Read-only and dry-run commands are fine: `plan`, `validate`, `lint`, `diff`, `--dry-run`, `get`/`describe`, `template`. Unsure whether a command changes something real? Treat it as an apply and ask.
- When I allow a change: first run read-only checks of the current state and name the way back (backup, snapshot or previous value).
- Afterwards leave it as you found it (stop or remove what you only needed temporarily) and check the end state.
- In the handoff, list every change made to a real environment and how to undo it.

## Subagents
- Hand work to subagents when it helps (parallel independent steps, broad searches across many files, a fresh-eyes review); do small or tightly coupled work yourself.
- When you start a subagent, its instructions must hold these rules and the task's limits (it doesn't see this conversation): at minimum no git writes, no apply/deploy, verify before claiming done, report questions back instead of guessing, and exactly what to return.
- You own the result: check its work yourself (read the changes, re-run the checks) before building on it or claiming done. My gates (OK, "go") stay the same.

## Match the process to the task
- Start your reply to each new task with `Size: small|medium|large|quick` so I can correct it.
- **Small** (typo, rename, one-line fix, a question): just do it.
- **Medium** (a bug, a small feature): one short message with what changes, which files and how to verify it; wait for my OK (one OK covers design and plan), then do it, then a refuter subagent reviews it before handoff (`team`, steps 4–5). Building something new? Check `prior-art` before that message.
- **Large** (new feature, refactor, many files): all steps below, as orchestrator: load the `team` skill and run it. The refuter is never skipped.
- **Quick** (I said "quick"): skip the ceremony.
- Steps 1–2 below are the full process for large tasks; for medium, the short plan above replaces them.

## 1. Understand before building
- Before proposing a design, look at the repo's architecture (stack, structure, conventions) so the design fits it; still unsure about the design after that? Ask me.
- Before writing code for anything non-trivial, ask what I'm actually trying to achieve, one question at a time.
- Anything ambiguous? Ask; don't guess and build.
- Building something new? First check whether a tool or solution already exists (`prior-art`): show me the candidates and ask whether to use, adapt or build our own.
- Propose a short design (what changes, which files, trade-offs). Wait for my OK before implementing.
- Answering a clarifying question is not an OK; ask for the OK explicitly.

## 2. Plan
- Small steps, each with files touched, what changes, how to verify it. Show me the plan; wait for "go".
- Stick to the plan. If it turns out wrong, stop and tell me instead of silently changing course.

## 3. Test first
- Write a failing test, run it, confirm it fails for the right reason. Then the minimum code to pass; run it again. Refactor only with tests green.
- Only useful tests: each must catch a real regression; one per behavior (edge cases count as their own), no duplicates, no tests that only check text or test the language/framework itself. One-off checks run in a scratch dir, not in the repo.
- No test setup? Say so and ask how I want to verify.
- No useful test possible (docs, wording or config with no behavior to guard)? Don't write one; say so and how you verified it instead.

## 4. Debug systematically
- Reproduce first, then find the root cause (read the error, trace the data, check recent changes) before changing code. No guessed fixes.
- One hypothesis at a time. If two fixes fail, stop and explain what you've learned.

## 5. Best solution, not overcomplicated
- Build only what was asked: no speculative features, no "while I'm here" changes.
- Pick the best solution for the circumstances (problem, repo, scale), not the most basic one: for new work the current standard tech for the job (frontend, backend, data, infra or tooling); in an existing repo, reuse its code, patterns and stack.
- No extra libraries, layers, abstractions or config until needed. Don't touch unrelated files or reformat code you didn't change.

## 6. Verify before claiming done
- Never say "fixed", "done" or "working" without running the tests or commands that prove it and showing the result. Couldn't verify? Say so plainly.

## 7. Hand off for review
When finished, give me: changed files (one line each on what changed), what you tested and the results, any change made to a real environment and how to undo it, and anything you're unsure about or left out.
