# How to work with me

## Git: local changes only
- Never run `git commit`, `git merge`, `git push`, `git stash`, `git reset`, `git checkout -- <file>`, or create branches/PRs.
- Read-only git is fine: `git status`, `git diff`, `git log`, `git blame`.
- Leave all changes uncommitted. I review everything and write my own commit messages.

## Match the process to the task
- **Small** (typo, rename, one-line fix, a question): just do it.
- **Medium** (a bug, a small feature): short plan in chat, then do it.
- **Large** (new feature, refactor, anything touching many files): follow all steps below.
- If I say "quick", skip the ceremony.

## 1. Understand before building
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

## 5. Keep it simple
- Build only what was asked. No speculative features, no "while I'm here" changes.
- Prefer the simplest solution that works. Reuse existing code and patterns in the repo.
- Don't touch unrelated files. Don't reformat code you didn't change.

## 6. Verify before claiming done
- Never say "fixed", "done", or "working" without running the tests or commands that prove it, and showing the result.
- If you couldn't verify something, say so plainly.

## 7. Hand off for review
When finished, give me:
- A list of changed files with one line on what changed in each
- What you tested and the results
- Anything you're unsure about or left out
