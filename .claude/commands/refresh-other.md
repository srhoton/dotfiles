Ask the Claude session in another repo to fast-forward that repo's checkout to its remote default branch (so this session can read fresh code there).

`$ARGUMENTS` is `<repo-name>` — the basename of the target repo's working directory.

If `$ARGUMENTS` is empty, ask the user which repo to refresh and stop.

Steps:

1. Determine the sender: `from = basename "$PWD"`.

2. Call `mcp__micro-status__list_sessions` and confirm `<repo-name>` is in the returned list. If it isn't, tell the user "no Claude session is registered for `<repo-name>` — open Claude in that repo (inside tmux) first" and stop. Do not post a doomed message.

3. Call `mcp__micro-status__post_message` with:
   - `from`: the sender computed above.
   - `to`: `<repo-name>`.
   - `subject`: `refresh to default branch`
   - `body` (verbatim — this is the recipe the receiving Claude will follow):

     ```
     Refresh this checkout to the remote default branch.

     1. Run `git fetch origin --prune`.
     2. Determine the default branch:
        `default=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')`
     3. If `git status --porcelain` is non-empty, STOP. Do NOT stash.
        Post a reply via mcp__micro-status__post_message with:
          from = <this repo's basename>
          to   = <SENDER>
          subject = "refresh blocked — dirty tree"
          body    = the output of `git status --short`, plus a note that
                    the human in this pane needs to clean/commit first.
        Then tell the human in this pane what's dirty and wait for them.
     4. Otherwise: `git checkout "$default" && git pull --ff-only origin "$default"`.
     5. Capture the new HEAD: `sha=$(git rev-parse HEAD)`.
     6. Post a reply via mcp__micro-status__post_message with:
          from = <this repo's basename>
          to   = <SENDER>
          subject = "refresh complete"
          body    = "<default-branch> @ <sha>"
     ```

   Substitute `<SENDER>` with the sender computed in step 1 so the receiver knows where to reply.

4. The tool returns `{id, notified, notify_error?}`. Report both fields to the user. If `notified=true`, the recipient's pane has been woken with `/inbox` and will process the request on its next turn. If `notified=false`, the recipient will pick it up the next time someone runs `/inbox` in that session.

5. Do not block waiting for the reply. The user can run `/inbox` later to see the `refresh complete` or `refresh blocked` ack.

If the MCP tool call fails because the server is unreachable, tell the user to start it with `micro-status-mcp serve` (typically in a dedicated tmux pane).
