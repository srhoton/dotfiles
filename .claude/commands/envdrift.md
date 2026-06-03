Report environment SHA drift for a Port.io stack: compare the commit deployed in `dev` against `qa`, `stage`, `prod`, and `demo`, and flag anything that isn't in sync.

`$ARGUMENTS` is the stack name (e.g. `mig-start-mg-fun`). If empty, default to `basename "$PWD"` (the current repo). If you can't determine a stack, ask the user.

**This is read-only. Never trigger a deploy from this command.** Use the Port MCP for entity reads; use local git only for ancestry classification.

Procedure:

1. Using the Port MCP `list_entities` on the `stack_environment_status` blueprint, read these entities and their `short_sha` property:
   `<stack>-dev`, `<stack>-qa`, `<stack>-stage`, `<stack>-prod`, `<stack>-demo`.
   - If the Port MCP is unavailable, say so and stop (suggest the user reconnect it).
   - If `<stack>-dev` does not exist, report that `<stack>` doesn't appear to be a Port stack and stop.
   - For any other env entity that doesn't exist, note it as "absent" and skip it.

2. Capture `<stack>-dev`'s `short_sha` as the base (`DEV_SHA`).

3. Classify the other envs against dev with the local git helper. Pass only the envs that exist:
   ```bash
   ~/.claude/bin/sha-relation <DEV_SHA> qa:<qa_sha> stage:<stage_sha> prod:<prod_sha> demo:<demo_sha>
   ```
   Each output line is `<label>\t<sha>\t<RELATION>` where RELATION is one of `MATCHES`, `BEHIND`, `AHEAD`, `DIVERGED`, `UNKNOWN`.

4. Render a table:

   ```
   Env drift for <stack> (dev @ <DEV_SHA>):

   | Env   | short_sha | vs dev        |
   |-------|-----------|---------------|
   | dev   | <sha>     | (base)        |
   | qa    | <sha>     | BEHIND dev    |
   | stage | <sha>     | MATCHES       |
   | prod  | <sha>     | ⚠ AHEAD of dev |
   | demo  | <sha>     | UNKNOWN       |
   ```

5. Verdict line beneath the table:
   - All `MATCHES` → "✅ All environments in sync at `<DEV_SHA>`."
   - Some `BEHIND`, none ahead/diverged → "ℹ️ N env(s) behind dev — normal if you haven't shipped yet."
   - Any `AHEAD` or `DIVERGED` → loud flag, listing each: "⚠️ `<env>` is AHEAD of dev (running `<sha>` which dev does not contain) — dev is missing a commit that's live in `<env>`. Investigate before shipping."
   - Any `UNKNOWN` → note that git couldn't resolve that SHA locally (the clone may be behind or this isn't the matching repo); it couldn't be classified.

Keep the output compact — the table plus the verdict line, nothing more.
