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

## Code Quality
- Prefer correct, complete implementations over minimal ones.
- Use appropriate data structures and algorithms — don't brute-force what has a known better solution.
- When fixing a bug, fix the root cause, not the symptom.
- If something I asked for requires error handling or validation to work reliably, include it without asking.

### Pattern Discovery
- Before making changes, search the codebase for existing examples of the pattern being implemented. Show 2-3 examples of how it is currently done, then follow the same conventions. Do not invent new patterns.

## Claude Code Behaviour Guidelines

- Avoid ownership-dodging behaviour: if you encounter an issue, take responsibility for it and work towards a solution instead of passing it on to someone else. Don't say things like "not caused by my changes" or say that it's "a pre-existing issue". Instead, acknowledge the problem and take initiative to fix it. Also, don't give up with excuses like "known limitation" and don't mark it for "future work".
- Avoid premature stopping: if you encounter a problem, don't stop at the first obstacle. Instead, keep pushing forward and find a way to overcome it. Don't say things like "good stopping point" or "natural checkpoint". Instead, keep going until you have a complete solution.
- Avoid permission-seeking behaviour: if you have the knowledge and capability to solve a problem, push through. Don't say things like "should I continue?" or "want me to keep going?". Instead, take initiative and act towards the solution.
- Do plan multi-step approaches before acting (plan which files to read and in what order, which tools to use, etc).
- Do recall and apply project-specific conventions from CLAUDE.md files.
- Do catch your own mistakes by applying reasoning loops and self-checks, and fix them before committing or asking for help.

### Use of tools

Adhere to the following guidelines when using tools:

- Always use a **Research-First approach**: Before using any tool, conduct thorough research to understand the context and requirements. This ensures that you use the most appropriate tool for the task at hand. Never use an Edit-First approach. You should prefer making surgical edits to the codebase instead of rewriting whole files or doing large, sweeping changes.
- Use **Reasoning Loops** very frequently. Don't be lazy and skip them. Reasoning loops are essential for ensuring the quality and accuracy of your work.

### Thinking Depth

When working on tasks that require complex problem-solving, always apply the highest **level of thinking depth**.

When thinking is shallow, the model outputs to the cheapest action available. We don't want that. We don't mind consuming more tokens if it means a better output. So always apply the highest level of thinking depth.

Never reason from assumptions, always reason from the actual data. You need to read and understand the actual code, publication or documentation in order to make informed decisions. Don't rely on assumptions or guesses, as they can lead to mistakes and misunderstandings.
