# dotfiles

## opencode

`.config/opencode/` is an opencode version of the Claude Code config in `.claude/`. It is generated, apart from `plugins/claude-hooks.js`. To change it, edit `.claude/` and regenerate; don't edit the generated files.

```bash
scripts/claude-to-opencode           # regenerate .config/opencode from .claude
scripts/claude-to-opencode --check   # exit 1 if .config/opencode is stale
scripts/install-opencode.sh          # symlink it into ~/.config/opencode
```

Tests:

```bash
python3 -m unittest discover -s scripts/tests
node --test scripts/tests/claude-hooks.test.mjs
```

### What maps to what

| Claude Code | opencode |
|---|---|
| `CLAUDE.md` | `AGENTS.md`: tool names rewritten, the model-tier rule dropped |
| `*_rules.md` | `rules/`, loaded through `instructions` in `opencode.json` |
| `agents/` | `agents/` as `mode: subagent`. A missing Write/Edit or Task tool becomes `edit: deny` or `task: deny`. |
| `commands/` | `commands/`, except the ones `settings.json` `skillOverrides` turns off |
| Enabled plugins' skills (AWS agent toolkit) | `skills/`, with the toolkit's Apache-2.0 `LICENSE` and `NOTICE` |
| MCP servers (`.claude.json`, `~/.claude.json`, enabled plugins, plus the Port.io connector) | `opencode.json` `mcp`. Env values are written as `{env:NAME}`, never copied. |
| Hooks in `~/.claude/settings.json` | `plugins/claude-hooks.js` reads them at startup and runs the same scripts with Claude's stdin JSON. Exit 2 blocks a tool call. |
| `settings.json` `env` | Injected into the bash tool's environment by the hooks plugin |

There is no model config anywhere. Agents inherit the session model, so OpenRouter autodiscovery or a provider in your local `~/.config/opencode/config.json` decides. The install leaves `config.json` alone.

Scripts in `~/.claude/bin`, `~/.claude/knowledge`, and `~/.claude/scratch` are referenced in place, so `.claude/` must be installed too.

### Not carried over

- Statusline, cloud routines, and Claude-only UI settings (theme, tui, remote control).
- The Workflow tool. `/review` and `/reviewit` use their parallel-subagent path instead.
- claude.ai connectors other than Atlassian and Port.io (US region, `https://mcp.us.port.io/v1`): Slack, Google, and the rest.

### One-time setup

- Export `KAGI_API_KEY`, `HARNESS_API_KEY`, `HARNESS_BASE_URL`, and `HARNESS_TOOLSETS` in your shell profile, not in this repo.
- Authenticate the OAuth servers with `opencode mcp auth Atlassian` and `opencode mcp auth Port`.
