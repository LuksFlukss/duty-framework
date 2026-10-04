# How to work with me

## Git: local changes only
- Never run `git commit`, `git merge`, `git push`, `git stash`, `git reset`, `git checkout -- <file>`, or create branches/PRs.
- Read-only git is fine: `git status`, `git diff`, `git log`, `git blame`.
- Leave all changes uncommitted. I review everything and write my own commit messages.

## Real environments: read-only
- Never apply, deploy, publish or otherwise change anything outside the working copy without my explicit permission. That covers any tool: infrastructure (`terraform apply`/`destroy`, `kubectl apply`/`delete`, `helm install`/`upgrade`), cloud CLIs, database migrations or writes, package publishes, releases.
- Read-only and dry-run commands are fine: `plan`, `validate`, `lint`, `diff`, `--dry-run`, `get`/`describe`, `template`.
- Not sure whether a command changes something real? Treat it as an apply and ask.

## Subagents
- Hand work to subagents when it helps: independent steps that can run in parallel, broad searches across many files, a fresh-eyes review. Do small or tightly coupled work yourself.
- When you start a subagent, put these rules and the task's limits in its instructions: it doesn't see this conversation. At minimum: no git writes, no apply/deploy, verify before claiming done, and report questions back instead of guessing. Also say exactly what to return.
- You own the result: check a subagent's work yourself (read the changes, re-run the checks) before building on it or claiming done. My gates (OK, "go") stay the same.

## Match the process to the task
- Start your reply to each new task with `Size: small|medium|large|quick` (quick = I said "quick") so I can correct it.
- **Small** (typo, rename, one-line fix, a question): just do it.
- **Medium** (a bug, a small feature): short plan in chat, then do it; before handoff a refuter subagent reviews the result (see `team`, steps 4–5).
- **Large** (new feature, refactor, anything touching many files): follow all steps below, as orchestrator: load the `team` skill and run it. The refuter is never skipped.
- If I say "quick", skip the ceremony.

## 1. Understand before building
- Before proposing a design, look at the repo's current architecture (stack, structure, conventions) so the design fits it. If you're still unsure about the design after that, ask me.
- Before writing code for anything non-trivial, ask what I'm actually trying to achieve. One question at a time.
- Propose a short design (what changes, which files, trade-offs). Wait for my OK before implementing.
- If something is ambiguous, ask. Don't guess and build.

## 2. Plan
- Break the work into small steps, each with: files touched, what changes, how to verify it.
- Show me the plan. Wait for "go".
- Stick to the plan. If it turns out wrong, stop and tell me instead of silently changing course.

## 3. Test first
- Write a failing test before the implementation. Run it and confirm it fails for the right reason.
- Write the minimum code to make it pass. Run it again.
- Refactor only with tests green.
- If the project has no test setup, say so and ask how I want to verify.

## 4. Debug systematically
- Don't guess at fixes. Reproduce the problem first.
- Find the root cause (read the error, trace the data, check recent changes) before changing code.
- One hypothesis at a time. If two fixes fail, stop and explain what you've learned.

## 5. Best solution, not overcomplicated
- Build only what was asked. No speculative features, no "while I'm here" changes.
- Pick the best solution for the circumstances (the problem, the repo, the scale), not the most basic one. For new work that means the current standard tech for the job, whether frontend, backend, data, infra or tooling. In an existing repo, reuse its code, patterns and stack.
- Implement it without overcomplicating: no extra libraries, layers, abstractions or config until needed.
- Don't touch unrelated files. Don't reformat code you didn't change.

## 6. Verify before claiming done
- Never say "fixed", "done", or "working" without running the tests or commands that prove it, and showing the result.
- If you couldn't verify something, say so plainly.

## 7. Hand off for review
When finished, give me:
- A list of changed files with one line on what changed in each
- What you tested and the results
- Anything you're unsure about or left out
