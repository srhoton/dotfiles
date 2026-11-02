# Archived commands, agents and scripts

These had **no use in any transcript from 2026-07-18 to 2026-11-02** (about 15 weeks of typed `/commands`, Skill-tool calls, Agent dispatches, workflow agents and `bin/` calls), so they were moved here on 2026-11-02. Claude Code doesn't load anything under `archive/`, so they no longer appear in the skill listing or the agent list.

To restore one, move it back. For example: `git mv .claude/archive/commands/fleet.md .claude/commands/`. Then copy it into `~/.claude/commands/` if the live config isn't synced from this repo.

## commands/
| Group | Commands |
|---|---|
| Legacy build pipeline | build, build-from-file, build-resume (they drive `routing-agent`) |
| Single-reviewer shortcuts (superseded by `/reviewit` and the review-fanout workflow) | reviewitadr, reviewitfunc, reviewitlocal, reviewitperf, reviewitrob, reviewitsec, reviewitzach |
| Deploy variants (`/shipit` stays) | fleet, ship-when-clean, shipit-batch, checkdeploy, deploy-test, validate-fix, validatewithjwt |
| Port.io reports | secscan, stackhealth |
| Agent mailbox | inbox, post-msg, refresh-other |
| One-off scaffolds and prompts | bughunt, docs, envconfig, java_service, moveittofb, terraformitup, vlt, vlttf, stale-prs (the command only; `bin/stale-prs` stays, because the `pr-stale-check` hook uses it) |

## agents/
- routing-agent and its language agents: golang-agent, java-quarkus-agent, python-agent, react-agent, terraform-agent, typescript-agent. The last dispatch was typescript-agent on 2026-09-24.
- lambda-performance-reviewer, security-reviewer, zach-style-code-reviewer: never dispatched.

## bin/
- `agent-msg`: the mailbox CLI.
  - The `micro-status` MCP server was removed from `~/.claude.json`, and its registration block from `hooks/session-env-setup.sh`.
  - The git-ignored `bin/micro-status-mcp` binary (18 MB) can be deleted.
  - To bring the mailbox back, restore this file, the three mailbox commands and the hook block, then `claude mcp add micro-status --transport http http://127.0.0.1:7878/mcp -s user`.
