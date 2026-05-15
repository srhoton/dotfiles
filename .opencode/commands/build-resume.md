---
description: Resume a previously started SDLC build by reading the existing sdlc-plan.md and continuing from the current phase
agent: routing-agent
---

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
2. **If in Implementation phase**: Skip approved components, retry failed (reset count), continue with pending
3. **If in Review phase**: Continue review loops for the current component
4. **If in Commit phase**: Skip already-created commits, continue with remaining

**Important Resume Rules**:
- Do NOT re-implement components already marked "Approved"
- Do NOT re-run reviews for components that have passed
- DO update plan with "[RESUMED]" notation
- DO reset retry counters for failed components

$ARGUMENTS

---

Wait for the routing-agent to complete and report back with the results.
