---
name: tdd
description: Use when implementing any feature or bugfix - write a failing test first, watch it fail for the right reason, then write the minimum code to pass.
---

# Test first

## Cycle

1. **Red.** Write one test for the next bit of behavior. Run it. Confirm it fails, and fails for the *right reason* (missing behavior, not a typo or import error).
2. **Green.** Write the minimum code to make it pass. Run it again, plus the rest of the suite.
3. **Refactor** only while everything is green. Re-run after.

Repeat per behavior.

## Rules

- A test that passed immediately proves nothing. Fix the test until you've seen it fail.
- Bug fix: first write a test that reproduces the bug.
- Test real behavior, not mocks of it.
- No code "for later" that no test asks for.
- Wrote code before the test? Delete it and start from the test.

## No test setup?

Say so and ask the user how they want to verify (add a test framework, a script, a manual check). Don't decide alone.
