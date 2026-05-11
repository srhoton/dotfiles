---
description: Validate a deployed resource and autonomously fix issues through diagnose-deploy-revalidate loop (max 5 iterations)
---

Validate the deployed resource and autonomously fix any issues: $ARGUMENTS

This command assumes the code has already been deployed via CI/CD (or locally).
Follow this validate-fix loop:

1. **Validate**: Test the deployed resource
   - AppSync: `aws appsync list-api-keys --api-id <id>`
   - REST: `fb-jwt <service-name>` for JWT Bearer auth
   - Test ONLY the specific operation, use `--cli-read-timeout 300`

2. **If validation passes**: Report success and stop.

3. **If validation fails**:
   a. Check CloudWatch logs: `aws logs tail /aws/lambda/<fn> --since 5m`
   b. Diagnose root cause
   c. Compare with reference implementations before fixing
   d. Apply fix, run tests, commit and push
   e. Wait for CI/CD deployment (Harness MCP, gh CLI, or terraform)
   f. Re-validate

4. **Repeat** (max 5 iterations)

5. **On final success**: Report summary of all fixes applied
