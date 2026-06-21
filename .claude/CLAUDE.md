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
- For TypeScript: verify `tsc --noEmit` passes (no `TS2741`/type-mismatch errors) before committing — prefer the project's `typecheck`/`build` script. When adding a field to a type/interface, update every companion object and JSON schema fixture (e.g. `*.v1.json`) in the same change so the compile stays green.
- Before modifying dependencies (Gradle/npm), verify compatibility with current project versions. Do not move runtime dependencies to compileOnly without confirming they are not needed at build/augmentation time.
- Before claiming a dependency or version doesn't exist, verify against the actual registry. A 404/failed install for `@fullbay/*` packages is almost always a stale CodeArtifact/SSO token, not a missing package — refresh the token and retry first.
- Never suggest skipping or bypassing pre-commit hooks (`--no-verify`) to get around a failing install or check. Fix the underlying cause.

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

### AWS Commands
- Before running any AWS CLI command against an environment, confirm the active SSO profile/account matches the intended target (`aws sts get-caller-identity` or check `AWS_PROFILE`, e.g. fb-demo-us-prod/Admin). Never assume the default profile is the right one.
- Confirm the SSO session isn't expired before starting a long AWS/Terraform task — re-authenticate proactively (`aws sso login --profile <p>`) rather than discovering the expiry mid-run on a rejected call or blocked dependency install.

### Debugging
- When diagnosing 401s/auth failures or other distributed-system errors, consider consumer-side causes (cold-start JWKS fetch blocking, concurrency races, client clock skew) in addition to the issuer/server side before settling on a root cause.

### Terraform Conventions
- Never use `count = 0` together with `moved` blocks on the same resource — this causes plan errors.
- Do not change DMS `MaxFullLoadSubTasks` above the current value without explicit approval (known OOM risk).
- Always run `terraform validate` and `terraform plan` before suggesting a commit.
- Do not modify IAM roles tagged with governance policies — flag for human approval instead of attempting the change.
- EventBridge **event-bus** targets reject `retry_policy` and `dead_letter_config` at the `PutTargets` API — omit those blocks for bus-to-bus routing (they're valid only on non-bus targets like Lambda/SQS).
- Before validating target/permission blocks against AWS, pull the latest state instead of trusting a stale local clone — the API-accepted shape drifts, and a stale clone will generate blocks the live API rejects.

### Descope FGA / Authorization Schemas
- Validate FGA/ReBAC DSL against the Descope console before considering a schema change done — do not assume the generated syntax is accepted.
- Common DSL syntax errors to avoid: no bare relation names on the RHS of a relation definition (qualify them), and no `//` comments in the DSL (the parser rejects them).
- When managing FGA in Terraform, translate the ReBAC requirements into DSL and iterate through console validation rather than trusting a one-shot conversion.

### Spec-Driven Implementation
- When implementing from a spec/plan file, read the entire spec first and present a summary plan before making code changes. Make reasonable assumptions and note them rather than asking clarifying questions interactively.

### Premise Verification
- Before drafting any plan that names a service, file, library version, or commit SHA you don't already know exists in this repo, run `/verify-premise` (or invoke the `premise-verifier` agent directly). If the referenced target is not actually present or current, stop and report — do not build a plan against a phantom target.
- Mandatory for: cross-service/cross-repo features, "look at how X uses Y" exploration that quotes a specific symbol, integration plans referencing a service the current repo has no obvious dependency on, and any task quoting a published library version or commit SHA.
- Optional but encouraged: same check inside `/build-from-file` when reading a spec that references external services.

## Deployment Workflow

- Standard end-to-end flow: implement → tests pass → self-review (`/review`) → commit with git notes → push → open PR → address review → ship through dev/stage/prod/demo via Port.io (`/shipit`).
- **Port.io cache flicker**: action runs can oscillate between IN_PROGRESS and SUCCESS during polling. Poll the same state 2-3 times before reporting a final terminal state.
- **Stale SHAs in deploys**: before triggering a deploy or terraform apply, confirm the target entity's `short_sha` matches the expected commit on origin. If misaligned, wait 30s and re-fetch — do not fire the action against a stale entity.
- **Approval gate polling**: treat `approval_status = null` as pending, not failed. Retry up to 5x with 20s backoff before assuming the gate is broken.

### New Lambda Repos
- Every new Node/TypeScript Lambda project must include a `.npmrc` configured for the @fullbay AWS CodeArtifact registry before the first PR is opened. Missing this file is the single most common CI failure pattern (`npm install` returns 404 for `@fullbay/*` packages and the pipeline fails at the install step).
- Any build/scaffold skill that creates a new Node-based Lambda must either generate the `.npmrc` or refuse to commit until one exists in the project root.

## Communication Style

- When the user asks for an investigation, write-up, or findings document, document the findings — do not attempt fixes unless explicitly asked.
- Avoid interactive clarifying questions during plan-writing phases; make a reasonable assumption and note it instead.

### Output Token Discipline

- Keep chat responses concise. Avoid restating large file contents or full diffs back to the user — they can read the files.
- Summarize work using bullet lists with `file:line` references, not pasted code blocks.
- For multi-file refactors, show only key snippets in the final summary, not every change.
- For deploy/pipeline polling, report state changes as a compact table — not narrative prose.
- This applies to user-visible output. Internal reasoning depth should remain high per the Thinking Depth section.
- For any single output that would exceed roughly 150 lines or include large code/diff/log blocks (review findings, migration plans, scraped log dumps, multi-file refactor diffs): write the full content to `~/.claude/scratch/<repo-basename>/<topic>-<ISO8601>.md` (`mkdir -p` on demand) and post only a 3-bullet summary in chat with the path. Hard output-token caps have killed prior sessions mid-task; the scratch file is the durable artifact, chat is the index. Applies especially to reviewer output, deployment plans, and long log analyses.

## Code Quality
- Prefer correct, complete implementations over minimal ones.
- Use appropriate data structures and algorithms — don't brute-force what has a known better solution.
- When fixing a bug, fix the root cause, not the symptom.
- If something I asked for requires error handling or validation to work reliably, include it without asking.

### Code Editing Conventions
- Never use bulk `sed`/regex edits for code changes. Make targeted, type-aware edits (Edit tool or LSP-assisted) instead — bulk text substitution has injected bugs like `, null` into `Collections.emptyList()` and enum/string mismatches.
- After any multi-file change, run the build (and tests where fast) before moving on, so mechanical errors surface immediately rather than at commit time.

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
- **WebSearch / WebFetch for unfamiliar territory**: when debugging an error message you don't recognize, working with an unfamiliar library API, or looking up AWS service behavior, use WebSearch followed by WebFetch on the most authoritative result. Prefer official docs over Stack Overflow. The `/docs <topic>` skill wraps this pattern.

### Thinking Depth

When working on tasks that require complex problem-solving, always apply the highest **level of thinking depth**.

When thinking is shallow, the model outputs to the cheapest action available. We don't want that. We don't mind consuming more tokens if it means a better output. So always apply the highest level of thinking depth.

Never reason from assumptions, always reason from the actual data. You need to read and understand the actual code, publication or documentation in order to make informed decisions. Don't rely on assumptions or guesses, as they can lead to mistakes and misunderstandings.
