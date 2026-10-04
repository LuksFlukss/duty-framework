---
name: explain
description: Use when the user asks to explain the flow, a repo or how something works - read the repo (read-only), size it, walk through what it does and why step by step with terminal diagrams, give 3–5 suggestions or questions, then offer to save it as a Markdown file.
---

# Explain the flow

Goal: the user understands what the repo (or the part they named) does, in what order, and why it's built that way. Read-only: no edits, no installs, nothing run that changes state.

## Steps

1. **Size it, twice.**
   - **The task:** an explanation is a question, so start your reply with `Size: small`, whatever the repo's size (`Size: quick` if the user said "quick"). Writing the Markdown file in step 6 stays part of this small task.
   - **The repo:** count files, entry points and moving parts, and state it on its own line as `Repo size: small|medium|large`. It decides how deep you go:
     - **Small** (a script, a few files): read everything yourself; draw a diagram only if the flow branches or crosses components.
     - **Medium** (one app or service): read the entry points and follow the main flow; diagram the architecture and the main flow.
     - **Large** (many modules, services or infra): map it first with `scout` and `researcher` subagents in parallel, then read the key paths yourself. Brief each one with the rules (read-only, no git writes, no apply/deploy, report questions back instead of guessing) and what to return: `path:line` facts only, short. Explain the overall flow, then each main part.
   - Asked about one feature or path? Size and explain only that.
2. **Read before explaining.** Stack, entry points (main, routes, handlers, CLI, hooks, pipelines), config, the data's path in and out, external calls. Never explain code you haven't opened; mark anything inferred as such. Skip generated, vendored, minified and lock files, and filter out embedded blobs (base64 data URIs, inline images) when reading, so they don't flood the context.
3. **Explain in the terminal, step by step**, in the order things run:
   - an overview first: what it is, who or what triggers it, what comes out
   - then numbered steps, each with **what** happens, **why** (the reason or trade-off behind it) and **where** (`path:line`)
   - plain language; define a term once when it's first used
4. **Draw diagrams where they help**: a picture of the structure or the flow beats a paragraph. The terminal doesn't render Mermaid, so draw in plain text inside a code block, at most ~80 columns wide:
   - architecture: boxes and arrows between components
   - flow or sequence: who calls whom, in order
   - data or state: how data changes along the way

   ```
   ┌──────────┐ 1. request ┌──────────┐ 3. save  ┌──────────┐
   │  Client  │ ─────────> │   API    │ ───────> │    DB    │
   └──────────┘            └──────────┘          └──────────┘
                                │ 2. validate (src/api/validate.ts:12)
                                v
                           ┌──────────┐
                           │ Validator│
                           └──────────┘
   ```
   Number the arrows in the order things happen, and match the numbers to your steps. Use plain `>` and `v` for arrowheads (some terminals draw `▶` double-width). Skip a diagram when it adds nothing, e.g. a single linear script.
5. **3–5 suggestions and questions**, only ones that really apply: improvements (bugs, risks, missing tests, dead code, unclear naming, security) and questions where the intent is unclear. Each one: what, where (`path:line`) and why it matters. Fewer than 3 real ones? Give fewer and say so; never pad.
6. **Offer the Markdown file.** End by asking whether to write what you explained to a Markdown file (suggest a name, e.g. `FLOW.md` in the repo root). Write it only on a yes: the same content and diagrams, nothing else. That file is the only change you make.

## Rules

- Read-only until the user says yes to the Markdown file.
- Facts come from the code you read, anchored to `path:line`; say "probably" or "unclear" when they aren't.
- Explain what is there; don't redesign it. Changes belong in the suggestions.
