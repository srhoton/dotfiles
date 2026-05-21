Check the agent mailbox for messages addressed to the current repo and process them.

Run `~/.claude/bin/agent-msg list` to enumerate pending message files. If the output is `(empty)`, say so in one line and stop — do not invent work.

For each file shown:

1. Read it from `~/.claude/agent-mailbox/$(basename "$PWD")/inbox/<filename>`. The frontmatter (`from`, `to`, `subject`, `ts`) tells you who sent it and why.
2. Summarize the sender's request in one short sentence to the user.
3. Decide what to do:
   - If the message is purely informational, acknowledge and archive it.
   - If it suggests a code change, treat it as a feature/bug request and act on it the same way you would a user request — investigate the referenced files, implement the change, and report back.
   - If the request is unclear or would require destructive action, ask the user before proceeding.
4. After processing, archive the file:
   ```bash
   mkdir -p ~/.claude/agent-mailbox/$(basename "$PWD")/read
   mv ~/.claude/agent-mailbox/$(basename "$PWD")/inbox/<filename> ~/.claude/agent-mailbox/$(basename "$PWD")/read/
   ```

Process messages in filename order (timestamps sort lexicographically) so older messages are handled first.
