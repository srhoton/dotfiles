Get a JWT token using `fb-jwt` and validate all the CRUD operations work. The openapi spec for the endpoint is in the openapi directory.

Use `fb-jwt` to obtain the token (it auto-detects the audience from the current directory). Then test all CRUD operations defined in the openapi spec.

Example: `curl -H "Authorization: Bearer $(fb-jwt)" https://<service-name>.lb.fb/<path>`
