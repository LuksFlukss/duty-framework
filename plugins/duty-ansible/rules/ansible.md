---
trigger: glob
globs: "**/roles/**/*.yml, **/roles/**/*.yaml, **/playbooks/**/*.yml, **/playbooks/**/*.yaml, **/group_vars/**, **/host_vars/**, **/ansible.cfg, **/galaxy.yml, **/molecule/**/*.yml"
description: Ansible content (duty-ansible)
---

Working with Ansible: load the `ansible` skill (duty-ansible) first and delegate to the `ansible` agent. Never run `ansible-playbook` for a real run (including `--check`), ad-hoc `ansible` commands, `ansible-navigator run` / `exec`, `ansible-pull`, `ansible-console`, `ansible-runner run` / `start` / `worker`, `ansible-galaxy` publish / import / delete, `ansible-vault decrypt` / `view` / `edit` / `rekey` or the MCP execution tools; give the user the run command and wait.
