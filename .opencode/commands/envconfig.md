---
description: Add environment configuration following existing patterns with flat UPPER_SNAKE_CASE keys
---

Add environment configuration for: $ARGUMENTS

## Step 1: Discover Existing Patterns

Before making any changes, search the codebase for existing environment configurations:
1. Find all config files: runtime-config.yml, *.tfvars, *.tf, TypeScript environment switches
2. Identify existing environments (qa, staging, prod, demo)
3. Show 2-3 examples of existing entries from this project

**CRITICAL:** All config keys MUST use flat UPPER_SNAKE_CASE format. No camelCase, nested YAML, or custom YAML readers.

## Step 2: Scaffold Configuration

Replicate the exact structure of existing environments for the new one.

## Step 3: Validate
- Check for hardcoded env references that should include the new one
- Verify no camelCase/nested YAML
- Run terraform validate and test suite

## Step 4: Summary
Report what was added, files modified, and template environment used.
