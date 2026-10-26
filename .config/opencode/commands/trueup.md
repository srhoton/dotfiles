---
description: "Commit your work with prompts in git notes, push it, and create a PR with an accurate description."
---
ok. Please commit your work, add prompts in this session to the commit via git notes, push it, and using your github cli tool, create a PR. Make sure the README for the PR accurately describes the changes made from a full diff from the branch you are merging into.

Do the commit, notes and push with `~/.claude/bin/commit-notes` instead of hand-written git commands. Write the commit message and the session prompts (the note) to two tempfiles, then run `~/.claude/bin/commit-notes -m <msgfile> -n <notesfile> --add <each path you changed> --push`. It stages only the paths you list, shows the staged stat and refuses if nothing is staged or you are on the default branch, runs `git commit -F` and `git notes add -F`, never skips hooks, and pushes (`-u origin HEAD` the first time). Use `-N` first if unsure what it will do. Read what it prints, including any untracked-file warning.

Before opening the PR, check the PR base with the printed `base=` (when a PR already exists; otherwise pass `--base <default branch>` explicitly) and that it is the default branch unless I asked for stacking. Create the PR with `gh pr create --body-file <tmpfile>`, never an inline `--body` or `@path`.
