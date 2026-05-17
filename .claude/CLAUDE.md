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
- For multiline PR bodies, prefer `gh pr create --body-file <tmpfile>` over inline heredocs. Heredocs containing backticks corrupt PR content.
- Same rule applies to multiline commit messages: write to a tempfile and use `git commit -F <tmpfile>` rather than `-m "$(cat <<EOF ...`.

### Git State Verification
- Before claiming a file or commit doesn't exist, run `git fetch origin && git log origin/<branch> --oneline -20` to confirm the local clone is current. Local clones drift.
- When asked about a specific commit SHA, check if it's a squash-merge of a PR (`git log --format='%s' -1 <sha>` — look for a `(#NN)` suffix) before treating it as standalone work.
- If a user pastes a GitHub URL that disagrees with your local view, trust the URL and `git fetch` to reconcile — do not assume the user is mistaken.

### Environment Configuration
- Always use the established IDP config library with flat UPPER_SNAKE_CASE keys. Do not create custom YAML config readers or use camelCase/nested YAML structures.

### Terraform Conventions
- Never use `count = 0` together with `moved` blocks on the same resource — this causes plan errors.
- Do not change DMS `MaxFullLoadSubTasks` above the current value without explicit approval (known OOM risk).
- Always run `terraform validate` and `terraform plan` before suggesting a commit.
- Do not modify IAM roles tagged with governance policies — flag for human approval instead of attempting the change.

### Spec-Driven Implementation
- When implementing from a spec/plan file, read the entire spec first and present a summary plan before making code changes. Make reasonable assumptions and note them rather than asking clarifying questions interactively.

## Deployment Workflow

- Standard end-to-end flow: implement → tests pass → self-review (`/review`) → commit with git notes → push → open PR → address review → ship through dev/stage/prod/demo via Port.io (`/shipit`).
- **Port.io cache flicker**: action runs can oscillate between IN_PROGRESS and SUCCESS during polling. Poll the same state 2-3 times before reporting a final terminal state.
- **Stale SHAs in deploys**: before triggering a deploy or terraform apply, confirm the target entity's `short_sha` matches the expected commit on origin. If misaligned, wait 30s and re-fetch — do not fire the action against a stale entity.
- **Approval gate polling**: treat `approval_status = null` as pending, not failed. Retry up to 5x with 20s backoff before assuming the gate is broken.

## Communication Style

- When the user asks for an investigation, write-up, or findings document, document the findings — do not attempt fixes unless explicitly asked.
- Avoid interactive clarifying questions during plan-writing phases; make a reasonable assumption and note it instead.

### Output Token Discipline

- Keep chat responses concise. Avoid restating large file contents or full diffs back to the user — they can read the files.
- Summarize work using bullet lists with `file:line` references, not pasted code blocks.
- For multi-file refactors, show only key snippets in the final summary, not every change.
- For deploy/pipeline polling, report state changes as a compact table — not narrative prose.
- This applies to user-visible output. Internal reasoning depth should remain high per the Thinking Depth section.

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
- **LSP-first for symbol-level questions**: when working in a file type with an active LSP (Java via jdtls, TypeScript via typescript-lsp, Python via pyright), prefer LSP capabilities — find-references, go-to-definition, workspace-symbols, diagnostics — over grep + build cycles. LSPs distinguish overloads, inheritance, and imported vs local symbols where grep can't. Keep grep for text/comment/config searches and for languages without an active LSP (Terraform, shell, YAML).

### Thinking Depth

When working on tasks that require complex problem-solving, always apply the highest **level of thinking depth**.

When thinking is shallow, the model outputs to the cheapest action available. We don't want that. We don't mind consuming more tokens if it means a better output. So always apply the highest level of thinking depth.

Never reason from assumptions, always reason from the actual data. You need to read and understand the actual code, publication or documentation in order to make informed decisions. Don't rely on assumptions or guesses, as they can lead to mistakes and misunderstandings.
