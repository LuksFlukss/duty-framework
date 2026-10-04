---
name: plan
description: Use after a design is approved and before touching code - break the work into small verifiable steps, show the plan, wait for "go", then stick to it.
---

# Plan

## Write the plan

Small steps, each with:

| # | Files touched | What changes | How to verify |
|---|---------------|--------------|---------------|

- Each step is a few minutes of work and ends with something you can check (a test, a command, an output).
- Code steps go test-first (see `tdd`): failing test, then implementation.
- Last step: verify everything and hand off (see `verify-and-handoff`).
- No commit steps. Changes stay uncommitted.
- Large task: run it as a team (see `team`). Mark which role does each step and which steps can be handed to subagents in parallel (no shared files).

Show the plan in chat. **Wait for "go".**

## Execute the plan

- Work the steps in order. Run each step's verification and look at the output before moving on.
- Steps marked for subagents: follow `team` (brief, refute, send back, verify yourself).
- Stick to the plan. If a step turns out wrong or impossible, **stop and tell the user** what you found and what you propose. Don't silently change course.
- Don't touch files outside the plan. Don't reformat code you didn't change.
