Run a test-first bug hunt for the issue described in `$ARGUMENTS`. `$ARGUMENTS` may be a free-form description, a Linear/Jira ticket reference, or a path to a bug report file.

**Critical rule: do not propose a fix until a failing test exists that fails for the right reason.** This skill exists because past sessions shipped speculative fixes when an early hypothesis went sideways; the failing test is the gate that forces evidence-based work.

Process:

1. **Evidence first — no hypotheses yet.**
   - Read the bug description and identify the suspected component(s).
   - Pull concrete evidence before guessing at the cause:
     - Logs: use the `awslabs.cloudwatch-mcp-server` MCP tools (`describe_log_groups`, `execute_log_insights_query`) if AWS Lambda or CloudWatch is involved.
     - Recent changes: `git log --oneline -20 -- <suspected paths>` and `gh pr list --state merged --search "<area>"` for recent PRs touching the area.
     - Code: read the actual implementation, do not infer from names.
   - State the evidence in one paragraph before forming a hypothesis. If you cannot find evidence, say so — do not invent it.

2. **Reproduce, then write a failing test.**
   - Identify the smallest test that would assert on the buggy behavior. Prefer the existing test framework in the repo (JUnit, Vitest, pytest, etc.) — do not introduce a new one.
   - The test must assert on the actual buggy output, not on the absence of output. If the bug is "returns null when it should return X", the test asserts `result == X` and fails because `result == null`.
   - Run the test and confirm it fails. Quote the failure message verbatim in your response.
   - **If the test passes immediately, your hypothesis is wrong.** Re-investigate before continuing.

3. **Implement the fix.**
   - Now form the root-cause hypothesis based on evidence + failing test.
   - Make the minimum change that turns the failing test green.
   - Re-run the test (now passes) AND the full surrounding suite (no regressions).
   - If the full suite has unrelated pre-existing failures, document them; do not chase them in this skill.

4. **Write the root-cause document.**
   - Write a short markdown file at `~/.claude/scratch/$(basename "$PWD")/bughunt-$(date -u +%Y-%m-%dT%H-%M-%SZ).md` with:
     - **Symptom**: what was observed.
     - **Evidence**: log lines, code paths, commit SHAs that led you to the cause.
     - **Root cause**: one paragraph.
     - **Fix**: file:line of the change and a one-line summary.
     - **Regression test**: file:line of the new test.
     - **Confidence**: high / medium / low + reason.
   - `mkdir -p` the directory if it doesn't exist.

5. **Surface in chat.**
   - 3-bullet summary: symptom, root cause, fix path.
   - Path to the scratch file.
   - Do not paste the full writeup or the diff inline — the file is the durable artifact.

Defaults / refusals:
- If the user asks you to commit a fix without step 2 having produced a failing test, refuse and explain why.
- If evidence-gathering surfaces that the bug is in a different repo than the current one, stop and report — do not chase it cross-repo without explicit instruction (`/refresh-other` + a follow-up bughunt in that repo is the right pattern).
- If the CloudWatch MCP tools aren't available, fall back to asking the user for relevant log excerpts rather than guessing.
