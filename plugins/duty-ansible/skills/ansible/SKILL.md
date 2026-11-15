---
name: ansible
description: Use when working with Ansible (playbooks, roles, collections, inventories) - follow current guidelines through the Ansible development tools MCP, module docs from ansible-doc, write or change content, review playbooks and PRs, upgrade ansible-core and collections. Never runs playbooks or ad-hoc commands.
paths: ["**/roles/**/*.yml", "**/roles/**/*.yaml", "**/playbooks/**/*.yml", "**/playbooks/**/*.yaml", "**/group_vars/**", "**/host_vars/**", "**/ansible.cfg", "**/galaxy.yml", "**/molecule/**/*.yml"]
---

# Ansible

Ansible playbooks, roles and collections. Current reference (verified 2026-11): ansible-core 2.22 latest (2.21 still supported), `ansible` package 14.x, ansible-lint 26.x. Check what the project actually uses (`ansible --version`, `ansible-lint --version`, `requirements.yml`, `galaxy.yml`, `execution-environment.yml`) and target that.

## Guidelines first: the Ansible MCP

The plugin starts Red Hat's Ansible development tools MCP server in Docker, with the project mounted read-only. Use it before writing or judging anything:

| Need | Tool |
|------|------|
| The principles behind good Ansible | `zen_of_ansible` |
| Best practices for a role, playbook, collection, inventory, ... | `ansible_content_best_practices` with a `topic`, before writing any of them |
| What the server offers | `list_available_tools` |

- Module and plugin docs: run `ansible-doc <fqcn>` locally (`ansible-doc -l` to list). Never from memory; quote option names exactly and check for deprecations.
- Collection versions: `ansible-galaxy collection list`, then Galaxy for the latest.
- Never call the MCP execution tools: `ansible_navigator` (runs playbooks), `ade_setup_environment` and `adt_check_env` (install packages), `define_and_build_execution_env`, `create_ansible_projects`, `ansible_lint` with `fix`. They run or change things, and the image has no ansible-core to run them. Lint with local `ansible-lint` instead.

**MCP tools unavailable? Stop.** Tell the user to start Docker and restart the session. No web search or memory fallback for the guidelines.

## Safety

- Allowed: read files, `ansible-lint` (`--fix` only on files in scope), `ansible-doc`, `ansible-playbook --syntax-check`, `--list-tasks`, `--list-hosts`, `--list-tags`, `ansible-inventory --graph` / `--list` on local static inventory files, `ansible-galaxy collection install` / `role install` from requirements into a project-local path (`-p ./collections`, `-p ./roles`). `molecule` only when the user asks (it creates containers or VMs).
- Never run: `ansible-playbook` for a real run (including `--check`, which connects to hosts and runs modules), ad-hoc `ansible` commands, `ansible-navigator run` / `exec`, `ansible-pull`, `ansible-console`, `ansible-runner run` / `start` / `worker`, `ansible-galaxy` publish / import / delete, `ansible-vault decrypt` / `view` / `edit` / `rekey` (secrets), the MCP execution tools above. They reach real hosts, Galaxy and secrets. The rule is absolute.
- Need a run? Give the user the run command, then wait:

  ```bash
  ansible-playbook -i <inventory> site.yml --check --diff
  ansible-playbook -i <inventory> site.yml
  ```

  Continue only when the user says it ran, then review the output they paste or save.

## Write or change content

1. Read the existing layout and naming; match it. Ask `ansible_content_best_practices` for the topic first.
2. Look up every module with `ansible-doc`. Follow the Ansible docs tips and tricks, the Red Hat CoP good practices (https://redhat-cop.github.io/automation-good-practices/) and the ansible-lint `production` profile:
   - FQCN for every module (`ansible.builtin.copy`, not `copy`).
   - Name every play, block and task: imperative, capitalized.
   - Explicit `state:`. Idempotent: prefer a module over `command` / `shell`; when unavoidable, use `creates` / `removes` / `changed_when` / `failed_when`.
   - `true` / `false` booleans; `.yml`, 2-space indent, files start with `---`.
   - Role variables prefixed with the role name (`<role>_*`); user-tunable ones in `defaults/main.yml`, internal constants in `vars/`; inputs described in `meta/argument_specs.yml`.
   - Handlers for restarts. `become` at the narrowest scope.
   - `no_log: true` on tasks handling secrets; secrets from `ansible-vault` or an external lookup, never plaintext.
   - Tags sparingly; no `ignore_errors`; choose `import_*` (static) or `include_*` (dynamic) deliberately.
   - Templates start with `{{ ansible_managed | comment }}`.
   - Pin collection versions in `collections/requirements.yml`.
   - New role or collection: scaffold with `ansible-galaxy role init` or `ansible-creator init` (local files only), then match the layout.
3. Make the smallest change. Don't add variables, defaults or abstractions nobody asked for.
4. Check: `ansible-lint --profile production` (or the repo's `.ansible-lint` config), `ansible-playbook --syntax-check`, `yamllint` if configured. Show the output.
5. Give the user the `--check --diff` run command to see the real effect.

## Review a playbook, role or PR

Read the files or the diff. Flag, most serious first:

- Non-idempotent `command` / `shell` (no `creates`, `removes` or `changed_when`).
- Plaintext secrets, secret-handling tasks without `no_log: true`.
- `become: true` at play level where a task would do; `ignore_errors`.
- Unpinned collections or roles; short module names (not FQCN); deprecated modules (`ansible-doc`).
- `state: latest` for packages in production; `hosts: all`; restarts without handlers.

End with a verdict: safe to run / needs changes / needs a question answered.

## Upgrade ansible-core or collections

1. Record the current versions first (`ansible --version`, `ansible-galaxy collection list`, the pins in `requirements.yml`).
2. Read the porting guides (https://docs.ansible.com/ansible/latest/porting_guides/) and each collection's changelog (`CHANGELOG.rst` or `changelogs/changelog.yaml` in the installed collection) for the entries between current and target.
3. Run `ansible-lint` against the target versions.
4. List the breaking changes that touch this content, before editing anything.
5. Change the content, lint, then hand the user the `--check --diff` run and review the result.

## Delegation

Hand Ansible work to the `ansible` agent, with the files, the goal and these safety rules in the brief. It reports what it changed or found, the commands it ran with output, run commands for the user, and open questions.
