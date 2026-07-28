# Terraform Rules

Only non-obvious, shop-specific decisions. See also the Terraform Conventions section in CLAUDE.md, which carries the hard-won operational rules (`count = 0` + `moved` blocks, DMS `MaxFullLoadSubTasks`, EventBridge bus targets rejecting `retry_policy`).

- **Naming**: `snake_case` for resources, variables, and outputs.
- **File structure**: `main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`, `versions.tf`.
- **Mandatory tags on every resource**: `Environment`, `Owner`, `Project`, `ManagedBy`. Apply via a shared `locals` map rather than repeating them.
- **Version pinning**: pin provider versions; `~>` for minor-version latitude, `>=` only for a true floor. Pin remote module versions explicitly — never copy a version from an example, look up the current one.
- **Conditional creation**: prefer `for_each` over `count` (stable addresses, no index churn on removal).
- **State**: separate state **per component/service**. Do not use workspaces for environment isolation — environments are separate state, matching the Port.io per-environment deploy model.
- **Formatting**: run `terraform fmt` before committing. Do not hand-sort resource arguments; `terraform fmt` owns layout.
- **Sensitive values**: pass via variables marked `sensitive = true`; never hardcode.
- **Linting/scanning**: `tflint` with a project `.tflint.hcl`; `checkov` or `tfsec` for security.
- **Testing**: native `terraform test` (Terraform 1.6+). Do not add terratest to new work.
