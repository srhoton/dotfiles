Applies to: `**/*fga*`, `**/*.dsl`, `**/*descope*`, `**/*fga*/**`, `**/*descope*/**`

# Descope FGA / Authorization Schemas
- Validate FGA/ReBAC DSL against the Descope console before considering a schema change done — do not assume the generated syntax is accepted.
- Common DSL syntax errors to avoid: no bare relation names on the RHS of a relation definition (qualify them), and no `//` comments in the DSL (the parser rejects them).
- When managing FGA in Terraform, translate the ReBAC requirements into DSL and iterate through console validation rather than trusting a one-shot conversion.
