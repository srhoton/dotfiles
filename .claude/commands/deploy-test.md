Test the deployed resource: $ARGUMENTS

Rules:
1. Get the AppSync API key using `aws appsync list-api-keys --api-id <id>` — do NOT
   try indirect approaches (Terraform state, env vars, etc.)
2. Test ONLY the specific mutation/query/endpoint named above — NEVER attempt
   login/authentication flows unless explicitly asked
3. Use direct API key auth for AppSync, or JWT from ~/git/tmp/passbf.json if instructed
4. Use `--cli-read-timeout 300` for any Lambda invocations or long-running operations
5. On failure, immediately check CloudWatch logs:
   `aws logs tail /aws/lambda/<function-name> --since 5m`
6. Report: status code, response body, any errors found in logs
7. If testing CRUD operations, test in order: Create → Read → Update → List → Delete
8. Always use proper shell quoting — no smart/curly quotes in curl commands
9. When comparing against expected behavior, check the existing codebase for reference
   implementations before assuming what the correct behavior should be
