Add environment configuration for: $ARGUMENTS

Follow these steps exactly:

## Step 1: Discover Existing Patterns

Before making any changes, search the codebase for existing environment configurations:

1. Find all config files: `runtime-config.yml`, `*.tfvars`, `*.tf`, TypeScript environment switches
2. Identify which environments already exist (e.g., qa, staging, prod, demo)
3. Show 2-3 examples of existing environment config entries from this project

**CRITICAL:** All config keys MUST use flat UPPER_SNAKE_CASE format matching the IDP config library. Do NOT use camelCase, nested YAML structures, or custom YAML config readers.

## Step 2: Scaffold Configuration

Replicate the exact structure of existing environments for the new one:

1. **Runtime config** (runtime-config.yml or similar): Add entries matching existing format exactly
2. **Terraform tfvars**: Create or update environment-specific tfvars files
3. **TypeScript environment switches**: Update any environment type definitions or switch statements
4. **CDK/Infra definitions**: Update any infrastructure definitions that reference environments

For each file modified, show the existing pattern you are following.

## Step 3: Validate

1. Grep the codebase for any hardcoded references to other environments that should include the new one
2. Verify no camelCase or nested YAML structures were introduced
3. Run `terraform validate` if Terraform files were changed
4. Run the project's test suite to verify nothing is broken

## Step 4: Summary

Report what was added, which files were modified, and which existing environment was used as the template pattern.
