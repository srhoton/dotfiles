Use the Task tool to dispatch to the `routing-agent` subagent with the following project request:

---

$ARGUMENTS

---

The routing-agent will orchestrate the complete SDLC flow:
1. Create a formal plan document (sdlc-plan.md)
2. Ask clarifying questions if needed
3. Verify you're on a feature branch (not main/master)
4. Dispatch to appropriate language subagents for implementation
5. Run functional and code quality reviews with retry loops
6. Commit each component with git notes
7. Push and create a PR

Wait for the routing-agent to complete and report back with the results.
