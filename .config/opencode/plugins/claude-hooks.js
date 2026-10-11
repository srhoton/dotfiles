// Runs the Claude Code hooks from ~/.claude/settings.json inside opencode.
//
// Hook scripts get the same stdin JSON Claude sends them (session_id, cwd,
// hook_event_name, tool_name, tool_input), so they need no opencode-specific code.
// Exit 2, or a PreToolUse permissionDecision of "deny", blocks a tool call.
// Any other failure is logged and never blocks.
//
// Only the ClaudeHooks export is a plugin: opencode loads every exported function
// in this directory as one, so helpers hang off it instead of being exported.

import { spawn, spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const SETTINGS_PATH = process.env.CLAUDE_HOOKS_SETTINGS || join(homedir(), ".claude", "settings.json");
// Hooks with their own opencode integration.
const SKIP_COMMANDS = [/herdr-agent-state/];
// Claude timeouts are seconds; cap them so a hung hook can't stall a session.
const MAX_TIMEOUT_SECONDS = 300;
const DEFAULT_TIMEOUT_SECONDS = 60;

const TOOL_NAMES = {
  bash: "Bash",
  edit: "Edit",
  write: "Write",
  apply_patch: "Edit",
  read: "Read",
  grep: "Grep",
  glob: "Glob",
  list: "LS",
  webfetch: "WebFetch",
  websearch: "WebSearch",
  task: "Task",
  todowrite: "TodoWrite",
  question: "AskUserQuestion",
  skill: "Skill",
};

function loadSettings(path = SETTINGS_PATH) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (err) {
    console.error(`[claude-hooks] cannot read ${path}: ${err.message}`);
    return {};
  }
}

function matcherAccepts(matcher, toolName) {
  if (!matcher || matcher === "*") return true;
  if (!toolName) return false;
  try {
    return new RegExp(`^(?:${matcher})$`).test(toolName);
  } catch {
    return matcher === toolName;
  }
}

function hooksFor(settings, event, toolName) {
  const groups = settings.hooks?.[event] ?? [];
  return groups
    .filter((group) => matcherAccepts(group.matcher, toolName))
    .flatMap((group) => group.hooks ?? [])
    .filter((hook) => hook.type === "command" && hook.command)
    .filter((hook) => !SKIP_COMMANDS.some((pattern) => pattern.test(hook.command)));
}

function timeoutMs(hook) {
  const seconds = Number(hook.timeout) || DEFAULT_TIMEOUT_SECONDS;
  return Math.min(seconds, MAX_TIMEOUT_SECONDS) * 1000;
}

function runCommand(command, payload, ms, cwd) {
  return new Promise((resolve) => {
    const child = spawn("/bin/bash", ["-c", command], {
      cwd,
      env: { ...process.env, CLAUDE_PROJECT_DIR: cwd ?? process.cwd() },
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => child.kill("SIGKILL"), ms);
    child.stdout.on("data", (chunk) => (stdout += chunk));
    child.stderr.on("data", (chunk) => (stderr += chunk));
    child.on("error", (err) => {
      clearTimeout(timer);
      resolve({ code: -1, stdout, stderr: String(err.message) });
    });
    child.on("close", (code, signal) => {
      clearTimeout(timer);
      resolve({ code: signal ? -1 : code, stdout, stderr });
    });
    child.stdin.on("error", () => {});
    child.stdin.end(JSON.stringify(payload));
  });
}

function parseJson(text) {
  const trimmed = text.trim();
  if (!trimmed.startsWith("{")) return null;
  try {
    return JSON.parse(trimmed);
  } catch {
    return null;
  }
}

// Returns { block, context }: block is the reason a PreToolUse hook refused the call
// (null if none did); context collects text hooks asked to show the model.
async function dispatch(settings, event, payload, cwd, run = runCommand) {
  const context = [];
  for (const hook of hooksFor(settings, event, payload.tool_name)) {
    const result = await run(hook.command, { ...payload, hook_event_name: event }, timeoutMs(hook), cwd);
    const json = parseJson(result.stdout);
    const specific = json?.hookSpecificOutput ?? {};
    if (specific.additionalContext) context.push(specific.additionalContext);
    if (event === "PreToolUse" && specific.permissionDecision === "deny") {
      return { block: specific.permissionDecisionReason || `blocked by ${hook.command}`, context };
    }
    if (result.code === 2) {
      const reason = result.stderr.trim() || `blocked by ${hook.command}`;
      if (event === "PreToolUse") return { block: reason, context };
      context.push(reason);
    } else if (result.code !== 0) {
      console.error(`[claude-hooks] ${event} hook exited ${result.code}: ${hook.command}\n${result.stderr.trim()}`);
    }
  }
  return { block: null, context };
}

function patchedFiles(patchText) {
  return [...String(patchText ?? "").matchAll(/^\*\*\* (?:Add|Update|Delete) File: (.+)$/gm)].map((m) => m[1].trim());
}

// Translates opencode tool args into the Claude tool_input shape the hook scripts read.
function toolInput(tool, args = {}) {
  switch (tool) {
    case "bash":
      return { command: args.command, description: args.description };
    case "edit":
      return { file_path: args.filePath, old_string: args.oldString, new_string: args.newString };
    case "write":
      return { file_path: args.filePath, content: args.content };
    case "apply_patch":
      return { file_path: patchedFiles(args.patchText)[0] };
    default:
      return { ...args, file_path: args.filePath };
  }
}

export const ClaudeHooks = async ({ directory }) => {
  const settings = loadSettings();
  const childSessions = new Set();
  const sessionContext = new Map();
  let rootSessionID;
  const base = (sessionID) => ({ session_id: sessionID, cwd: directory });

  process.once("exit", () => {
    for (const hook of hooksFor(settings, "SessionEnd")) {
      spawnSync("/bin/bash", ["-c", hook.command], {
        input: JSON.stringify({ ...base(rootSessionID), hook_event_name: "SessionEnd", reason: "exit" }),
        timeout: Math.min(timeoutMs(hook), 5000),
        cwd: directory,
      });
    }
  });

  return {
    "shell.env": async (_input, output) => {
      Object.assign(output.env, settings.env ?? {});
    },

    "tool.execute.before": async (input, output) => {
      const payload = {
        ...base(input.sessionID),
        tool_name: TOOL_NAMES[input.tool] ?? input.tool,
        tool_input: toolInput(input.tool, output.args),
      };
      const { block } = await dispatch(settings, "PreToolUse", payload, directory);
      if (block) throw new Error(block);
    },

    "tool.execute.after": async (input, output) => {
      const payload = {
        ...base(input.sessionID),
        tool_name: TOOL_NAMES[input.tool] ?? input.tool,
        tool_input: toolInput(input.tool, input.args),
        tool_response: { output: output.output },
      };
      const { context } = await dispatch(settings, "PostToolUse", payload, directory);
      if (context.length) output.output = `${output.output}\n\n${context.join("\n\n")}`;
    },

    "chat.message": async (input, output) => {
      const prompt = (output.parts ?? []).filter((p) => p.type === "text").map((p) => p.text).join("\n");
      const { context } = await dispatch(settings, "UserPromptSubmit", { ...base(input.sessionID), prompt }, directory);
      if (context.length) sessionContext.set(input.sessionID, [...(sessionContext.get(input.sessionID) ?? []), ...context]);
    },

    "experimental.chat.system.transform": async (input, output) => {
      const extra = sessionContext.get(input.sessionID);
      if (extra?.length) output.system.push(...extra);
    },

    event: async ({ event }) => {
      const props = event.properties ?? {};
      switch (event.type) {
        case "session.created": {
          const info = props.info ?? {};
          if (info.parentID) {
            childSessions.add(info.id);
            return;
          }
          rootSessionID = info.id;
          const { context } = await dispatch(settings, "SessionStart", { ...base(info.id), source: "startup" }, directory);
          if (context.length) sessionContext.set(info.id, context);
          return;
        }
        case "session.idle": {
          const name = childSessions.has(props.sessionID) ? "SubagentStop" : "Stop";
          await dispatch(settings, name, { ...base(props.sessionID), stop_hook_active: false }, directory);
          return;
        }
        case "session.error":
          await dispatch(settings, "StopFailure", { ...base(props.sessionID), error: props.error }, directory);
          return;
        case "permission.updated": {
          const payload = { ...base(props.sessionID), message: props.title ?? "opencode needs your permission" };
          await dispatch(settings, "PermissionRequest", payload, directory);
          await dispatch(settings, "Notification", { ...payload, notification_type: "permission_prompt" }, directory);
          return;
        }
        default:
      }
    },
  };
};

ClaudeHooks.internals = { dispatch, hooksFor, matcherAccepts, toolInput, patchedFiles, timeoutMs, runCommand };
