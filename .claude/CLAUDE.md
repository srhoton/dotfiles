# Global Rules

## Language Rules
- Java coding rules @~/.claude/java_rules.md
- Terraform coding rules @~/.claude/terraform_rules.md
- Python coding rules @~/.claude/python_rules.md
- Golang coding rules @~/.claude/golang_rules.md
- Typescript coding rules @~/.claude/typescript_rules.md
- React coding rules @~/.claude/react_rules.md

## Workflow Rules

### Before Committing
- Always run the full test suite before committing. If tests fail, fix them before proceeding.
- For Java/Quarkus: run `./gradlew spotlessApply` before committing.
- Before modifying dependencies (Gradle/npm), verify compatibility with current project versions. Do not move runtime dependencies to compileOnly without confirming they are not needed at build/augmentation time.

### Pull Requests
- When creating PRs, check if a referenced PR number is still open. Never update a closed PR -- create a new one.

### Environment Configuration
- Always use the established IDP config library with flat UPPER_SNAKE_CASE keys. Do not create custom YAML config readers or use camelCase/nested YAML structures.

### Spec-Driven Implementation
- When implementing from a spec/plan file, read the entire spec first and present a summary plan before making code changes. Make reasonable assumptions and note them rather than asking clarifying questions interactively.

### Pattern Discovery
- Before making changes, search the codebase for existing examples of the pattern being implemented. Show 2-3 examples of how it is currently done, then follow the same conventions. Do not invent new patterns.
