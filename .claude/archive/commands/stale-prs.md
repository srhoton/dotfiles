List open PRs in the current repo that are being ignored — not yours, not drafts, and with no activity in more than N days.

`$ARGUMENTS` is an optional day threshold (default `3`). E.g. `/stale-prs` uses 3 days; `/stale-prs 7` uses 7.

Run the existing helper:

```bash
~/.claude/bin/stale-prs ${ARGUMENTS:-3}
```

Then:

- If it prints lines, surface them to the user verbatim under a short header like "Stale PRs in <repo> (no activity >Nd):". Each line is already formatted as `#<num> <title> — <age>d stale, @<author> — <url>`, sorted most-stale first.
- If it prints nothing, the exit was clean — tell the user there are no stale PRs (or that this isn't a GitHub repo / `gh` isn't authenticated, if that's the likely cause). Do not invent results.

This is the same query the `pr-stale-check.sh` PostToolUse hook runs automatically after `gh pr create`; this command just lets you check on demand without opening a PR.
