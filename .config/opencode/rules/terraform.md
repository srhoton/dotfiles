Applies to: `**/*.tf`, `**/*.tfvars`, `**/*.tftest.hcl`, `**/.tflint.hcl`

# Terraform Rules

Only non-obvious, shop-specific decisions. See also the Terraform Conventions section at the end of this file, which carries the hard-won operational rules (`count = 0` + `moved` blocks, DMS `MaxFullLoadSubTasks`, EventBridge bus targets rejecting `retry_policy`).

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

## Terraform Conventions
- Never use `count = 0` together with `moved` blocks on the same resource — this causes plan errors.
- Do not change DMS `MaxFullLoadSubTasks` above the current value without explicit approval (known OOM risk).
- Always run `terraform validate` and `terraform plan` before suggesting a commit.
- Do not modify IAM roles tagged with governance policies — flag for human approval instead of attempting the change.
- EventBridge **event-bus** targets reject `retry_policy` and `dead_letter_config` at the `PutTargets` API — omit those blocks for bus-to-bus routing (they're valid only on non-bus targets like Lambda/SQS).
- Before validating target/permission blocks against AWS, pull the latest state instead of trusting a stale local clone — the API-accepted shape drifts, and a stale clone will generate blocks the live API rejects.
