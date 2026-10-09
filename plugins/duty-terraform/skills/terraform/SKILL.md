---
name: terraform
description: Use when working with Terraform (*.tf, *.tfvars) - research live provider and module docs through the Terraform MCP, write or change code, review plans and PRs, upgrade providers and modules. Never runs plan or apply.
paths: ["**/*.tf", "**/*.tfvars"]
---

# Terraform (Azure and AWS)

Terraform only, not OpenTofu. Clouds: Azure (`azurerm`, `azapi`, Azure Verified Modules, custom modules built on them) and AWS (`aws`, `terraform-aws-modules`). Docs and versions come from the Terraform MCP, never from memory.

## Docs first: the Terraform MCP

The plugin starts HashiCorp's Terraform MCP server (public registry tools only) in Docker. Use it before writing or judging anything:

| Need | Tool |
|------|------|
| Latest provider version | `get_latest_provider_version` (namespace, name) |
| Resource, data source, function docs | `search_providers` (`provider_document_type`: `resources`, `data-sources`, `functions`, `actions`, `list-resources`), then `get_provider_details` with the doc id |
| Upgrade and migration guides | `search_providers` with `provider_document_type=guides` |
| What a provider supports | `get_provider_capabilities` |
| Modules (AVM `Azure/avm-res-*`, `Azure/avm-ptn-*`, `terraform-aws-modules/*`) | `search_modules`, then `get_module_details` (inputs, outputs, examples) |
| Latest module version | `get_latest_module_version` |
| Sentinel policies | `search_policies`, `get_policy_details` |

**MCP tools unavailable? Stop.** Tell the user to start Docker and restart the session. No web search or memory fallback.

## Safety

- Allowed: read files, `terraform fmt`, `terraform init -backend=false`, `terraform validate`, `tflint`, and `git ls-remote` to see what a module `?ref=` resolves to on origin (a local branch can differ).
- Never run: `terraform plan`, a normal `terraform init`, `terraform init -upgrade` (any form), apply, destroy, import, any `terraform state` command, taint, workspace changes. They reach real state and backends. The rule is absolute.
- Need a plan? Give the user the plan command, then wait:

  ```bash
  terraform init
  terraform plan -out=tfplan
  terraform show -no-color tfplan > plan.txt
  ```

  Continue only when the user says it ran, then review `plan.txt`.
- `terraform init` failing on Azure DevOps git modules with "Corrupted MAC on input" is a transport flake: tell the user to re-run their `terraform init`; never re-run a normal init yourself, and don't rewrite module sources.
- `terraform init -backend=false` failing because `.terraform.lock.hcl` doesn't match the new version or constraints: STOP and hand it back. Tell the user they can remove `.terraform/` and `.terraform.lock.hcl` (or resolve it their own way), then wait until they say to continue. Never delete them yourself and never work around it.

## Research

1. Name the provider/module and the version in use (`.terraform.lock.hcl`, `required_providers`, `?ref=`).
2. Look it up with the MCP tools above, for that version or the latest.
3. Answer from the docs, quoting argument names exactly. Note which arguments force replacement.

## Write or change code

1. Read the existing layout and naming; match it.
2. Look up every resource and module through the MCP. Pin provider and module versions to what the MCP reports (`~>` for providers, exact or `?ref=` tag for modules). Prefer an AVM or `terraform-aws-modules` module over raw resources when one fits.
3. Make the smallest change. Don't add variables, outputs or abstractions nobody asked for.
4. Check: `terraform fmt -check`, `terraform init -backend=false`, `terraform validate`, `tflint` (if installed). Show the output.
5. Tell the user which plan to run to see the real effect.

## Review a plan or PR

Read `plan.txt` or the diff. Flag, most serious first:

- Destroys and replacements (`-/+`, `must be replaced`); name the force-new attribute that causes each.
- Drift: changes nobody wrote in the diff.
- Sensitive changes: secrets, keys, certificates, state of data stores (databases, storage, key vaults, S3).
- IAM / RBAC widening (`*` actions, Owner, Contributor, AdministratorAccess), public network exposure (`0.0.0.0/0`, public access enabled), disabled encryption or logging.
- Unpinned or moved module refs (`?ref=` to a branch).

End with a verdict: safe to apply / needs changes / needs a question answered.

## Upgrade providers or modules

1. Find the current and target versions (MCP latest-version tools). Record the current pin or `?ref=` and note the `.terraform.lock.hcl` state (present, which versions) before changing anything.
2. Find what changed:
   - Provider: read the upgrade guides (`search_providers` with `provider_document_type=guides`).
   - Module: change ONLY the version pin (or `?ref=`) to the target first, then run `terraform init -backend=false`, so `.terraform/modules/` holds the target version. Read the target module's `CHANGELOG.md` (or release notes) there for the entries between current and target. For git-sourced modules, `git ls-remote --tags` confirms the target tag exists.
   - Also compare the inputs and outputs of both versions with `get_module_details`.
   - No changelog? Say so, and rely on the input/output comparison.
3. List the breaking changes that touch this code, before editing anything else.
4. Change the code; use `moved` blocks instead of recreating resources.
5. `terraform validate`, then hand the user the plan commands and review the result.

Upgrade stops before the code changes (the user stops it, or a blocker)? Put the pin or `?ref=` back to the recorded value yourself, and tell the user `.terraform/` and `.terraform.lock.hcl` may have changed and are theirs to restore. Don't use git to restore files.

## Delegation

Hand Terraform work to the `terraform` agent, with the files, the goal and these safety rules in the brief. It reports what it changed or found, the commands it ran with output, plan commands for the user, and open questions.
