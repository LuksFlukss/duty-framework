---
trigger: glob
globs: "*.tf, *.tfvars"
description: Terraform files (duty-terraform)
---

Working with Terraform: load the `terraform` skill (duty-terraform) first and delegate to the `terraform` agent. Never run `terraform plan`, a normal `terraform init`, `terraform init -upgrade` (any form), apply, destroy, import, any `terraform state` command, taint or workspace changes; give the user the plan commands and wait.
