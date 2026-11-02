Validate all CRUD operations are available and troubleshoot any issues.

For JWT-authenticated *-svc services, use `fb-jwt` to obtain a token (it auto-detects the audience from the current directory). Use the openapi spec in the openapi directory to determine the available endpoints.

Example: `curl -H "Authorization: Bearer $(fb-jwt)" https://<service-name>.lb.fb/<path>`
