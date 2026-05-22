Check the agent mailbox for messages addressed to the current repo and process them.

Call the `list_messages` tool from the `micro-status` MCP server with:

- `repo`: the basename of the current working directory (`basename "$PWD"`).
- `include_read`: omit or set to `false`. Only unread messages should be processed.

If the response has an empty `messages` array, say "no messages" in one line and stop — do not invent work.

For each message in the response (`messages[]`), in order (oldest first; the list is already sorted):

1. Summarize the sender's request in one short sentence to the user, including the `from`, `subject`, and `id`.
2. Decide what to do based on the `body`:
   - If the message is purely informational, acknowledge it and move on.
   - If it suggests a code change, treat it as a feature/bug request and act on it the same way you would a direct user request — investigate the referenced files, implement the change, and report back.
   - If the request is unclear or would require a destructive action, ask the user before proceeding.
3. After you have handled the message (whether by acting on it or by acknowledging it), call the `mark_read` tool with the message's `id` so it does not appear in future `/inbox` runs.

If the MCP server is unreachable, tell the user to start it with `micro-status-mcp serve` — do not fall back to reading files from `~/.claude/agent-mailbox/`.
