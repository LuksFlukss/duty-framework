---
name: team
description: Use for large tasks - you are the orchestrator; decide which role subagents (scout, researcher, builder, refuter, debugger) the task needs, brief them, never trust their "done", and verify yourself.
---

# Team: orchestrate large tasks with role subagents

You are the **orchestrator**. You frame the task, write the spec, decide which
roles to run, brief them, judge their reports and verify the result yourself.
The user's gates stay the same: OK on the design, "go" on the plan, their
review at the end.

Small or medium task? Don't use this skill; do the work yourself.

## Roles

| Role | Model | Can edit | Does |
|------|-------|----------|------|
| `scout` | haiku | no | Finds files, symbols, call sites; reports `path:line` locations |
| `researcher` | sonnet | no | Verifies facts (code behavior, docs, patterns to reuse), marks `UNVERIFIED:` |
| `builder` | sonnet | yes | Implements one spec test-first, reports actual verification output |
| `refuter` | opus | no | Re-checks the work against the spec and re-runs verification itself |
| `debugger` | opus | no | Root cause only, when a failure survives a fix round |

In Claude Code they're `duty-framework:<role>` subagents. Elsewhere, start a
general subagent and paste the role's brief from this plugin's
`agents/<role>.md` into its instructions.

## Decide the team

Run only what's needed, and tell the user which roles you'll use and why
before starting them:

- **scout**: skip if every file to touch is already known.
- **researcher**: skip if nothing unfamiliar or external is involved.
- **builder**: one per independent part of the plan; parallel only if they
  touch no shared files. Tightly coupled work goes to one builder, or do it
  yourself.
- **refuter**: **never skipped** for a large task.
- **debugger**: not by default; only per "Send back" below.

## Process

1. **Understand** (`design` skill). Scout and researcher may run here, in
   parallel, read-only, to map the repo before you propose the design.
2. **Spec and plan** (`plan` skill). Write a spec a fresh agent with zero
   context can execute: goal, files (`path:line`), approach, reuse,
   constraints/non-goals, acceptance criteria, verification command and
   expected result. In the plan, mark which role does each step. Wait for "go".
3. **Build.** Brief each builder with its part of the spec plus the rules
   (see Briefs). Wait for its report.
4. **Refute.** Give the refuter the spec, the changed files and the builder's
   claims. It reports `CONFIRMED` or `FINDINGS`.
5. **Send back** (max 2 rounds). Findings go back to a builder verbatim with a
   fix instruction, then refute again. A failure that survives a fix round
   with an unclear cause → `debugger` first, its diagnosis feeds the next
   builder round. Still failing after 2 rounds → stop and put the history to
   the user.
6. **Verify yourself** (`verify-and-handoff`). Read the changes, re-run the
   verification: the builder's and refuter's word are inputs, not proof.
7. **Hand off**: the usual list, plus roles run/skipped and why, refuter
   findings and how they were resolved.

## Briefs

Subagents don't see this conversation. Every brief is self-contained:

- **Role** and **task** in your own words; the relevant spec section.
- **Repo path**, files in scope, what not to touch.
- **Rules**: no git writes, no apply/deploy, test first (builder), report
  questions instead of guessing.
- **Verification command** and expected result.
- **What to return**, in what shape and length.
