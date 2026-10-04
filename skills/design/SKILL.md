---
name: design
description: Use before building anything medium or large - understand the goal, ask one question at a time, propose a short design and wait for OK.
---

# Design

Goal: you and the user agree on what to build before any code is written.

## Steps

1. **Size it.** State it as `Size: small|medium|large|quick` at the start of your reply, so the user can correct you.
   - Small: skip this skill, just do it.
   - Medium: a few sentences of plan in chat, wait for OK, then do it, then a refuter review before handoff.
   - Large: continue below.
   - "quick" from the user: skip the ceremony.
2. **Read the current architecture first.** Search the repo (read-only) for its stack, structure and conventions, plus the relevant code, docs and recent changes, so the design builds on what's there and your questions are informed. Still unsure about the design after that? Ask in step 3.
3. **Ask what they're trying to achieve.** One question per message. Prefer multiple choice. Stop asking once you can describe the outcome and how you'd know it works.
4. **Propose a short design:**
   - what changes and why
   - which tech (best fit for the circumstances) and which files
   - trade-offs, and the alternative you rejected
   - how it will be verified
5. **Wait for OK.** No implementation, scaffolding or installs before it. An answer to a clarifying question is not an OK: ask for it explicitly. Then use the `plan` skill.

## Rules

- Ambiguous? Ask. Don't guess and build.
- Build only what was asked. Reuse what the repo already has.
- Propose the best solution for the circumstances, not the most basic one or dated tech. Then keep the design small; don't overcomplicate it.
- No design docs or spec files unless the user asks for one; the design lives in chat.
