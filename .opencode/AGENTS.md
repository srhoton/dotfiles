# Global Rules

## Language Rules

When working with specific languages, load the corresponding rules file:
- Java coding rules in .opencode/rules/java_rules.md
- Terraform coding rules in .opencode/rules/terraform_rules.md
- Python coding rules in .opencode/rules/python_rules.md
- Golang coding rules in .opencode/rules/golang_rules.md
- Typescript coding rules in .opencode/rules/typescript_rules.md
- React coding rules in .opencode/rules/react_rules.md

## Workflow Rules

### Before Committing
- Always run the full test suite before committing. If tests fail, fix them before proceeding.
- For Java/Quarkus: run `./gradlew spotlessApply` before committing.
- Before modifying dependencies (Gradle/npm), verify compatibility with current project versions. Do not move runtime dependencies to compileOnly without confirming they are not needed at build/augmentation time.

### Pull Requests
- When creating PRs, check if a referenced PR number is still open. Never update a closed PR -- create a new one.

### Environment Configuration
- Always use the established IDP config library with flat UPPER_SNAKE_CASE keys. Do not create custom YAML config readers or use camelCase/nested YAML structures.

### Terraform Conventions
- Never use `count = 0` together with `moved` blocks on the same resource — this causes plan errors.
- Do not change DMS `MaxFullLoadSubTasks` above the current value without explicit approval (known OOM risk).
- Always run `terraform validate` and `terraform plan` before suggesting a commit.
- Do not modify IAM roles tagged with governance policies — flag for human approval instead of attempting the change.

### Spec-Driven Implementation
- When implementing from a spec/plan file, read the entire spec first and present a summary plan before making code changes. Make reasonable assumptions and note them rather than asking clarifying questions interactively.

## Communication Style

- When the user asks for an investigation, write-up, or findings document, document the findings — do not attempt fixes unless explicitly asked.
- Avoid interactive clarifying questions during plan-writing phases; make a reasonable assumption and note it instead.

## Code Quality
- Prefer correct, complete implementations over minimal ones.
- Use appropriate data structures and algorithms — don't brute-force what has a known better solution.
- When fixing a bug, fix the root cause, not the symptom.
- If something I asked for requires error handling or validation to work reliably, include it without asking.

### Pattern Discovery
- Before making changes, search the codebase for existing examples of the pattern being implemented. Show 2-3 examples of how it is currently done, then follow the same conventions. Do not invent new patterns.

### Use of tools

Adhere to the following guidelines when using tools:

- Always use a **Research-First approach**: Before using any tool, conduct thorough research to understand the context and requirements. This ensures that you use the most appropriate tool for the task at hand. Never use an Edit-First approach. You should prefer making surgical edits to the codebase instead of rewriting whole files or doing large, sweeping changes.
- Use **Reasoning Loops** very frequently. Don't be lazy and skip them. Reasoning loops are essential for ensuring the quality and accuracy of your work.

### Thinking Depth

When working on tasks that require complex problem-solving, always apply the highest **level of thinking depth**.

Never reason from assumptions, always reason from the actual data. You need to read and understand the actual code, publication or documentation in order to make informed decisions. Don't rely on assumptions or guesses, as they can lead to mistakes and misunderstandings.
