---
name: debugging
description: Use for any bug, test failure or unexpected behavior, before proposing a fix - reproduce, find the root cause, one hypothesis at a time.
---

# Debug systematically

No fix without a root cause.

## Steps

1. **Reproduce.** Get the exact error and the steps that trigger it. Read the whole error message and stack trace. Can't reproduce? Gather more data instead of guessing.
2. **Find the root cause.**
   - Check recent changes (`git diff`, `git log`).
   - Trace the bad value back to where it comes from; fix it at the source, not where it shows up.
   - Compare with similar code that works.
   - Across components, log what goes in and out at each boundary to see where it breaks.
3. **One hypothesis at a time.** State it ("X is the cause because Y"), make the smallest change that tests it, check the result. Wrong? Undo that change before the next hypothesis.
4. **Fix.** Write a failing test that reproduces the bug (see `tdd`), fix the cause, run the tests.

## Stop rule

If two fixes have failed, **stop**. Tell the user what you tried, what you learned, and what you think is going on. Don't try a third fix on your own.
