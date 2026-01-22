Resume a previously started SDLC build process by reading the existing plan document.

First, read the plan document at `./sdlc-plan.md` to understand:
1. The original project request
2. Current phase and status
3. Which components have been completed
4. Which components are pending or failed
5. Any errors that were logged

Then use the Task tool to dispatch to the `routing-agent` subagent with the following instructions:

---

**RESUME MODE**: Continue from existing plan at ./sdlc-plan.md

Read the plan document and resume execution from where it left off:

1. **If in Planning phase**: Complete the plan and proceed to Implementation
2. **If in Implementation phase**:
   - Skip components marked as "Approved"
   - Retry components marked as "Failed" (reset retry count)
   - Continue with components marked as "Pending" or "In Progress"
3. **If in Review phase**:
   - Continue review loops for the current component (functional → quality → ADR)
   - If a component was mid-review, restart that component's review from functional review
4. **If in Commit phase**:
   - Skip commits that have already been created
   - Continue with remaining commits, git notes, and PR creation

**Important Resume Rules**:
- Do NOT re-implement components that are already marked "Approved"
- Do NOT re-run reviews for components that have passed both reviews
- DO update the plan document with "[RESUMED]" notation and timestamp
- DO reset retry counters for failed components (give them another 3 attempts)
- If the plan shows "Failed" status, ask the user if they want to retry or need to provide additional guidance

$ARGUMENTS

---

Wait for the routing-agent to complete and report back with the results.
