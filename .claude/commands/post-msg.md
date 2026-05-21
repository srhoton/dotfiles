Send a message to a Claude session running in another repo via the agent mailbox.

`$ARGUMENTS` is pipe-separated: `<to-repo> | <subject> | <body>`.

- `<to-repo>` is the basename of the recipient repo's working directory (e.g., `usr-contact-svc`, `architecture-decisions`).
- `<subject>` is a short one-line summary used in the receiving Claude's notification.
- `<body>` is the actual message. Include concrete file paths with `path:line` references, function/symbol names, and what you want the recipient to do (investigate, implement, review, etc.).

Parse the arguments by splitting on ` | ` (pipe surrounded by spaces). Trim whitespace from each part. Then invoke:

```bash
~/.claude/bin/agent-msg post "<to-repo>" "<subject>" "<body>"
```

Use a heredoc for the body if it contains quotes, backticks, or multiple lines:

```bash
~/.claude/bin/agent-msg post "<to-repo>" "<subject>" - <<'EOF'
<body>
EOF
```

The command prints the path of the message file it wrote — include that in your response so the user can find it. If the recipient's tmux pane is registered (auto-registers on Claude session start when run in tmux), the message will also be typed into their prompt automatically; otherwise it sits in their inbox until they run `/inbox`.

If `$ARGUMENTS` is empty or doesn't contain at least two ` | ` separators, ask the user for the missing pieces before posting.
