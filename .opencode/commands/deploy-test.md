---
description: Test a deployed resource using the appropriate auth method (AppSync API key or fb-jwt JWT)
---

Test the deployed resource: $ARGUMENTS

Rules:
1. Get the AppSync API key using `aws appsync list-api-keys --api-id <id>` — do NOT try indirect approaches
2. Test ONLY the specific mutation/query/endpoint — NEVER attempt login flows
3. Authentication: AppSync → API key auth; *-svc REST → `fb-jwt` JWT Bearer
4. Use `--cli-read-timeout 300` for Lambda invocations
5. On failure, check CloudWatch logs: `aws logs tail /aws/lambda/<function-name> --since 5m`
6. If testing CRUD, test in order: Create → Read → Update → List → Delete
7. Always use proper shell quoting
