Verify the premise of the following feature request / spec / claim BEFORE drafting any implementation plan:

$ARGUMENTS

Dispatch the `premise-verifier` subagent via the Task tool. Provide it with the full text above as the claim set to verify, plus the current working directory as context.

When the verifier returns its report:

1. Display the structured report verbatim (CONFIRMED / REFUTED / AMBIGUOUS).
2. If the verdict is **STOP — premise refuted**:
   - Display a one-line summary of which claims were refuted.
   - Recommend the user revise the premise before continuing.
   - Do NOT proceed to drafting an implementation plan.
3. If the verdict is **PROCEED**:
   - Note the verification passed.
   - Wait for the user's next instruction (do not auto-proceed to implementation unless they ask).

Keep output concise. The verifier's report is the primary deliverable.
