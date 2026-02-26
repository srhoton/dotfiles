Validate the deployed resource and autonomously fix any issues: $ARGUMENTS

This command assumes the code has already been deployed via CI/CD (or locally).
Follow this validate-fix loop:

1. **Validate**: Test the deployed resource following deploy-test rules:
   - **For AppSync endpoints**: Get API key via `aws appsync list-api-keys --api-id <id>` — never indirect methods
   - **For *-svc REST endpoints (JWT-authenticated)**: Get a JWT via `fb-jwt <service-name>` and use as `Authorization: Bearer <token>`. If inside a *-svc repo, just run `fb-jwt` with no arguments to auto-detect the audience.
   - Test ONLY the specific operation — never login/authentication flows
   - Use `--cli-read-timeout 300` for Lambda invocations
   - Always use proper shell quoting — no smart/curly quotes

2. **If validation passes**: Report success and stop.

3. **If validation fails**:
   a. Check CloudWatch logs: `aws logs tail /aws/lambda/<fn> --since 5m`
   b. Diagnose root cause from the error and logs
   c. Compare with working reference implementations in the codebase before inventing fixes
   d. Apply the fix to the code
   e. Run local tests to verify the fix doesn't break anything
   f. Commit and push the fix
   g. **Wait for CI/CD deployment**:
      - Read `.claude/cicd.json` from the project root
      - **If provider is `harness`**: use Harness MCP to poll pipelines (list_executions → get_execution every 30s, max 15 min)
      - **If provider is `github-actions`**: use `gh` CLI to poll workflows (gh run list → gh run view every 30s, max 15 min)
      - **If provider is `terraform`**: run `terraform -chdir=<dir> apply -auto-approve`
      - **If no config exists**: Ask "Fix pushed. Is CI/CD deployment complete?" (wait for user confirmation)
      - On success: proceed to re-validate
      - On failure: report which pipeline/workflow failed with details and diagnose
   h. Re-validate from step 1

4. **Repeat** (max 5 iterations before stopping and reporting all attempts)

5. **On final success**: Report summary of all fixes applied across iterations

Constraints:
- Check existing patterns in the codebase before attempting novel fixes
- Use Terraform AWS provider v5 syntax only
- Match resolver/mutation names exactly to Lambda handler field names
- If testing CRUD operations, test in order: Create → Read → Update → List → Delete
- When comparing against expected behavior, check the existing codebase for reference
  implementations before assuming what the correct behavior should be
