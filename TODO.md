# TODO

## stop-gate

- Copilot's real `apply_patch` argument shape is still unconfirmed. The gate accepts both `{"input": "<patch>"}` and a raw patch string. A local session log (`~/.copilot/session-state/1352ebab-57fb-4254-bfce-206c54c1d22a/events.jsonl`) contains `apply_patch` calls: check their shape, and add it as a fixture in `tests/test-hooks.sh` if it differs.
- A `SendMessage` to a refuter counts as a review when `to` equals the refuter's `name` or the `agentId:` from its tool result. The `agentId:` path matches real Claude transcripts (5 sessions resumed a refuter by its agentId, taken from the `agentId: <id>` trailer in the launch result). The `name` path is still unconfirmed: no local transcript spawns a refuter with a `name`.

## Other

- Rotate the GitHub OAuth token in `~/.copilot/config.json`; it was printed in a local Claude session on 2026-10-10.
- On the Copilot device, check `copilot --version` (it needs ≥ 1.0.65 to pass the per-prompt reminder to the model) and choose a stronger model with `/model`. In testing, the default was Claude Sonnet 5. The WSL machine already has 1.0.95.
