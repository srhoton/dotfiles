import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { ClaudeHooks } from "../../.config/opencode/plugins/claude-hooks.js";

const { dispatch, hooksFor, matcherAccepts, toolInput, patchedFiles, timeoutMs } = ClaudeHooks.internals;
const REPO = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const GUARD = `bash ${join(REPO, ".claude", "hooks", "guard-destructive-git.sh")}`;

function settingsWith(event, matcher, command, extra = {}) {
  return { hooks: { [event]: [{ matcher, hooks: [{ type: "command", command, ...extra }] }] } };
}

function dirtyRepo() {
  const dir = mkdtempSync(join(tmpdir(), "claude-hooks-"));
  execFileSync("git", ["init", "-q", dir]);
  writeFileSync(join(dir, "wip.txt"), "uncommitted\n");
  return dir;
}

test("matcherAccepts - regex, wildcard and missing matcher", () => {
  assert.equal(matcherAccepts(undefined, "Bash"), true);
  assert.equal(matcherAccepts("*", "Bash"), true);
  assert.equal(matcherAccepts("Edit|Write", "Write"), true);
  assert.equal(matcherAccepts("Edit|Write", "WebFetch"), false);
  assert.equal(matcherAccepts("Bash", undefined), false);
});

test("hooksFor - skips herdr and non-command hooks", () => {
  const settings = {
    hooks: {
      SessionStart: [
        { hooks: [{ type: "command", command: "bash herdr-agent-state.sh session" }] },
        { hooks: [{ type: "prompt", prompt: "x" }, { type: "command", command: "echo ok" }] },
      ],
    },
  };
  assert.deepEqual(hooksFor(settings, "SessionStart").map((h) => h.command), ["echo ok"]);
});

test("toolInput - maps opencode args to Claude tool_input", () => {
  assert.deepEqual(toolInput("bash", { command: "ls" }), { command: "ls", description: undefined });
  assert.equal(toolInput("edit", { filePath: "/a.ts" }).file_path, "/a.ts");
  assert.equal(toolInput("write", { filePath: "/b.ts", content: "x" }).file_path, "/b.ts");
  const patch = "*** Begin Patch\n*** Update File: src/c.ts\n@@\n*** Add File: d.ts\n*** End Patch";
  assert.deepEqual(patchedFiles(patch), ["src/c.ts", "d.ts"]);
  assert.equal(toolInput("apply_patch", { patchText: patch }).file_path, "src/c.ts");
});

test("timeoutMs - Claude seconds, capped", () => {
  assert.equal(timeoutMs({ timeout: 10 }), 10_000);
  assert.equal(timeoutMs({ timeout: 120000 }), 300_000);
  assert.equal(timeoutMs({}), 60_000);
});

test("dispatch - real destructive-git guard blocks reset --hard on a dirty repo", async () => {
  const repo = dirtyRepo();
  const settings = settingsWith("PreToolUse", "Bash", GUARD, { timeout: 10 });
  const payload = { tool_name: "Bash", tool_input: { command: "git reset --hard" } };
  const { block } = await dispatch(settings, "PreToolUse", payload, repo);
  assert.match(block ?? "", /uncommitted/i);
});

test("dispatch - real guard allows a read-only command", async () => {
  const repo = dirtyRepo();
  const settings = settingsWith("PreToolUse", "Bash", GUARD, { timeout: 10 });
  const payload = { tool_name: "Bash", tool_input: { command: "git status" } };
  assert.equal((await dispatch(settings, "PreToolUse", payload, repo)).block, null);
});

test("dispatch - matcher keeps a Bash guard off Edit calls", async () => {
  const settings = settingsWith("PreToolUse", "Bash", "exit 2");
  const { block } = await dispatch(settings, "PreToolUse", { tool_name: "Edit", tool_input: {} }, tmpdir());
  assert.equal(block, null);
});

test("dispatch - permissionDecision deny blocks", async () => {
  const out = JSON.stringify({ hookSpecificOutput: { permissionDecision: "deny", permissionDecisionReason: "nope" } });
  const settings = settingsWith("PreToolUse", undefined, `echo '${out}'`);
  const { block } = await dispatch(settings, "PreToolUse", { tool_name: "Bash", tool_input: {} }, tmpdir());
  assert.equal(block, "nope");
});

test("dispatch - non-2 failure logs and does not block", async () => {
  const settings = settingsWith("PreToolUse", undefined, "echo boom >&2; exit 1");
  const original = console.error;
  const logged = [];
  console.error = (msg) => logged.push(msg);
  try {
    const { block } = await dispatch(settings, "PreToolUse", { tool_name: "Bash", tool_input: {} }, tmpdir());
    assert.equal(block, null);
  } finally {
    console.error = original;
  }
  assert.match(logged.join("\n"), /exited 1/);
});

test("dispatch - PostToolUse additionalContext and exit-2 stderr reach the model", async () => {
  const ctx = JSON.stringify({ hookSpecificOutput: { additionalContext: "lint: 2 errors" } });
  const settings = {
    hooks: {
      PostToolUse: [
        { matcher: "Edit|Write", hooks: [{ type: "command", command: `echo '${ctx}'` }] },
        { matcher: "Write", hooks: [{ type: "command", command: "echo stale >&2; exit 2" }] },
      ],
    },
  };
  const { block, context } = await dispatch(settings, "PostToolUse", { tool_name: "Write", tool_input: {} }, tmpdir());
  assert.equal(block, null);
  assert.deepEqual(context, ["lint: 2 errors", "stale"]);
});

test("dispatch - hook receives Claude-shaped stdin", async () => {
  const settings = settingsWith("PreToolUse", undefined, `python3 -c "import json,sys;d=json.load(sys.stdin);sys.exit(2 if d['hook_event_name']=='PreToolUse' and d['tool_input']['command']=='x' else 0)"`);
  const { block } = await dispatch(settings, "PreToolUse", { tool_name: "Bash", tool_input: { command: "x" } }, tmpdir());
  assert.notEqual(block, null);
});

test("plugin - shell.env injects settings env, tool.execute.before throws on block", async () => {
  const dir = mkdtempSync(join(tmpdir(), "claude-hooks-settings-"));
  const path = join(dir, "settings.json");
  const settings = settingsWith("PreToolUse", "Bash", "echo refused >&2; exit 2");
  writeFileSync(path, JSON.stringify({ ...settings, env: { AWS_PROFILE: "fb-dev-non-prod/Admin" } }));
  process.env.CLAUDE_HOOKS_SETTINGS = path;
  const { ClaudeHooks: Fresh } = await import(`../../.config/opencode/plugins/claude-hooks.js?settings=${Date.now()}`);
  delete process.env.CLAUDE_HOOKS_SETTINGS;
  const hooks = await Fresh({ directory: dir });
  const env = {};
  await hooks["shell.env"]({ cwd: dir }, { env });
  assert.equal(env.AWS_PROFILE, "fb-dev-non-prod/Admin");
  await assert.rejects(
    hooks["tool.execute.before"]({ tool: "bash", sessionID: "s", callID: "c" }, { args: { command: "ls" } }),
    /refused/,
  );
  await hooks["tool.execute.before"]({ tool: "read", sessionID: "s", callID: "c" }, { args: { filePath: "/etc/hosts" } });
});
