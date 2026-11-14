---
name: tdd
description: Use when implementing any feature or bugfix - write a failing test first, watch it fail for the right reason, then write the minimum code to pass.
---

# Test first

## Cycle

1. **Red.** Write one test for the next bit of behavior. Run it. Confirm it fails, and fails for the *right reason* (missing behavior, not a typo or import error).
2. **Green.** Write the minimum code to make it pass. Run it again, plus the rest of the suite.
   **Check the test:** name a code change that would make it fail again. Can't name one? It guards nothing: improve it or drop it.
3. **Refactor** only while everything is green. Re-run after.

Repeat per behavior.

## Only useful tests

- Write a test only if it would catch a real regression in behavior that matters. Ask: "if this test didn't exist, which bug could slip through?" No answer → don't write it.
- One test per behavior or branch; no variants that go through the same code path. Edge and boundary cases (empty, limits, off-by-one, error paths) count as separate behaviors.
- No tests that only check a file contains some text, and no tests of the language, framework or library itself.
- One-off verification (proving once that it works) runs in a scratch dir, not in the repo; put the result in the handoff.

## Rules

- A test that passed immediately proves nothing. Fix the test until you've seen it fail.
- Bug fix: first write a test that reproduces the bug (unless no useful test is possible, see below).
- Test real behavior, not mocks of it.
- No code "for later" that no test asks for.
- Wrote code before the test? Delete it and start from the test. (Not for changes where no useful test is possible, see below.)

## No test setup?

Say so and ask the user how they want to verify (add a test framework, a script, a manual check). Don't decide alone.

## No useful test possible?

Docs, wording or config with no behavior to guard: don't write a test for it. Say so, and say how you verified it instead (ran the suite, validated, checked it by hand).
