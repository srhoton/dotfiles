Send a message to a Claude session running in another repo via the micro-status-mcp server.

`$ARGUMENTS` is pipe-separated: `<to-repo> | <subject> | <body>`.

- `<to-repo>` is the basename of the recipient repo's working directory (e.g., `usr-contact-svc`, `architecture-decisions`).
- `<subject>` is a short one-line summary used in the receiving Claude's notification.
- `<body>` is the actual message. Include concrete file paths with `path:line` references, function/symbol names, and what you want the recipient to do (investigate, implement, review, etc.).

Parse the arguments by splitting on ` | ` (pipe surrounded by spaces). Trim whitespace from each part.

Then call the `post_message` tool from the `micro-status` MCP server with:

- `from`: the basename of the **current** working directory (the sender). Compute it from `$PWD`.
- `to`: the `<to-repo>` parsed above.
- `subject`: the `<subject>` parsed above.
- `body`: the `<body>` parsed above (preserved verbatim, multi-line OK).

The tool returns `{id, notified, notify_error?}`. If `notified=true`, the recipient's tmux pane has been woken with `/inbox`. If `notified=false`, either the recipient isn't registered or their pane is gone — the message still sits in the recipient's inbox until they run `/inbox`. Include the returned `id` and `notified` flag in your response.

If `$ARGUMENTS` is empty or doesn't contain at least two ` | ` separators, ask the user for the missing pieces before posting.

If the MCP tool call fails because the server is unreachable, tell the user to start it with `micro-status-mcp serve` (typically in a dedicated tmux pane) — do not fall back to writing files anywhere.
