#!/bin/bash
#
# Tests for hooks/guard-prod-readonly.sh (secret-read rule only). Synthetic inputs only.
# Usage: bash hooks/tests/guard-prod-readonly.sh
# Override the hook under test with HOOK=/path/to/copy.sh (used for mutation checks).
#
# Prod read-only is NOT this hook's job any more: it is enforced by IAM through the
# fb-live-us-prod/ReadOnly SSO role. Prod mutation commands (e.g. dynamodb put-item)
# are therefore expected to be ALLOWED by the hook, and are tested as such below.

HOOK="${HOOK:-$(cd "$(dirname "$0")/.." && pwd)/guard-prod-readonly.sh}"
# Built by concatenation so no literal prod profile string appears in this file.
PROD_RO="fb-live-us-""prod/ReadOnly"
DEV="fb-dev-non-prod/Admin"
PASS=0
FAIL=0

MCP_TOOL_A="mcp__claude_ai_AWS_MCP__aws___run_script"
MCP_TOOL_B="mcp__plugin_aws-data-analytics_aws-mcp__aws___run_script"

json_bash() {
  CMD="$1" python3 -c 'import json,os;print(json.dumps({"tool_name":"Bash","tool_input":{"command":os.environ["CMD"]}}))'
}

# json_mcp CODE [TOOL_NAME]
json_mcp() {
  CODE="$1" TOOL="${2:-$MCP_TOOL_A}" python3 -c 'import json,os;print(json.dumps({"tool_name":os.environ["TOOL"],"tool_input":{"code":os.environ["CODE"]}}))'
}

# check NAME EXPECTED_RC JSON
check() {
  local name="$1" want="$2" json="$3" got err
  err=$(printf '%s' "$json" | bash "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [ "$got" -eq "$want" ]; then
    PASS=$((PASS + 1))
    echo "PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $name (want exit $want, got $got) $err"
  fi
}

bash_case() { check "$1" "$2" "$(json_bash "$3")"; }
mcp_case() { check "$1" "$2" "$(json_mcp "$3" "${4:-}")"; }

# --- R1: CLI get-secret-value ---
bash_case "R1 plain get-secret-value" 2 "aws secretsmanager get-secret-value --secret-id x"
bash_case "R1 batch-get-secret-value" 2 "aws secretsmanager batch-get-secret-value --secret-id-list x y"
bash_case "R1 timeout wrapper" 2 "timeout 30 aws secretsmanager get-secret-value --secret-id x"
bash_case "R1 echo piped to xargs" 2 "echo get-secret-value | xargs aws secretsmanager"
bash_case "R1 dev Admin profile" 2 "aws --profile $DEV secretsmanager get-secret-value --secret-id x"
bash_case "R1 prod ReadOnly profile still blocked" 2 "aws --profile $PROD_RO secretsmanager get-secret-value --secret-id x"
bash_case "R1 uppercase command" 2 "AWS SECRETSMANAGER GET-SECRET-VALUE --SECRET-ID x"
bash_case "R1 mixed case" 2 "Aws SecretsManager Get-Secret-Value --secret-id x"
bash_case "R1 awscli word without secretsmanager" 2 "awscli get-secret-value --secret-id x"

# --- R2: SSM parameter path for Secrets Manager ---
bash_case "R2 CLI get-parameter" 2 "aws ssm get-parameter --name /aws/reference/secretsmanager/x --with-decryption"
bash_case "R2 CLI uppercase" 2 "AWS SSM GET-PARAMETER --NAME /AWS/REFERENCE/SECRETSMANAGER/x"
bash_case "R2 boto3 get_parameter" 2 "python3 -c \"import boto3; boto3.client('ssm').get_parameter(Name='/aws/reference/secretsmanager/x')\""
bash_case "R2 node GetParameterCommand" 2 "node -e \"new GetParameterCommand({Name:'/aws/reference/secretsmanager/x'})\""

# --- R3: SDK GetSecretValue ---
bash_case "R3 boto3 get_secret_value" 2 "python3 -c \"import boto3; boto3.client('x').get_secret_value(SecretId='x')\""
bash_case "R3 node GetSecretValueCommand" 2 "node -e \"const {GetSecretValueCommand}=require('@aws-sdk/client-secrets-manager'); new GetSecretValueCommand({SecretId:'x'})\""
bash_case "R3 BatchGetSecretValue with secretsmanager" 2 "node -e \"BatchGetSecretValueCommand secretsmanager\""

# --- MCP run_script ---
mcp_case "MCP GetSecretValue" 2 "const c = new GetSecretValueCommand({SecretId: 'x'})"
mcp_case "MCP get_secret_value" 2 "boto3.client('secretsmanager').get_secret_value(SecretId='x')"
mcp_case "MCP get-secret-value spelling" 2 "aws secretsmanager get-secret-value --secret-id x"
mcp_case "MCP BatchGetSecretValue" 2 "client.batch_get_secret_value(SecretIdList=['x'])" "$MCP_TOOL_B"
mcp_case "MCP SSM reference path" 2 "ssm.get_parameter(Name='/aws/reference/secretsmanager/x')" "$MCP_TOOL_B"
mcp_case "MCP uppercase" 2 "GETSECRETVALUE"

# --- Allowed ---
bash_case "allow describe-secret" 0 "aws secretsmanager describe-secret --secret-id x"
bash_case "allow list-secrets" 0 "aws secretsmanager list-secrets"
bash_case "allow grep for the string in docs" 0 "grep -rn get-secret-value docs/"
bash_case "allow cat ~/.aws/config" 0 "cat ~/.aws/config"
bash_case "allow ls .aws dir" 0 "ls -la ~/.aws/"
bash_case "allow /aws/lambda log group on prod ReadOnly" 0 "aws logs filter-log-events --profile $PROD_RO --log-group-name /aws/lambda/fn --start-time \$(date +%s)000"
# Not this hook's job any more: IAM (ReadOnly role) denies prod writes.
bash_case "allow prod dynamodb put-item (IAM enforces, not the hook)" 0 "aws dynamodb put-item --table-name t --item '{}' --profile $PROD_RO"
bash_case "allow git status" 0 "git status"
bash_case "allow ssm get-parameter on a normal path" 0 "aws ssm get-parameter --name /app/config/x"
mcp_case "allow MCP dynamodb query" 0 "client('dynamodb').query(TableName='t', KeyConditionExpression='a = :a')"
mcp_case "allow MCP describe_secret" 0 "boto3.client('secretsmanager').describe_secret(SecretId='x')"
check "allow non-JSON input" 0 "this is not json get-secret-value secretsmanager"
check "allow empty input" 0 ""
check "allow JSON array" 0 '["get-secret-value"]'
check "allow unrelated tool" 0 '{"tool_name":"Write","tool_input":{"content":"aws secretsmanager get-secret-value"}}'

# --- Timing: 1MB of ARN lines must be judged in well under 1s ---
bigfile=$(mktemp)
trap 'rm -f "$bigfile"' EXIT
python3 -c 'import json;print(json.dumps({"tool_name":"Bash","tool_input":{"command":"arn:aws:secretsmanager:us-east-1:000000000000:secret:x\n"*21000}}))' >"$bigfile"
secs=$(HOOK="$HOOK" BIGFILE="$bigfile" python3 -c '
import os, subprocess, time
data = open(os.environ["BIGFILE"], "rb").read()
t = time.monotonic()
r = subprocess.run(["bash", os.environ["HOOK"]], input=data, capture_output=True)
print("%d %.3f" % (r.returncode, time.monotonic() - t))')
rc=${secs%% *}; el=${secs##* }
if [ "$rc" = "0" ] && python3 -c "import sys; sys.exit(0 if float('$el') < 1.0 else 1)"; then
  PASS=$((PASS + 1)); echo "PASS: 1MB of secretsmanager ARN lines allowed in ${el}s"
else
  FAIL=$((FAIL + 1)); echo "FAIL: 1MB timing case (rc=$rc, ${el}s)"
fi

echo "---"
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
