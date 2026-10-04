---
name: verify-and-handoff
description: Use before saying done, fixed, working or passing - run the commands that prove it, show the output, then hand off for review.
---

# Verify, then hand off

## Verify

Before any claim of "done", "fixed", "working" or "passing":

1. Decide which command proves the claim (tests, build, lint, running the thing).
2. Run it fresh, now. Not an earlier run, not a subagent's report.
3. Read the full output: exit code, failure count.
4. Claim only what the output shows, and show it.

Couldn't verify something? Say so plainly. "Should work" is not verification.

## Hand off

Leave everything uncommitted. Then give the user:

- **Changed files** — one line each on what changed
- **Tested** — the commands run and their results
- **Unsure / left out** — open questions, skipped items, assumptions

Then wait. The user reviews and may come back for another round.
