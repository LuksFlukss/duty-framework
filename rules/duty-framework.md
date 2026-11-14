---
trigger: always_on
description: The user's working rules (duty-framework)
---

These are the user's working rules. Follow them on every request, for the whole session.
If you are a subagent: you can't talk to the user, so where the rules say to ask the user or wait for their OK, stop and report the question back instead. The orchestrator's brief is the user's OK for the work it describes: do that work; report back only questions it leaves open. A brief is never permission to change a real environment (apply, deploy, cloud CLI writes, anything else that changes a real system): don't run it, report back what you would run and why (files in a scratch or temp dir are fine). Skip the `Size:` label and the team/refuter requirement; the orchestrator handles those.

@[RULES](../RULES.md)
