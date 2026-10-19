#!/bin/bash
#
# PreToolUse hook: block reads of Secrets Manager secret values.
#
# Scope: this hook ONLY enforces the secret-read rule. Prod read-only is no
# longer enforced here; it lives in IAM. Claude uses the fb-live-us-prod/ReadOnly
# SSO role, which denies all writes plus secretsmanager:GetSecretValue and
# kms:Decrypt. Secret reads stay hook-enforced because the dev and data-lake
# Admin profiles CAN read secrets, and secret values must never enter context.
# Use the aws-secrets-manager skill's runtime-resolution pattern instead:
#   {{resolve:secretsmanager:<secret-id>:SecretString:<json-key>}}
#
# Protocol: PreToolUse JSON on stdin. Exit 2 blocks (message on stderr), exit 0
# allows. Non-JSON or unrelated input is allowed. Only linear substring/regex
# checks on the text; no shell parsing.
#
# Bash tool (lowercased command):
#   R1  "get-secret-value" (covers batch-get-secret-value) AND "secretsmanager"
#       or an aws/awscli word (an "aws" preceded by "/" or "." does not count,
#       so ~/.aws/config and /aws/lambda/... log groups do not trigger)
#   R2  "/aws/reference/secretsmanager" AND a get-parameter spelling
#   R3  getsecretvalue / batchgetsecretvalue / get_secret_value AND one of
#       secretsmanager, secrets-manager, boto3, aws-sdk
# MCP run_script tool (tool_input.code): R2, or any GetSecretValue spelling.
#
# Fail-closed on an internal error only when the input mentions "secret".

read -r -d '' PY <<'PYEOF'
import json, re, sys

MSG = (
    "BLOCKED: reading Secrets Manager secret values is not allowed; the value "
    "must never enter context. Use the aws-secrets-manager skill's runtime "
    "resolution instead: {{resolve:secretsmanager:<secret-id>:SecretString:<json-key>}}"
)
GET_PARAM = ("get-parameter", "get_parameter", "getparameter")
R2_PATH = "/aws/reference/secretsmanager"
AWS_WORD = re.compile(r"(?<![\w/.])(?:aws|awscli)\b")
R3_FN = re.compile(r"getsecretvalue|batchgetsecretvalue|get_secret_value")
R3_CTX = ("secretsmanager", "secrets-manager", "boto3", "aws-sdk")
MCP_FN = re.compile(r"getsecretvalue|batchgetsecretvalue|get[_-]secret[_-]value")
MCP_TOOL = re.compile(r"mcp__.*aws.*run_script", re.IGNORECASE)


def r2(t):
    return R2_PATH in t and any(p in t for p in GET_PARAM)


def bash_blocked(t):
    t = t.lower()
    if "get-secret-value" in t and ("secretsmanager" in t or AWS_WORD.search(t)):
        return True
    if r2(t):
        return True
    return bool(R3_FN.search(t)) and any(c in t for c in R3_CTX)


def mcp_blocked(t):
    t = t.lower()
    return r2(t) or bool(MCP_FN.search(t))


try:
    data = json.loads(sys.stdin.read())
except ValueError:
    sys.exit(0)
if not isinstance(data, dict):
    sys.exit(0)
name = data.get("tool_name")
ti = data.get("tool_input")
if not isinstance(name, str) or not isinstance(ti, dict):
    sys.exit(0)
if name == "Bash":
    cmd = ti.get("command")
    blocked = isinstance(cmd, str) and bash_blocked(cmd)
elif MCP_TOOL.search(name):
    code = ti.get("code")
    blocked = mcp_blocked(code if isinstance(code, str) else json.dumps(ti))
else:
    sys.exit(0)
if blocked:
    sys.stderr.write(MSG + "\n")
    sys.exit(2)
sys.exit(0)
PYEOF

input=$(cat)
printf '%s' "$input" | python3 -I -c "$PY"
rc=$?
case "$rc" in
  0 | 2) exit "$rc" ;;
esac

# Internal error (python crash or missing): fail closed only if "secret" appears.
if printf '%s' "$input" | grep -qi 'secret'; then
  echo "BLOCKED: guard-prod-readonly.sh internal error (rc=$rc) on input mentioning 'secret'; failing closed. Use the aws-secrets-manager skill's {{resolve:secretsmanager:...}} pattern." >&2
  exit 2
fi
exit 0
