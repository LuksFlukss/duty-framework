---
name: design
description: Use before building anything medium or large - understand the goal, ask one question at a time, propose a short design and wait for OK.
---

# Design

Goal: you and the user agree on what to build before any code is written.

## Steps

1. **Size it.** Say whether the request is small, medium or large, so the user can correct you.
   - Small: skip this skill, just do it.
   - Medium: a few sentences of plan in chat, then do it.
   - Large: continue below.
   - "quick" from the user: skip the ceremony.
2. **Read first.** Look at the relevant code, docs and recent changes (read-only) so your questions are informed.
3. **Ask what they're trying to achieve.** One question per message. Prefer multiple choice. Stop asking once you can describe the outcome and how you'd know it works.
4. **Propose a short design:**
   - what changes and why
   - which files
   - trade-offs, and the alternative you rejected
   - how it will be verified
5. **Wait for OK.** No implementation, scaffolding or installs before it. Then use the `plan` skill.

## Rules

- Ambiguous? Ask. Don't guess and build.
- Build only what was asked. Reuse what the repo already has.
- No design docs or spec files unless the user asks for one; the design lives in chat.
