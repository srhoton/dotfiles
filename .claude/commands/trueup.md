---
description: "Commit your work with prompts in git notes, push it, and create a PR with an accurate description."
disable-model-invocation: true
---
ok. Please commit your work, add prompts in this session to the commit via git notes, push it, and using your github cli tool, create a PR. Make sure the README for the PR accurately describes the changes made from a full diff from the branch you are merging into.

Do the commit, notes and push with `~/.claude/bin/commit-notes` instead of hand-written git commands. Write the commit message and the session prompts (the note) to two tempfiles, then run `~/.claude/bin/commit-notes -m <msgfile> -n <notesfile> --add <each path you changed> --push`. It stages only the paths you list, shows the staged stat and refuses if nothing is staged or you are on the default branch, runs `git commit -F` and `git notes add -F`, never skips hooks, and pushes (`-u origin HEAD` the first time). Use `-N` first if unsure what it will do. Read what it prints, including any untracked-file warning.

This command is the one place the risk score goes into a PR body (`/deliver` follows it). Before `gh pr create` or `gh pr edit`, score the change and put the block in the body's **Test plan**:

- If this session ran review-fanout on the current changes (`/review`, `/deliver`), run `~/.claude/bin/risk-score --fanout <last review round's output file> --md`. Always the LAST round's file, since the output has no resolved flag and an earlier round's findings may already be fixed.
- Otherwise, or if that output file is gone, run `~/.claude/bin/risk-score --md` and keep its `(pre-review)` label, adding "no fan-out this session" when that is the reason.

`--md` prints `**Risk N/5** (pre-review|final)`, a `hot N | complexity N | config N | review gap N` line, then up to three `- <driver>` bullets. Paste it into the body wrapped in `<!-- risk-score -->` and `<!-- /risk-score -->` comment lines, so one span is always replaceable. If the PR already exists, read its body with `gh pr view <N> --json body,state`, replace that marked span with the new block (an older block with no markers is the `**Risk N/5**` line through the bullets that follow it), and write it back with `gh pr edit <N> --body-file <tmpfile>`. Never leave two risk blocks in one body.

Before opening the PR, check the PR base with the printed `base=` (when a PR already exists; otherwise pass `--base <default branch>` explicitly) and that it is the default branch unless I asked for stacking. Create the PR with `gh pr create --body-file <tmpfile>`, never an inline `--body` or `@path`.
