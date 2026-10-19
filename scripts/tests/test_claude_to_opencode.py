"""Tests for scripts/claude-to-opencode."""

import importlib.machinery
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "claude-to-opencode"
_loader = importlib.machinery.SourceFileLoader("claude_to_opencode", str(SCRIPT))
_spec = importlib.util.spec_from_loader(_loader.name, _loader)
c2o = importlib.util.module_from_spec(_spec)
_loader.exec_module(c2o)

CLAUDE_MD = """# Global Rules
Language and tool rules live in `~/.claude/rules/` and load when matching files are touched.

### Use of tools
- **Bounded subagents**: scope every dispatch.
- **Subagent model tier**: pass `model` on every Agent tool call:
  - **`haiku`** - lookups.
  - **`sonnet`** - research.
- reconnect the server via `/mcp`.
- Ask with `AskUserQuestion`; track with TodoWrite. Read the project's `CLAUDE.md`.
"""

READ_ONLY_AGENT = """---
name: functional-reviewer
description: Verifies code.
tools: Read, Glob, Grep, Bash
model: opus
color: purple
---

Use the Task tool. See ~/.claude/rules/java.md, ~/.claude/rules/<lang>.md and the legacy ~/.claude/java_rules.md.
"""

JAVA_RULE = """---
paths:
  - "**/*.java"
  - "**/libs.versions.toml"
---

# Java Rules

Follow ~/.claude/rules/shared.md. Never edit CLAUDE.md here.
"""

REACT_RULE = """---
paths:
  - "**/*.{ts,tsx}"
  - '**/vite.config.*'
---

# React Rules

See @~/.claude/rules/java.md for the base rules.
"""

PLAIN_RULE = "# Shared Rules\n\nNo scope here.\n"

DELIVER_COMMAND = """---
description: "Deliver a ticket."
disable-model-invocation: true
---
You are a delivery pipeline for `$ARGUMENTS`.
"""

ROUTER_AGENT = """---
name: routing-agent
description: |
  Orchestrates.

  <example>x</example>
tools: Read, Write, Edit, Bash, Task, AskUserQuestion
---
Body.
"""


def make_source(root: Path, kagi_value: str = "") -> tuple[Path, Path, list[Path]]:
    src = root / "claude"
    (src / "agents").mkdir(parents=True)
    (src / "commands").mkdir()
    (src / "CLAUDE.md").write_text(CLAUDE_MD)
    (src / "rules").mkdir()
    (src / "rules" / "java.md").write_text(JAVA_RULE)
    (src / "rules" / "react.md").write_text(REACT_RULE)
    (src / "rules" / "shared.md").write_text(PLAIN_RULE)
    (src / "agents" / "functional-reviewer.md").write_text(READ_ONLY_AGENT)
    (src / "agents" / "routing-agent.md").write_text(ROUTER_AGENT)
    (src / "commands" / "shipit.md").write_text(
        "You are a deployer. Deploy `$ARGUMENTS` now.\n"
    )
    (src / "commands" / "deliver.md").write_text(DELIVER_COMMAND)
    (src / "commands" / "vlt.md").write_text("Ok. Lint it.\n")
    (src / "settings.json").write_text(
        json.dumps(
            {
                "env": {
                    "AWS_PROFILE": "fb-dev-non-prod/Admin",
                    "OTHER": "not-copied-literally",
                },
                "skillOverrides": {"vlt": "off", "shipit": "on"},
                "enabledPlugins": {"tools@market": True, "off@market": False},
            }
        )
    )
    home = root / "home"
    plugin = home / "plugins" / "cache" / "market" / "tools" / "1.0.0"
    (plugin / "skills" / "query-lake").mkdir(parents=True)
    (plugin / "skills" / "query-lake" / "SKILL.md").write_text(
        "---\nname: query-lake\ndescription: q\n---\nBody\n"
    )
    (plugin / ".mcp.json").write_text(
        json.dumps({"mcpServers": {"aws-mcp": {"command": "uvx", "args": ["proxy"]}}})
    )
    off = home / "plugins" / "cache" / "market" / "off" / "1.0.0" / "skills" / "hidden"
    off.mkdir(parents=True)
    (off / "SKILL.md").write_text("---\nname: hidden\ndescription: h\n---\n")
    mcp = root / "claude.json"
    mcp.write_text(
        json.dumps(
            {
                "mcpServers": {
                    "Kagi": {
                        "command": "uvx",
                        "args": ["kagimcp"],
                        "env": {"KAGI_API_KEY": kagi_value},
                    },
                    "Github": {
                        "command": "gh-mcp",
                        "env": {"GITHUB_PERSONAL_ACCESS_TOKEN": ""},
                    },
                    "Atlassian": {
                        "type": "http",
                        "url": "https://mcp.atlassian.com/v2/mcp",
                    },
                }
            }
        )
    )
    return src, home, [mcp]


class GenerateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_generate(self, kagi_value: str = "") -> Path:
        src, home, mcp = make_source(self.root, kagi_value)
        out = self.root / "out"
        c2o.generate(src, out, home, mcp)
        return out

    def test_agents_md_rewrites_and_drops_model_tier(self) -> None:
        text = (self.run_generate() / "AGENTS.md").read_text()
        self.assertIn(
            "Language and tool rules live in `~/.config/opencode/rules/`;"
            " each file opens with an `Applies to:` line",
            text,
        )
        self.assertNotIn("load when matching files are touched", text)
        self.assertNotIn("~/.claude", text)
        self.assertNotIn("Subagent model tier", text)
        self.assertNotIn("haiku", text)
        self.assertIn("Bounded subagents", text)
        self.assertIn("reconnect it with `opencode mcp`", text)
        self.assertIn("`question`", text)
        self.assertIn("todowrite", text)
        self.assertIn("`AGENTS.md` (or `CLAUDE.md`)", text)

    def test_missing_claude_md_marker_fails(self) -> None:
        src, home, mcp = make_source(self.root)
        (src / "CLAUDE.md").write_text(
            CLAUDE_MD.replace("**Subagent model tier**", "**Model picks**")
        )
        with self.assertRaisesRegex(c2o.GenerationError, "subagent model tier"):
            c2o.generate(src, self.root / "out", home, mcp)

    def test_read_only_agent_gets_edit_and_task_deny(self) -> None:
        text = (self.run_generate() / "agents" / "functional-reviewer.md").read_text()
        front = text.split("---")[1]
        self.assertIn("mode: subagent", front)
        self.assertIn("  edit: deny", front)
        self.assertIn("  task: deny", front)
        for dropped in ("name:", "model:", "color:", "tools:"):
            self.assertNotIn(dropped, front)
        self.assertIn("Use the task tool", text)
        self.assertIn(
            "See ~/.config/opencode/rules/java.md, ~/.config/opencode/rules/<lang>.md"
            " and the legacy ~/.config/opencode/rules/java.md.",
            text,
        )
        self.assertNotIn("_rules.md", text)

    def test_router_agent_keeps_block_description_and_full_permissions(self) -> None:
        text = (self.run_generate() / "agents" / "routing-agent.md").read_text()
        front = text.split("\n---\n")[0]
        self.assertIn(
            "description: |\n  Orchestrates.\n\n  <example>x</example>", front
        )
        self.assertNotIn("permission:", front)

    def test_disabled_commands_skipped_and_description_derived(self) -> None:
        out = self.run_generate()
        self.assertEqual(
            sorted(p.name for p in (out / "commands").iterdir()),
            ["deliver.md", "shipit.md"],
        )
        text = (out / "commands" / "shipit.md").read_text()
        self.assertTrue(
            text.startswith(
                '---\ndescription: "You are a deployer. Deploy <args> now."\n---\n'
            )
        )
        self.assertIn("$ARGUMENTS", text.split("---\n", 2)[2])

    def test_command_frontmatter_drops_model_invocation_key_and_keeps_description(
        self,
    ) -> None:
        text = (self.run_generate() / "commands" / "deliver.md").read_text()
        self.assertEqual(
            text,
            '---\ndescription: "Deliver a ticket."\n---\n'
            "You are a delivery pipeline for `$ARGUMENTS`.\n",
        )
        self.assertNotIn("disable-model-invocation", text)

    def test_rules_strip_paths_and_state_scope(self) -> None:
        rules = self.run_generate() / "rules"
        self.assertEqual(
            sorted(p.name for p in rules.iterdir()),
            ["java.md", "react.md", "shared.md"],
        )
        java = (rules / "java.md").read_text()
        self.assertTrue(
            java.startswith(
                "Applies to: `**/*.java`, `**/libs.versions.toml`\n\n# Java Rules\n"
            )
        )
        self.assertNotIn("paths:", java)
        self.assertNotIn("---", java)
        self.assertIn("~/.config/opencode/rules/shared.md", java)
        self.assertIn("AGENTS.md", java)
        self.assertNotIn("CLAUDE.md", java)
        react = (rules / "react.md").read_text()
        self.assertTrue(
            react.startswith(
                "Applies to: `**/*.{ts,tsx}`, `**/vite.config.*`\n\n# React Rules\n"
            )
        )
        self.assertIn("@~/.config/opencode/rules/java.md", react)
        self.assertEqual((rules / "shared.md").read_text(), PLAIN_RULE)

    def test_convert_rule_accepts_inline_paths_forms(self) -> None:
        flow = '---\npaths: ["**/*.{ts,tsx}", "**/x.json"]\n---\nBody\n'
        self.assertEqual(
            c2o.convert_rule(flow), "Applies to: `**/*.{ts,tsx}`, `**/x.json`\n\nBody\n"
        )
        scalar = "---\npaths: **/*.{py,pyi}\n---\nBody\n"
        self.assertEqual(
            c2o.convert_rule(scalar), "Applies to: `**/*.{py,pyi}`\n\nBody\n"
        )

    def test_rule_with_empty_paths_fails(self) -> None:
        with self.assertRaisesRegex(c2o.GenerationError, "no globs"):
            c2o.convert_rule("---\npaths:\n---\nBody\n")

    def test_missing_rules_directory_fails(self) -> None:
        src, home, mcp = make_source(self.root)
        for rule in (src / "rules").iterdir():
            rule.unlink()
        (src / "rules").rmdir()
        with self.assertRaisesRegex(c2o.GenerationError, "rules"):
            c2o.generate(src, self.root / "out", home, mcp)

    def test_missing_rules_pointer_fails(self) -> None:
        src, home, mcp = make_source(self.root)
        (src / "CLAUDE.md").write_text(
            CLAUDE_MD.replace("Language and tool rules live", "Rules are")
        )
        with self.assertRaisesRegex(c2o.GenerationError, "rules pointer"):
            c2o.generate(src, self.root / "out", home, mcp)

    def test_skills_only_from_enabled_plugins(self) -> None:
        out = self.run_generate()
        self.assertEqual(
            sorted(p.name for p in (out / "skills").iterdir()), ["query-lake"]
        )

    def test_invalid_skill_name_fails(self) -> None:
        src, home, mcp = make_source(self.root)
        bad = (
            home
            / "plugins"
            / "cache"
            / "market"
            / "tools"
            / "1.0.0"
            / "skills"
            / "Bad_Name"
        )
        bad.mkdir()
        (bad / "SKILL.md").write_text("---\nname: Bad_Name\ndescription: b\n---\n")
        with self.assertRaisesRegex(c2o.GenerationError, "Bad_Name"):
            c2o.generate(src, self.root / "out", home, mcp)

    def test_mcp_env_values_never_copied(self) -> None:
        planted = "kagi-value-that-must-not-leak"
        out = self.run_generate(kagi_value=planted)
        config = json.loads((out / "opencode.json").read_text())
        mcp = config["mcp"]
        self.assertEqual(sorted(mcp), ["Atlassian", "Kagi", "Port", "aws-mcp"])
        self.assertEqual(
            mcp["Port"], {"type": "remote", "url": "https://mcp.us.port.io/v1"}
        )
        self.assertEqual(
            mcp["Kagi"]["environment"]["KAGI_API_KEY"], "{env:KAGI_API_KEY}"
        )
        self.assertEqual(
            mcp["aws-mcp"]["environment"], {"AWS_PROFILE": "fb-dev-non-prod/Admin"}
        )
        self.assertEqual(
            mcp["Atlassian"],
            {"type": "remote", "url": "https://mcp.atlassian.com/v2/mcp"},
        )
        self.assertNotIn("model", config)
        for path in out.rglob("*"):
            if path.is_file():
                text = path.read_text()
                self.assertNotIn(planted, text, path)
                self.assertNotIn("not-copied-literally", text, path)

    def test_secret_scan_catches_planted_key(self) -> None:
        src, home, mcp = make_source(self.root)
        key = "ghp_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"
        (src / "commands" / "shipit.md").write_text(f"Deploy with token {key}.\n")
        with self.assertRaisesRegex(c2o.GenerationError, "possible secrets"):
            c2o.generate(src, self.root / "out", home, mcp)

    def test_secret_scan_long_token_but_not_identifiers(self) -> None:
        root = self.root / "scan"
        root.mkdir()
        (root / "ok.md").write_text(
            "X-Amzn-Bedrock-AgentCore-Runtime-Custom-Correlation-Id and "
            "0123456789abcdef0123456789abcdef01234567 and arn:aws:iam::123/Role\n"
        )
        self.assertEqual(c2o.scan_secrets(root), [])
        (root / "bad.md").write_text(
            "K3AAz9Qx81LmPqRsTuVwXyZ0123456789AbCdEfGhIjKlMn\n"
        )
        self.assertEqual(len(c2o.scan_secrets(root)), 1)

    def test_check_mode_detects_drift(self) -> None:
        src, home, mcp = make_source(self.root)
        out = self.root / "out"
        args = [
            "--src",
            str(src),
            "--out",
            str(out),
            "--claude-home",
            str(home),
            "--mcp-source",
            str(mcp[0]),
        ]
        self.assertEqual(c2o.main(args), 0)
        (out / "plugins").mkdir()
        (out / "plugins" / "hand-written.js").write_text("// not owned\n")
        self.assertEqual(c2o.main([*args, "--check"]), 0)
        (src / "commands" / "shipit.md").write_text("You are a deployer. Changed.\n")
        self.assertEqual(c2o.main([*args, "--check"]), 1)
        self.assertEqual(c2o.main(args), 0)
        self.assertTrue((out / "plugins" / "hand-written.js").exists())
        self.assertEqual(c2o.main([*args, "--check"]), 0)


if __name__ == "__main__":
    unittest.main()
