---
name: prior-art
description: Use during design of a medium or large task that builds something new (tool, script, automation, module, feature) - search GitHub, package registries and vendor tools for an existing solution, report the candidates and ask the user whether to use, adapt or build our own. Don't reinvent the wheel.
---

# Prior art

Goal: before designing something new, know whether it already exists, and let the user choose.

## When

- Medium or large task that builds something new: a tool, script, automation, module, integration or feature.
- Runs in `design`, once the goal is clear and before proposing the design.
- Skip it for bug fixes, small or "quick" tasks, config tweaks, and changes to existing code.
- Large task: run the `gh` and MCP registry searches yourself (the `researcher` has no shell or MCP tools) and hand the web and docs search to the `researcher`; judge its report yourself.

## Steps

1. **Name the need in one line**, plus the stack and constraints (language, cloud, license, must run offline, ...).
2. **Search, broad to specific:**
   - The repo and the user's own org first: `gh search repos <terms> --owner <org>`; reuse beats anything external.
   - GitHub: `gh search repos <terms> --sort stars`, `gh search code <terms>`; awesome-lists for the area.
   - Package registries for the stack: npm, PyPI, PowerShell Gallery, Terraform Registry (Terraform MCP), Artifact Hub, crates.io, Go packages.
   - Official vendor tools: a built-in feature, CLI command, portal option, or reference implementation (Microsoft Learn, AWS docs, ...).
   - Web search for niche needs; a more thorough search mode, if your search tool has one, when the first results come back thin.
3. **Check each serious candidate** from its README, docs and repo metadata: what it does, fit to the need, license, last commit/release, stars/downloads, open issues, risks (abandoned, heavy dependencies, security, needs credentials).
4. **Report** as a short table, best fit first, 3–5 candidates at most:

   | Candidate | Link | Does | Fit | License | Maintained | Risk |
   |---|---|---|---|---|---|---|

   Always add a last row **Build our own**: why it might still be the better choice, and roughly what it takes.
   Nothing found? Say what you searched, so the user can judge.
5. **Ask the user**: use as-is, adapt, or build our own; give your recommendation and why. Then wait for their answer before designing further.

## Rules

- Never install, clone or run a candidate during this step; reading READMEs, docs and repo metadata is enough.
- Every claim gets a link; anything you couldn't check is marked `UNVERIFIED:`.
- Keep it short: this informs the design, it isn't a market study.
- Search queries describe the technical need only: no customer, project or personal names.
