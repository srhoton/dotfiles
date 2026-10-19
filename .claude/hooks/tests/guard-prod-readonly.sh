#!/bin/bash
#
# Tests for hooks/guard-prod-readonly.sh. Synthetic inputs only.
# Usage: bash hooks/tests/guard-prod-readonly.sh
# Override the hook under test with HOOK=/path/to/copy.sh (used for mutation checks).

HOOK="${HOOK:-$(cd "$(dirname "$0")/.." && pwd)/guard-prod-readonly.sh}"
PROD="fb-live-us-prod/Admin"
DEV="fb-dev-non-prod/Admin"
DEMO="fb-demo-us-prod/Admin"
PASS=0
FAIL=0

json_bash() {
  CMD="$1" python3 -c 'import json,os;print(json.dumps({"tool_name":"Bash","tool_input":{"command":os.environ["CMD"]}}))'
}

# Real AWS MCP run_script tool names seen in session transcripts.
MCP_TOOL_A="mcp__claude_ai_AWS_MCP__aws___run_script"
MCP_TOOL_B="mcp__plugin_aws-data-analytics_aws-mcp__aws___run_script"

# json_mcp CODE [TOOL_NAME]
json_mcp() {
  CODE="$1" TOOL="${2:-$MCP_TOOL_A}" python3 -c 'import json,os;print(json.dumps({"tool_name":os.environ["TOOL"],"tool_input":{"code":os.environ["CODE"]}}))'
}

# check NAME EXPECTED_RC JSON [ENV_PROFILE]
check() {
  local name="$1" want="$2" json="$3" envprof="${4:-}" got err
  if [ -n "$envprof" ]; then
    err=$(printf '%s' "$json" | env -u AWS_DEFAULT_PROFILE AWS_PROFILE="$envprof" bash "$HOOK" 2>&1 >/dev/null)
  else
    err=$(printf '%s' "$json" | env -u AWS_PROFILE -u AWS_DEFAULT_PROFILE bash "$HOOK" 2>&1 >/dev/null)
  fi
  got=$?
  # $? above is the status of the assignment, i.e. of the pipeline's last command.
  if [ "$got" -eq "$want" ]; then
    PASS=$((PASS + 1))
    echo "PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $name (want exit $want, got $got) $err"
  fi
}

# bash_case NAME EXPECTED_RC COMMAND [ENV_PROFILE]
bash_case() { check "$1" "$2" "$(json_bash "$3")" "${4:-}"; }

# Prod: mutations blocked
bash_case "prod dynamodb put-item blocked" 2 "aws dynamodb put-item --table-name t --item '{}' --profile $PROD"
bash_case "prod dynamodb update-item blocked" 2 "aws dynamodb update-item --table-name t --profile $PROD"
bash_case "prod dynamodb delete-item blocked" 2 "aws dynamodb delete-item --table-name t --profile $PROD"
bash_case "prod dynamodb batch-write-item blocked" 2 "aws --profile $PROD dynamodb batch-write-item --request-items file://x.json"
bash_case "prod dynamodb transact-write-items blocked" 2 "aws dynamodb transact-write-items --profile=$PROD"
bash_case "prod stepfunctions start-execution blocked" 2 "aws stepfunctions start-execution --state-machine-arn arn:x --profile $PROD"
bash_case "prod stepfunctions redrive-execution blocked" 2 "aws stepfunctions redrive-execution --execution-arn arn:x --profile $PROD"
bash_case "prod stepfunctions stop-execution blocked" 2 "aws stepfunctions stop-execution --execution-arn arn:x --profile $PROD"
bash_case "prod lambda invoke blocked" 2 "aws lambda invoke --function-name f --profile $PROD /dev/stdout"
bash_case "prod sqs send-message blocked" 2 "aws sqs send-message --queue-url u --message-body b --profile $PROD"
bash_case "prod sqs purge-queue blocked" 2 "aws sqs purge-queue --queue-url u --profile $PROD"
bash_case "prod s3 rm blocked" 2 "aws s3 rm s3://bucket/key --profile $PROD"
bash_case "prod s3 mv blocked" 2 "aws s3 mv s3://bucket/a s3://bucket/b --profile $PROD"
bash_case "prod s3 cp local->s3 blocked" 2 "aws s3 cp ./file.txt s3://bucket/key --profile $PROD"
bash_case "prod s3 cp s3->s3 blocked" 2 "aws s3 cp s3://bucket/a s3://bucket/b --profile $PROD"
bash_case "prod s3 sync local->s3 blocked" 2 "aws s3 sync ./dir s3://bucket/p --profile $PROD"
bash_case "prod s3 cp stdin->s3 blocked" 2 "aws s3 cp - s3://bucket/key --profile $PROD"
bash_case "prod athena start-query-execution blocked" 2 "aws athena start-query-execution --profile $PROD"

# Prod: reads allowed
bash_case "prod dynamodb query allowed" 0 "aws dynamodb query --table-name t --profile $PROD"
bash_case "prod dynamodb scan allowed" 0 "aws dynamodb scan --table-name t --profile $PROD"
bash_case "prod dynamodb describe-table allowed" 0 "aws dynamodb describe-table --table-name t --profile $PROD"
bash_case "prod dynamodb batch-get-item allowed" 0 "aws dynamodb batch-get-item --profile $PROD --request-items file://x.json"
bash_case "prod stepfunctions list-executions allowed" 0 "aws stepfunctions list-executions --state-machine-arn arn:x --profile $PROD"
bash_case "prod sqs get-queue-attributes allowed" 0 "aws sqs get-queue-attributes --queue-url u --profile $PROD"
bash_case "prod logs filter-log-events allowed" 0 "aws logs filter-log-events --log-group-name g --profile $PROD"
bash_case "prod logs start-query allowed" 0 "aws logs start-query --log-group-name g --profile $PROD"
bash_case "prod logs get-query-results allowed" 0 "aws logs get-query-results --query-id q --profile $PROD"
bash_case "prod logs tail allowed" 0 "aws logs tail /aws/lambda/f --profile $PROD"
bash_case "prod sts get-caller-identity allowed" 0 "aws sts get-caller-identity --profile $PROD"
bash_case "prod s3 ls allowed" 0 "aws s3 ls s3://bucket/ --profile $PROD"
bash_case "prod s3api head-object allowed" 0 "aws s3api head-object --bucket b --key k --profile $PROD"
bash_case "prod s3 cp s3->local allowed" 0 "aws s3 cp s3://bucket/key ./out.txt --profile $PROD"
bash_case "prod s3 cp s3->stdout allowed" 0 "aws s3 cp s3://bucket/key - --profile $PROD"
bash_case "prod s3 sync s3->local allowed" 0 "aws s3 sync s3://bucket/p ./dir --exclude '*.tmp' --profile $PROD"
bash_case "prod sso login allowed" 0 "aws sso login --profile $PROD"
bash_case "prod configure allowed" 0 "aws configure list --profile $PROD"
bash_case "prod lambda invoke via --profile after op still blocked" 2 "aws --region us-east-1 lambda invoke --profile $PROD --function-name f out.json"

# Non-prod: mutations allowed
bash_case "dev dynamodb put-item allowed" 0 "aws dynamodb put-item --table-name t --profile $DEV"
bash_case "demo dynamodb put-item allowed (demo is not prod)" 0 "aws dynamodb put-item --table-name t --profile $DEMO"
bash_case "no profile at all put-item allowed" 0 "aws dynamodb put-item --table-name t"
bash_case "env dev profile put-item allowed" 0 "aws dynamodb put-item --table-name t" "$DEV"
bash_case "flag dev overrides env prod" 0 "aws dynamodb put-item --table-name t --profile $DEV" "$PROD"

# Profile sources
bash_case "env prod profile put-item blocked" 2 "aws dynamodb put-item --table-name t" "$PROD"
bash_case "env prod profile query allowed" 0 "aws dynamodb query --table-name t" "$PROD"
bash_case "inline AWS_PROFILE prod sqs send-message blocked" 2 "AWS_PROFILE=$PROD aws sqs send-message --queue-url u --message-body b"
bash_case "exported AWS_PROFILE prod then mutation blocked" 2 "export AWS_PROFILE=$PROD && aws sqs purge-queue --queue-url u"
bash_case "unset AWS_PROFILE clears prod env" 0 "unset AWS_PROFILE; aws sqs purge-queue --queue-url u" "$PROD"
bash_case "env wrapper prod mutation blocked" 2 "env AWS_PROFILE=$PROD aws sqs purge-queue --queue-url u"
bash_case "bash -c prod mutation blocked" 2 "bash -c \"aws --profile $PROD lambda invoke --function-name f o.json\""
bash_case "chain: get-caller-identity && prod lambda invoke blocked" 2 "aws sts get-caller-identity && aws --profile $PROD lambda invoke --function-name f out.json"
bash_case "chain: prod describe ; prod put-item blocked" 2 "aws --profile $PROD dynamodb describe-table --table-name t; aws --profile $PROD dynamodb put-item --table-name t"
bash_case "pipe: prod reads allowed" 0 "aws dynamodb scan --table-name t --profile $PROD | jq . && aws sts get-caller-identity --profile $PROD"
bash_case "newline separated prod mutation blocked" 2 "echo hi
aws sqs purge-queue --queue-url u --profile $PROD"
bash_case "non-aws command mentioning prod mutation blocked by backstop (known false positive, cannot tell echo from eval)" 2 "echo aws dynamodb put-item --profile $PROD"
bash_case "git commit message mentioning prod mutation blocked by backstop (known false positive)" 2 "git commit -m 'aws lambda invoke --profile $PROD'"
bash_case "git commit message mentioning aws without prod literal ignored" 0 "git commit -m 'aws lambda invoke'"
bash_case "non-aws command ignored" 0 "ls -la"

# Wrappers: structural path skips their value args (reads pass, mutations blocked)
bash_case "timeout wrapper prod put-item blocked" 2 "timeout 60 aws --profile $PROD dynamodb put-item --table-name t --item '{}'"
bash_case "timeout -k wrapper prod put-item blocked" 2 "timeout -k 5 60 aws --profile $PROD dynamodb put-item --table-name t"
bash_case "timeout wrapper prod describe-table allowed" 0 "timeout 60 aws --profile $PROD dynamodb describe-table --table-name t"
bash_case "xargs -I wrapper prod put-item blocked" 2 "echo t | xargs -I X aws --profile $PROD dynamodb put-item --table-name X"
bash_case "xargs -n wrapper prod purge-queue blocked" 2 "echo u | xargs -n 1 aws --profile $PROD sqs purge-queue --queue-url"
bash_case "xargs -L wrapper prod purge-queue blocked" 2 "echo u | xargs -L 1 aws --profile $PROD sqs purge-queue --queue-url"
bash_case "xargs -I wrapper prod describe-table allowed" 0 "echo t | xargs -I X aws --profile $PROD dynamodb describe-table --table-name X"
bash_case "nice -n wrapper prod put-item blocked" 2 "nice -n 5 aws --profile $PROD dynamodb put-item --table-name t"
bash_case "nice -n wrapper env prod put-item blocked" 2 "nice -n 5 aws dynamodb put-item --table-name t" "$PROD"
bash_case "env -u wrapper prod put-item blocked" 2 "env -u FOO aws --profile $PROD dynamodb put-item --table-name t"
bash_case "env -u wrapper env prod put-item blocked" 2 "env -u FOO aws dynamodb put-item --table-name t" "$PROD"
bash_case "sudo -u wrapper prod put-item blocked" 2 "sudo -u root aws --profile $PROD dynamodb put-item --table-name t"
bash_case "sudo -u wrapper env prod put-item blocked" 2 "sudo -u root aws dynamodb put-item --table-name t" "$PROD"
bash_case "stdbuf -oL wrapper prod put-item blocked" 2 "stdbuf -oL aws --profile $PROD dynamodb put-item --table-name t"
bash_case "stdbuf -o L wrapper env prod put-item blocked" 2 "stdbuf -o L aws dynamodb put-item --table-name t" "$PROD"
bash_case "watch -n wrapper prod put-item blocked" 2 "watch -n 5 aws --profile $PROD dynamodb put-item --table-name t"
bash_case "watch quoted command prod put-item blocked" 2 "watch -n 5 'aws --profile $PROD dynamodb put-item --table-name t'"
bash_case "nohup wrapper prod put-item blocked" 2 "nohup aws --profile $PROD dynamodb put-item --table-name t"
bash_case "mise exec -- wrapper prod put-item blocked" 2 "mise exec -- aws --profile $PROD dynamodb put-item --table-name t"
bash_case "mise exec tool -- wrapper env prod put-item blocked" 2 "mise exec awscli@2 -- aws dynamodb put-item --table-name t" "$PROD"
bash_case "uv run wrapper prod put-item blocked" 2 "uv run aws --profile $PROD dynamodb put-item --table-name t"
bash_case "uv run --with wrapper env prod put-item blocked" 2 "uv run --with boto3 aws dynamodb put-item --table-name t" "$PROD"
bash_case "eval prod put-item blocked" 2 "eval \"aws --profile $PROD dynamodb put-item --table-name t\""
bash_case "eval env prod put-item blocked" 2 "eval 'aws dynamodb put-item --table-name t'" "$PROD"
bash_case "wrapped chain: timeout read && timeout mutation blocked" 2 "timeout 5 aws --profile $PROD dynamodb scan --table-name t && timeout 5 aws --profile $PROD sqs purge-queue --queue-url u"

# Indirect profiles
bash_case "indirect: P=prod; aws --profile \$P put-item blocked" 2 "P=$PROD; aws --profile \$P dynamodb put-item --table-name t"
bash_case "indirect: --profile \${P} blocked" 2 "P=$PROD; aws --profile \${P} dynamodb put-item --table-name t"
bash_case "indirect: --profile=\$P blocked" 2 "P=$PROD; aws --profile=\$P dynamodb put-item --table-name t"
bash_case "indirect: export AWS_PROFILE=\$P blocked" 2 "P=$PROD; export AWS_PROFILE=\$P; aws dynamodb put-item --table-name t"
bash_case "indirect: AWS_PROFILE=\$P inline blocked" 2 "P=$PROD; AWS_PROFILE=\$P aws dynamodb put-item --table-name t"
bash_case "indirect: \${AWS_PROFILE:-prod} default blocked" 2 "aws --profile \${AWS_PROFILE:-$PROD} dynamodb put-item --table-name t"
bash_case "indirect: \${AWS_PROFILE:-prod} with dev env resolves to dev but prod is named: mutation blocked (P1 ignores profile resolution)" 2 "aws --profile \${AWS_PROFILE:-$PROD} dynamodb put-item --table-name t" "$DEV"
bash_case "indirect: \${AWS_PROFILE:-prod} with dev env resolves to dev, read allowed" 0 "aws --profile \${AWS_PROFILE:-$PROD} dynamodb scan --table-name t" "$DEV"
bash_case "indirect: \$P from dev assignment allowed" 0 "P=$DEV; aws --profile \$P dynamodb put-item --table-name t"
bash_case "indirect: \$P read allowed" 0 "P=$PROD; aws --profile \$P dynamodb query --table-name t"

# Raw-text backstop: parse failure and unparseable heredocs
HEREDOC_APOS="cat > /tmp/n.txt <<EOF
we don't care
EOF"
bash_case "heredoc with apostrophe then prod delete-item blocked" 2 "$HEREDOC_APOS
aws --profile $PROD dynamodb delete-item --table-name t --key '{}'"
bash_case "heredoc with apostrophe then prod put-item blocked" 2 "$HEREDOC_APOS
aws --profile $PROD dynamodb put-item --table-name t"
bash_case "heredoc with apostrophe then prod describe-table allowed" 0 "$HEREDOC_APOS
aws --profile $PROD dynamodb describe-table --table-name t"
bash_case "heredoc with apostrophe then prod query allowed" 0 "$HEREDOC_APOS
aws --profile $PROD dynamodb query --table-name t"
bash_case "heredoc with apostrophe then dev put-item allowed" 0 "$HEREDOC_APOS
aws --profile $DEV dynamodb put-item --table-name t"
bash_case "heredoc with apostrophe, env prod put-item blocked" 2 "$HEREDOC_APOS
aws dynamodb put-item --table-name t" "$PROD"
bash_case "heredoc with apostrophe then secret read blocked" 2 "$HEREDOC_APOS
aws secretsmanager get-secret-value --secret-id s"
bash_case "heredoc with apostrophe then prod s3 cp upload blocked" 2 "$HEREDOC_APOS
aws --profile $PROD s3 cp ./f s3://b/k"
bash_case "heredoc with apostrophe then prod s3 cp download allowed" 0 "$HEREDOC_APOS
aws --profile $PROD s3 cp s3://b/k ./k"
bash_case "heredoc with apostrophe then prod terraform apply blocked" 2 "$HEREDOC_APOS
AWS_PROFILE=$PROD terraform apply"
bash_case "unparseable quotes with prod mutation blocked" 2 "echo 'oops; aws --profile $PROD dynamodb put-item --table-name t"

# Backstop reads: must keep passing (literal prod in text, read-only operations)
bash_case "prod dynamodb query ... pipeline allowed" 0 "aws --profile $PROD dynamodb query --table-name t --key-condition-expression 'pk = :p' | jq ."
bash_case "prod logs filter-log-events with --start-time allowed" 0 "aws --profile $PROD logs filter-log-events --log-group-name g --start-time 1700000000000"
bash_case "prod s3 cp s3->local allowed (backstop)" 0 "aws --profile $PROD s3 cp s3://b/k ./k"
bash_case "timeout prod logs start-query allowed" 0 "timeout 60 aws --profile $PROD logs start-query --log-group-name g"
bash_case "timeout prod s3 cp s3->local allowed" 0 "timeout 60 aws --profile $PROD s3 cp s3://b/k ./k"
bash_case "timeout prod s3 sync s3->local with --exclude allowed" 0 "timeout 60 aws --profile $PROD s3 sync s3://b/p ./d --exclude '*.tmp'"
bash_case "timeout prod s3 cp upload blocked" 2 "timeout 60 aws --profile $PROD s3 cp ./f s3://b/k"
bash_case "timeout prod s3 rm blocked" 2 "timeout 60 aws --profile $PROD s3 rm s3://b/k"
bash_case "timeout prod s3 mv blocked" 2 "timeout 60 aws --profile $PROD s3 mv s3://b/a ./a"
bash_case "grep for get-secret-value in files allowed" 0 "grep -rn get-secret-value hooks/"
bash_case "grep for secretsmanager piped to grep get-secret-value blocked (P2 is order-independent: known false positive)" 2 "grep -rn secretsmanager hooks/ | grep get-secret-value"
bash_case "grep -r secretsmanager only allowed" 0 "grep -rn secretsmanager hooks/"

# Secrets: blocked on every profile
bash_case "get-secret-value blocked on dev" 2 "aws secretsmanager get-secret-value --secret-id s --profile $DEV"
bash_case "get-secret-value blocked with no profile" 2 "aws secretsmanager get-secret-value --secret-id s"
bash_case "get-secret-value blocked on prod" 2 "aws secretsmanager get-secret-value --secret-id s --profile $PROD"
bash_case "batch-get-secret-value blocked on dev" 2 "aws secretsmanager batch-get-secret-value --secret-id-list a --profile $DEV"
bash_case "get-secret-value in chain blocked" 2 "echo x && aws --region us-east-1 secretsmanager get-secret-value --secret-id s"
bash_case "secretsmanager list-secrets allowed on dev" 0 "aws secretsmanager list-secrets --profile $DEV"
bash_case "secretsmanager describe-secret allowed on prod" 0 "aws secretsmanager describe-secret --secret-id s --profile $PROD"
bash_case "unparseable quotes with secret read still blocked" 2 "aws secretsmanager get-secret-value --secret-id 's"
bash_case "unparseable quotes otherwise allowed" 0 "echo 'unterminated"
bash_case "timeout wrapped get-secret-value blocked" 2 "timeout 5 aws secretsmanager get-secret-value --secret-id s"
bash_case "eval wrapped get-secret-value blocked" 2 "eval \"aws secretsmanager get-secret-value --secret-id s\""
bash_case "xargs wrapped batch-get-secret-value blocked" 2 "echo a | xargs -n 1 aws secretsmanager batch-get-secret-value --secret-id-list"
bash_case "uppercase secret op blocked by backstop" 2 "timeout 5 AWS SecretsManager GET-SECRET-VALUE --secret-id s"

# Terraform
bash_case "terraform apply with prod env blocked" 2 "terraform apply -auto-approve" "$PROD"
bash_case "terraform destroy with prod env blocked" 2 "terraform destroy" "$PROD"
bash_case "terraform -chdir apply with prod env blocked" 2 "terraform -chdir=infra apply" "$PROD"
bash_case "terraform apply with inline prod profile blocked" 2 "AWS_PROFILE=$PROD terraform apply"
bash_case "terraform apply with exported prod profile blocked" 2 "export AWS_PROFILE=$PROD && terraform -chdir=x apply -auto-approve"
bash_case "terraform plan with prod env allowed" 0 "terraform plan" "$PROD"
bash_case "terraform -chdir plan with prod env allowed" 0 "terraform -chdir=infra plan -out=p" "$PROD"
bash_case "terraform state rm with prod env blocked" 2 "terraform state rm aws_s3_bucket.b" "$PROD"
bash_case "terraform state mv with prod env blocked" 2 "terraform state mv a b" "$PROD"
bash_case "terraform import with prod env blocked" 2 "terraform import aws_s3_bucket.b my-bucket" "$PROD"
bash_case "terraform taint with prod env blocked" 2 "terraform taint aws_s3_bucket.b" "$PROD"
bash_case "terraform untaint with prod env blocked" 2 "terraform untaint aws_s3_bucket.b" "$PROD"
bash_case "terraform force-unlock with prod env blocked" 2 "terraform force-unlock abc-123" "$PROD"
bash_case "terraform refresh with prod env blocked" 2 "terraform refresh" "$PROD"
bash_case "terraform workspace select with prod env blocked" 2 "terraform workspace select x" "$PROD"
bash_case "terraform bare state with prod env blocked" 2 "terraform state" "$PROD"
bash_case "tofu import with prod env blocked" 2 "tofu import aws_s3_bucket.b my-bucket" "$PROD"
bash_case "terraform -chdir state rm with prod env blocked" 2 "terraform -chdir=infra state rm aws_s3_bucket.b" "$PROD"
bash_case "terraform import with inline prod profile blocked" 2 "AWS_PROFILE=$PROD terraform import a b"
bash_case "timeout terraform import with prod env blocked" 2 "timeout 60 terraform import a b" "$PROD"
bash_case "timeout terraform apply with literal prod profile blocked" 2 "timeout 60 env AWS_PROFILE=$PROD terraform apply"
bash_case "terraform state list with prod env allowed" 0 "terraform state list" "$PROD"
bash_case "terraform state show with prod env allowed" 0 "terraform state show aws_s3_bucket.b" "$PROD"
bash_case "terraform state pull with prod env allowed" 0 "terraform state pull" "$PROD"
bash_case "terraform -chdir state list with prod env allowed" 0 "terraform -chdir=infra state list" "$PROD"
for sub in plan show output validate fmt init providers version graph console; do
  bash_case "terraform $sub with prod env allowed" 0 "terraform $sub" "$PROD"
done
bash_case "terraform -version with prod env allowed" 0 "terraform -version" "$PROD"
bash_case "timeout terraform plan with prod env allowed" 0 "timeout 60 terraform plan -out=p" "$PROD"
bash_case "terraform import with dev env allowed" 0 "terraform import a b" "$DEV"
bash_case "terraform state rm with dev env allowed" 0 "terraform state rm a" "$DEV"
bash_case "terraform apply with dev env allowed" 0 "terraform apply" "$DEV"
bash_case "terraform apply with demo env allowed" 0 "terraform apply" "$DEMO"
bash_case "terraform apply with no profile allowed" 0 "terraform apply"

BT='`'

# H1: a clean structural verdict is trusted even when the prod literal is in the
# text, and the raw-text backstop judges only the service/op position (never
# resource names, ARNs, query strings or redirect targets). Synthetic account.
READS=(
  "aws --profile $PROD logs filter-log-events --log-group-name /aws/lambda/send-invoice-email"
  "aws --profile $PROD stepfunctions get-execution-history --execution-arn arn:aws:states:us-east-1:111111111111:execution:mig-sfn:start-run-1"
  "aws --profile $PROD dynamodb scan --table-name t > /tmp/update-check.json"
  "aws --profile $PROD logs start-query --log-group-name g --query-string 'fields @message | filter @message like /update-order/'"
  "aws --profile $PROD lambda get-function --function-name create-order-handler"
  "aws --profile $PROD stepfunctions list-executions --state-machine-arn arn:aws:states:us-east-1:111111111111:stateMachine:redrive-handler"
  "aws --profile $PROD lambda list-functions --query 'Functions[?contains(FunctionName, ${BT}update-${BT})]'"
  "aws --profile $PROD s3 ls s3://b/delete-me/"
  "aws --no-cli-pager --region us-east-1 --profile $PROD dynamodb query --table-name delete-me --index-name update-idx"
  "aws --profile $PROD s3 cp s3://b/create-me/k ./update-k.txt"
)
i=0
for c in "${READS[@]}"; do
  i=$((i + 1))
  bash_case "H1 prod read #$i with verb-prefixed values allowed (structural verdict trusted)" 0 "$c"
  bash_case "H1 prod read #$i with verb-prefixed values allowed (backstop judges op position only)" 0 "$HEREDOC_APOS
$c"
done
MUTS=(
  "aws --profile $PROD lambda invoke --function-name update-order out.json"
  "aws --profile $PROD dynamodb put-item --table-name delete-me --item '{}'"
  "aws --no-cli-pager --profile $PROD sqs purge-queue --queue-url u"
  "aws --debug --region us-east-1 --profile $PROD sqs purge-queue --queue-url u"
  "aws --no-sign-request --no-verify-ssl --no-paginate --profile $PROD sqs purge-queue --queue-url u"
  "aws --foo --profile $PROD sqs purge-queue --queue-url u"
  "aws --foo s3 rm s3://b/k --profile $PROD"
  "aws --profile $PROD lambda --region us-east-1 invoke --function-name f o.json"
  "aws --profile $PROD s3 --region us-east-1 rm s3://b/k"
  "aws --profile $PROD dynamodb put-item --table-name t > /tmp/update-check.json"
  "aws --profile $PROD sqs send-message --queue-url u --message-body b 2>&1"
  "aws --profile $PROD s3 cp ./f s3://b/k --only-show-errors"
  "aws --profile $PROD s3 sync ./d s3://b/p --exclude '*.tmp'"
  "aws --profile $PROD logs start-query --log-group-name g && aws --profile $PROD sqs purge-queue --queue-url u"
)
i=0
for c in "${MUTS[@]}"; do
  i=$((i + 1))
  bash_case "H1 prod mutation #$i blocked (structural)" 2 "$c"
  bash_case "H1 prod mutation #$i blocked (backstop)" 2 "$HEREDOC_APOS
$c"
done
bash_case "H1 env prod: read with mutating-looking table name allowed" 0 "aws dynamodb scan --table-name update-check" "$PROD"
bash_case "H1 env prod: put-item still blocked" 2 "aws dynamodb put-item --table-name update-check" "$PROD"
# Trust is limited to words the structural pass actually examined.
bash_case "H1 trust: unrecognised wrapper (parallel) prod mutation blocked" 2 "echo u | parallel aws --profile $PROD sqs purge-queue --queue-url {}"
bash_case "H1 trust: ssh-wrapped prod mutation blocked" 2 "ssh host aws --profile $PROD sqs purge-queue --queue-url u"
bash_case "H1 trust: find -exec prod mutation blocked" 2 "find . -name x -exec aws --profile $PROD dynamodb put-item --table-name t {} +"
bash_case "H1 trust: uppercase AWS prod mutation blocked" 2 "AWS --profile $PROD dynamodb put-item --table-name t"
bash_case "H1 trust: uppercase AWS prod read allowed" 0 "AWS --profile $PROD dynamodb scan --table-name t"
bash_case "H1 trust: read then echo of aws mutation text blocked (unexamined aws word)" 2 "aws --profile $PROD dynamodb scan --table-name t && echo aws sqs purge-queue"

# #1/#8: profiles from command substitution / unset variables are unknown.
UNK_BLOCKED=(
  "aws --profile \"fb-live-us-\$(echo prod)/Admin\" sqs purge-queue --queue-url q"
  "aws --profile fb-live-us-\$(echo prod)/Admin sqs purge-queue --queue-url q"
  "aws --profile \$(cat /tmp/p) sqs purge-queue --queue-url q"
  "aws --profile \"\$(cat /tmp/p)\" dynamodb delete-item --table-name t"
  "aws --profile ${BT}cat /tmp/p${BT} sqs purge-queue --queue-url q"
  "aws --profile=\$(cat /tmp/p) sqs purge-queue --queue-url q"
  "aws --profile \$(echo \$(cat /tmp/p)) sqs purge-queue --queue-url q"
  "aws --profile \$(cat /tmp/p) s3 cp ./f s3://b/k"
  "aws --profile \$(cat /tmp/p) s3 rm s3://b/k"
  "aws --profile \$GUARD_TEST_UNSET_VAR dynamodb put-item --table-name t"
  "AWS_PROFILE=\$(cat /tmp/p) aws sqs purge-queue --queue-url q"
  "AWS_PROFILE=\"\$(cat /tmp/p)\" aws sqs purge-queue --queue-url q"
  "AWS_PROFILE=${BT}cat /tmp/p${BT} aws sqs purge-queue --queue-url q"
  "AWS_DEFAULT_PROFILE=\$(cat /tmp/p) aws sqs purge-queue --queue-url q"
  "AWS_PROFILE=\$GUARD_TEST_UNSET_VAR aws sqs purge-queue --queue-url q"
  "export AWS_PROFILE=\$(cat /tmp/p) && aws sqs purge-queue --queue-url q"
  "env AWS_PROFILE=\$(cat /tmp/p) aws sqs purge-queue --queue-url q"
  "P=\$(cat /tmp/p); aws --profile \$P sqs purge-queue --queue-url q"
  "AWS_PROFILE=\$(cat /tmp/p) terraform apply"
  "export AWS_PROFILE=\$(cat /tmp/p); tofu destroy"
)
i=0
for c in "${UNK_BLOCKED[@]}"; do
  i=$((i + 1))
  bash_case "unknown profile #$i mutation blocked" 2 "$c"
done
UNK_ALLOWED=(
  "aws --profile \$(cat /tmp/p) dynamodb scan --table-name t"
  "aws --profile \"\$(cat /tmp/p)\" logs start-query --log-group-name g --query-string 'x'"
  "aws --profile \$(cat /tmp/p) s3 ls s3://b/"
  "aws --profile \$(cat /tmp/p) s3 cp s3://b/k ./k"
  "aws --profile \$(cat /tmp/p) lambda get-function --function-name update-handler"
  "aws --profile \$GUARD_TEST_UNSET_VAR dynamodb scan --table-name t"
  "AWS_PROFILE=\$(cat /tmp/p) aws dynamodb query --table-name t"
  "AWS_PROFILE=\$(cat /tmp/p) terraform plan"
  "aws --profile $DEV dynamodb put-item --table-name \"\$(cat /tmp/t)\""
  "aws --profile $DEV dynamodb put-item --table-name t --item \$(cat /tmp/i)"
)
i=0
for c in "${UNK_ALLOWED[@]}"; do
  i=$((i + 1))
  bash_case "unknown profile #$i read (or dev profile with substitution elsewhere) allowed" 0 "$c"
done
bash_case "loop variable as profile: mutation blocked" 2 "for p in x y; do aws --profile \$p sqs purge-queue --queue-url u; done"
bash_case "loop variable as profile: read allowed" 0 "for p in x y; do aws --profile \$p dynamodb scan --table-name t; done"
bash_case "loop variable as table name on prod: read allowed" 0 "for t in a b; do aws --profile $PROD dynamodb scan --table-name \$t; done"
# Same class when the structural layer cannot parse the text.
bash_case "unparseable text + --profile \$(..) mutation blocked" 2 "$HEREDOC_APOS
aws --profile \$(cat /tmp/p) sqs purge-queue --queue-url q"
bash_case "unparseable text + AWS_PROFILE=\$P terraform apply blocked" 2 "$HEREDOC_APOS
AWS_PROFILE=\$P terraform apply"
bash_case "unparseable text + --profile \$(..) read allowed" 0 "$HEREDOC_APOS
aws --profile \$(cat /tmp/p) dynamodb scan --table-name t"

# #2: service/op through a variable or substitution.
SECRET_VAR_BLOCKED=(
  "S=secretsmanager; aws \$S get-secret-value --secret-id x"
  "S=secretsmanager; G=get-secret-value; aws \"\$S\" \"\$G\" --secret-id x"
  "S=secretsmanager; aws \${S} batch-get-secret-value --secret-id-list a"
  "aws \$GUARD_TEST_UNSET_VAR get-secret-value --secret-id x"
  "aws secretsmanager \$GUARD_TEST_UNSET_VAR --secret-id x"
  "aws \$GUARD_TEST_UNSET_VAR \$GUARD_TEST_UNSET_OP --secret-id x"
  "S=\$(echo secretsmanager); aws \$S get-secret-value --secret-id x"
  "aws \$(echo secretsmanager) get-secret-value --secret-id x"
  "aws secretsmanager \$(echo get-secret-value) --secret-id x"
  "aws \"\$(echo secretsmanager)\" \"\$(echo get-secret-value)\" --secret-id x"
  "aws ${BT}echo secretsmanager${BT} get-secret-value --secret-id x"
  "aws --profile $DEV \$GUARD_TEST_UNSET_VAR get-secret-value --secret-id x"
  "aws --profile $PROD \$GUARD_TEST_UNSET_VAR get-secret-value --secret-id x"
)
i=0
for c in "${SECRET_VAR_BLOCKED[@]}"; do
  i=$((i + 1))
  bash_case "secret via variable #$i blocked (structural)" 2 "$c"
done
bash_case "secret via variable blocked (backstop: unparseable text, unset service)" 2 "$HEREDOC_APOS
aws \$S get-secret-value --secret-id x"
bash_case "secret via variable blocked (backstop: both quoted variables)" 2 "$HEREDOC_APOS
aws \"\$S\" \"\$G\" --secret-id x"
bash_case "secret via variable blocked (backstop: unset op)" 2 "$HEREDOC_APOS
aws secretsmanager \$G --secret-id x"
bash_case "secret via variable blocked (backstop: assignment before aws)" 2 "$HEREDOC_APOS
S=secretsmanager; aws \$S get-secret-value --secret-id x"
bash_case "variable service + non-secret op allowed (dev, no profile)" 0 "aws \$GUARD_TEST_UNSET_VAR describe-secret --secret-id x"
bash_case "variable op + non-secret service allowed (dev profile)" 0 "aws --profile $DEV dynamodb \$GUARD_TEST_UNSET_VAR --table-name t"
bash_case "resolved variable service secretsmanager + list-secrets allowed" 0 "S=secretsmanager; aws \$S list-secrets"
bash_case "variable service allowed (backstop, unparseable text, no prod context)" 0 "$HEREDOC_APOS
aws \$S describe-secret --secret-id x"
bash_case "prod: variable service blocked" 2 "aws --profile $PROD \$GUARD_TEST_UNSET_VAR describe-table --table-name t"
bash_case "prod: variable op blocked" 2 "aws --profile $PROD dynamodb \$GUARD_TEST_UNSET_VAR --table-name t"
bash_case "prod: variable op via substitution blocked" 2 "aws --profile $PROD dynamodb \$(echo scan) --table-name t"
bash_case "prod: variable that resolves to a read allowed" 0 "S=dynamodb; O=scan; aws --profile $PROD \$S \$O --table-name t"
bash_case "prod: variable that resolves to a mutation blocked" 2 "S=dynamodb; O=put-item; aws --profile $PROD \$S \$O --table-name t"
bash_case "env prod: variable op blocked" 2 "aws dynamodb \$GUARD_TEST_UNSET_VAR --table-name t" "$PROD"
bash_case "unknown profile + variable op blocked" 2 "aws --profile \$(cat /tmp/p) dynamodb \$GUARD_TEST_UNSET_VAR --table-name t"

# #10: terraform init flags that copy or overwrite remote state, under prod.
for f in -migrate-state -force-copy -reconfigure; do
  bash_case "terraform init $f with prod env blocked" 2 "terraform init $f" "$PROD"
  bash_case "terraform -chdir init $f -input=false with prod env blocked" 2 "terraform -chdir=infra init $f -input=false" "$PROD"
  bash_case "tofu init $f with inline prod profile blocked" 2 "AWS_PROFILE=$PROD tofu init $f"
  bash_case "terraform init $f with dev env allowed" 0 "terraform init $f" "$DEV"
  bash_case "terraform init $f with prod env blocked (backstop)" 2 "$HEREDOC_APOS
terraform init $f" "$PROD"
  bash_case "terraform -chdir init $f with prod literal blocked (backstop)" 2 "$HEREDOC_APOS
AWS_PROFILE=$PROD terraform -chdir=infra init -input=false $f"
done
bash_case "terraform init --migrate-state=true with prod env blocked" 2 "terraform init --migrate-state=true" "$PROD"
bash_case "terraform init -backend-config -upgrade with prod env allowed" 0 "terraform init -backend-config=x.hcl -upgrade" "$PROD"
bash_case "terraform init -upgrade with prod literal allowed (backstop)" 0 "$HEREDOC_APOS
AWS_PROFILE=$PROD terraform init -upgrade"
bash_case "terraform init; echo -reconfigure allowed (flag after separator, backstop)" 0 "$HEREDOC_APOS
AWS_PROFILE=$PROD terraform init -upgrade; echo -reconfigure"

# ---- Round 3: the "trusted structural verdict" shortcut -----------------------
# P1: when the text names prod, the resolved profile is not trusted: every aws /
# terraform invocation must be a read. P2: get-secret-value next to secretsmanager,
# an aws word, a wrapper or an indirect command word, in any order. P3: the
# env-profile path (no prod literal) models `env -u/-i` and abbreviated options.
# Synthetic values only.

# [1] abbreviated --profile (argparse prefix), hook env is dev.
bash_case "R3#1 --prof prod put-item blocked" 2 "aws --prof $PROD dynamodb put-item --table-name t" "$DEV"
bash_case "R3#1 --pro=prod purge-queue blocked" 2 "aws --pro=$PROD sqs purge-queue --queue-url x" "$DEV"
bash_case "R3#1 trailing --profil prod put-item blocked" 2 "aws dynamodb put-item --table-name t --profil $PROD" "$DEV"
bash_case "R3#1 --profi prod put-item blocked (no hook env)" 2 "aws --profi $PROD dynamodb put-item --table-name t"
bash_case "R3#1 --p prod put-item blocked" 2 "aws --p $PROD dynamodb put-item --table-name t" "$DEV"
bash_case "R3#1 unparseable text + abbreviated --prof \$(..) put-item blocked (backstop)" 2 "$HEREDOC_APOS
aws --prof \$(cat /tmp/p) dynamodb put-item --table-name t" "$DEV"
bash_case "R3#1 unparseable text + abbreviated --prof \$(..) read allowed (backstop)" 0 "$HEREDOC_APOS
aws --prof \$(cat /tmp/p) dynamodb scan --table-name t" "$DEV"
bash_case "R3#1 abbreviated --prof prod read allowed" 0 "aws --prof $PROD dynamodb scan --table-name t" "$DEV"
bash_case "R3#1 abbreviated --prof prod put-item blocked (backstop)" 2 "$HEREDOC_APOS
aws --prof $PROD dynamodb put-item --table-name t" "$DEV"
bash_case "R3#1 abbreviated --profil before op, prod put-item blocked (backstop)" 2 "$HEREDOC_APOS
aws --no-cli-p --profil $PROD dynamodb put-item --table-name t" "$DEV"
# P3 only (no prod literal in the text): the abbreviation must resolve to the profile.
bash_case "R3#1 P3: --prof resolving to prod via variable, put-item blocked" 2 "P=fb-live-; aws --prof \${P}us-prod/Admin dynamodb put-item --table-name t" "$DEV"
bash_case "R3#1 P3: --pro= resolving to prod via variable, purge-queue blocked" 2 "P=fb-live-; aws --pro=\${P}us-prod/Admin sqs purge-queue --queue-url q" "$DEV"
bash_case "R3#1 P3: --prof dev overrides hook-env prod (allowed)" 0 "aws --prof $DEV dynamodb put-item --table-name t" "$PROD"
bash_case "R3#1 P3: --prof dev, value option skipped, op position kept" 0 "aws --regi us-east-1 --prof $DEV dynamodb put-item --table-name t" "$PROD"
bash_case "R3#1 P3: abbreviated --regi value does not shift the op (prod put-item blocked)" 2 "aws --regi us-east-1 dynamodb put-item --table-name t" "$PROD"

# [2] arguments appended by xargs / parallel / find -exec.
bash_case "R3#2 xargs supplies service+op, prod flag: blocked" 2 "echo dynamodb put-item --table-name t | xargs aws --profile $PROD" "$DEV"
bash_case "R3#2 xargs supplies service+op, prod literal on stdin side, dev profile: blocked (P1)" 2 "echo \"dynamodb put-item --profile $PROD\" | xargs aws" "$DEV"
bash_case "R3#2 xargs supplies op only, prod flag: blocked" 2 "echo put-item | xargs aws --profile $PROD dynamodb --table-name t" "$DEV"
bash_case "R3#2 xargs -I replace string as op, prod flag: blocked" 2 "printf 'put-item\n' | xargs -I{} aws --profile $PROD dynamodb {} --table-name t" "$DEV"
bash_case "R3#2 xargs -I OP custom replace string as op, prod flag: blocked" 2 "echo purge-queue | xargs -I OP aws --profile $PROD sqs OP --queue-url q" "$DEV"
bash_case "R3#2 xargs missing op, hook env prod, no literal: blocked" 2 "echo put-item | xargs aws dynamodb --table-name t" "$PROD"
bash_case "R3#2 xargs missing service+op, hook env prod, no literal: blocked" 2 "echo dynamodb put-item | xargs aws" "$PROD"
bash_case "R3#2 parallel supplies service+op, prod flag: blocked" 2 "echo dynamodb put-item | parallel aws --profile $PROD" "$DEV"
bash_case "R3#2 find -exec supplies service, prod flag: blocked" 2 "find . -name x -exec aws --profile $PROD {} put-item +" "$DEV"
bash_case "R3#2 xargs complete read on prod still allowed" 0 "echo t | xargs -I X aws --profile $PROD dynamodb describe-table --table-name X" "$DEV"
bash_case "R3#2 xargs supplying args on a dev profile, no prod named: allowed (non-prod mutation)" 0 "echo dynamodb put-item | xargs aws --profile $DEV" "$DEV"
bash_case "R3#2 secret: stdin op, literal secretsmanager service" 2 "echo get-secret-value --secret-id x | xargs aws secretsmanager" "$DEV"
bash_case "R3#2 secret: stdin service+op" 2 "echo secretsmanager get-secret-value --secret-id x | xargs aws"
bash_case "R3#2 secret: xargs -I{} replace string as op" 2 "printf 'get-secret-value\n' | xargs -I{} aws secretsmanager {} --secret-id x"
bash_case "R3#2 secret: xargs -I{} replace string as service" 2 "echo secretsmanager | xargs -I{} aws {} get-secret-value --secret-id x"
bash_case "R3#2 secret: stdin op from a file (no secret text), secretsmanager service" 2 "xargs aws secretsmanager < ops.txt"
bash_case "R3#2 secret: replace-string op from a file" 2 "xargs -I{} aws secretsmanager {} --secret-id x < ops.txt"
bash_case "R3#2 secret: custom replace string op from a file" 2 "xargs -I OP aws secretsmanager OP < ops.txt"
bash_case "R3#2 secret: replace-string service, secret op, from a file" 2 "xargs -I SVC aws SVC get-secret-value --secret-id x < svc.txt"
bash_case "R3#2 secret: parallel {} op" 2 "parallel aws secretsmanager {} ::: x"
bash_case "R3#2 secret: find -exec both terms" 2 "find . -name ops -exec echo secretsmanager get-secret-value \\; | sh"
bash_case "R3#2 secret: uppercase words" 2 "echo SECRETSMANAGER GET-SECRET-VALUE | XARGS AWS"
bash_case "R3#2 secret: awscli word" 2 "echo get-secret-value | awscli secretsmanager"
bash_case "R3#2 secret: batch-get-secret-value via xargs" 2 "echo batch-get-secret-value | xargs aws secretsmanager"
bash_case "R3#2 secret: op literal, service from stdin, with a profile" 2 "echo secretsmanager | xargs -I{} aws --profile $DEV {} get-secret-value --secret-id x"
bash_case "R3#2 secret: replace-string op after secretsmanager blocked even for a harmless stdin (conservative)" 2 "echo describe-secret | xargs -I{} aws secretsmanager {} --secret-id x"
bash_case "R3#2 xargs replace string only in an argument of a literal non-secret op allowed" 0 "echo x | xargs -I{} aws secretsmanager describe-secret --secret-id {}"
bash_case "R3#2 get-secret-value text without aws/secretsmanager/wrapper allowed" 0 "echo get-secret-value | grep secret"

# [3] aws reached through a variable or a command substitution.
bash_case "R3#3 \${AWS_BIN:-aws} prod put-item blocked" 2 "\${AWS_BIN:-aws} dynamodb put-item --table-name t --profile $PROD"
bash_case "R3#3 \$(which aws) prod put-item blocked" 2 "\$(which aws) dynamodb put-item --table-name t --profile $PROD"
bash_case "R3#3 \"\$(command -v aws)\" prod put-item blocked" 2 "\"\$(command -v aws)\" dynamodb put-item --table-name t --profile $PROD"
bash_case "R3#3 A=aws; \$A prod put-item blocked" 2 "A=aws; \$A dynamodb put-item --table-name t --profile $PROD"
bash_case "R3#3 A=\$(which aws); \$A prod put-item blocked" 2 "A=\$(which aws); \$A dynamodb put-item --table-name t --profile $PROD"
bash_case "R3#3 backtick command word prod put-item blocked" 2 "${BT}which aws${BT} dynamodb put-item --table-name t --profile $PROD"
bash_case "R3#3 unset variable as command word, prod named: blocked" 2 "\$GUARD_TEST_UNSET_VAR dynamodb scan --table-name t --profile $PROD"
bash_case "R3#3 \${AWS_BIN:-aws} prod read allowed (resolves to aws)" 0 "\${AWS_BIN:-aws} dynamodb scan --table-name t --profile $PROD"
bash_case "R3#3 \${AWS_BIN:-/usr/local/bin/aws} prod put-item blocked" 2 "\${AWS_BIN:-/usr/local/bin/aws} dynamodb put-item --table-name t --profile $PROD"
bash_case "R3#3 \$(which aws) prod read blocked (indirect command word, conservative)" 2 "\$(which aws) dynamodb scan --table-name t --profile $PROD"
bash_case "R3#3 \$(which aws) put-item blocked (backstop)" 2 "$HEREDOC_APOS
\$(which aws) dynamodb put-item --table-name t --profile $PROD"
bash_case "R3#3 \${AWS_BIN:-aws} put-item, hook env prod, no literal: blocked" 2 "\${AWS_BIN:-aws} dynamodb put-item --table-name t" "$PROD"
bash_case "R3#3 A=aws; \$A put-item, hook env prod, no literal: blocked" 2 "A=aws; \$A dynamodb put-item --table-name t" "$PROD"
bash_case "R3#3 \$(which aws) put-item, hook env prod, no literal: blocked" 2 "\$(which aws) dynamodb put-item --table-name t" "$PROD"
bash_case "R3#3 \$(which aws) put-item on dev hook env, nothing prod: allowed" 0 "\$(which aws) dynamodb put-item --table-name t" "$DEV"
bash_case "R3#3 A=aws; \$A put-item, no prod anywhere: allowed" 0 "A=aws; \$A dynamodb put-item --table-name t"
bash_case "R3#3 \${AWS_BIN:-aws} put-item, dev flag, nothing prod: allowed" 0 "\${AWS_BIN:-aws} dynamodb put-item --table-name t --profile $DEV"
bash_case "R3#3 A=aws; \$A get-secret-value blocked" 2 "A=aws; \$A secretsmanager get-secret-value --secret-id x"
bash_case "R3#3 \$(which aws) get-secret-value blocked" 2 "\$(which aws) secretsmanager get-secret-value --secret-id x"
bash_case "R3#3 unresolved command word + get-secret-value (no aws/secretsmanager text) blocked" 2 "\$GUARD_TEST_UNSET_VAR get-secret-value --secret-id s"
bash_case "R3#3 C=\$(cat c); \$C get-secret-value blocked" 2 "C=\$(cat /tmp/c); \$C get-secret-value --secret-id s"
bash_case "R3#3 whole command in a variable (A=\"aws ...\"; \$A) prod put-item blocked" 2 "A=\"aws dynamodb put-item --table-name t --profile $PROD\"; \$A"

# [4] env wrapper semantics: -u / --unset / -i / - / --ignore-environment.
bash_case "R3#4 env -u AWS_PROFILE + AWS_DEFAULT_PROFILE prod put-item blocked" 2 "env -u AWS_PROFILE AWS_DEFAULT_PROFILE=$PROD aws dynamodb put-item --table-name t" "$DEV"
bash_case "R3#4 env -i + AWS_DEFAULT_PROFILE prod, absolute aws path, put-item blocked" 2 "env -i AWS_DEFAULT_PROFILE=$PROD /usr/local/bin/aws dynamodb put-item --table-name t" "$DEV"
# P3 only (no prod literal in the text).
bash_case "R3#4 P3: env -u AWS_PROFILE AWS_DEFAULT_PROFILE=prod (variable) blocked" 2 "P=fb-live-; env -u AWS_PROFILE AWS_DEFAULT_PROFILE=\${P}us-prod/Admin aws dynamodb put-item --table-name t" "$DEV"
bash_case "R3#4 P3: env --unset AWS_PROFILE blocked" 2 "P=fb-live-; env --unset AWS_PROFILE AWS_DEFAULT_PROFILE=\${P}us-prod/Admin aws dynamodb put-item --table-name t" "$DEV"
bash_case "R3#4 P3: env --unset=AWS_PROFILE blocked" 2 "P=fb-live-; env --unset=AWS_PROFILE AWS_DEFAULT_PROFILE=\${P}us-prod/Admin aws dynamodb put-item --table-name t" "$DEV"
bash_case "R3#4 P3: env -uAWS_PROFILE blocked" 2 "P=fb-live-; env -uAWS_PROFILE AWS_DEFAULT_PROFILE=\${P}us-prod/Admin aws dynamodb put-item --table-name t" "$DEV"
bash_case "R3#4 P3: env --uns (getopt prefix) blocked" 2 "P=fb-live-; env --uns AWS_PROFILE AWS_DEFAULT_PROFILE=\${P}us-prod/Admin aws dynamodb put-item --table-name t" "$DEV"
bash_case "R3#4 P3: env -i AWS_DEFAULT_PROFILE=prod blocked" 2 "P=fb-live-; env -i AWS_DEFAULT_PROFILE=\${P}us-prod/Admin aws dynamodb put-item --table-name t" "$DEV"
bash_case "R3#4 P3: env - AWS_DEFAULT_PROFILE=prod blocked" 2 "P=fb-live-; env - AWS_DEFAULT_PROFILE=\${P}us-prod/Admin aws dynamodb put-item --table-name t" "$DEV"
bash_case "R3#4 P3: env --ignore-environment blocked" 2 "P=fb-live-; env --ignore-environment AWS_DEFAULT_PROFILE=\${P}us-prod/Admin aws dynamodb put-item --table-name t" "$DEV"
bash_case "R3#4 P3: env -iu FOO cluster blocked" 2 "P=fb-live-; env -iu FOO AWS_DEFAULT_PROFILE=\${P}us-prod/Admin aws dynamodb put-item --table-name t" "$DEV"
bash_case "R3#4 P3: env -u then bash -c nested blocked" 2 "P=fb-live-; env -u AWS_PROFILE AWS_DEFAULT_PROFILE=\${P}us-prod/Admin bash -c 'aws dynamodb put-item --table-name t'" "$DEV"
bash_case "R3#4 P3: hook env prod, env -u AWS_PROFILE clears it (allowed)" 0 "env -u AWS_PROFILE aws dynamodb put-item --table-name t" "$PROD"
bash_case "R3#4 P3: hook env prod, env -i clears it (allowed)" 0 "env -i aws dynamodb put-item --table-name t" "$PROD"
bash_case "R3#4 P3: hook env prod, env -i AWS_PROFILE=dev (allowed)" 0 "env -i AWS_PROFILE=$DEV aws dynamodb put-item --table-name t" "$PROD"
bash_case "R3#4 P3: hook env prod, env -u AWS_PROFILE AWS_DEFAULT_PROFILE=dev (allowed)" 0 "env -u AWS_PROFILE AWS_DEFAULT_PROFILE=$DEV aws dynamodb put-item --table-name t" "$PROD"
bash_case "R3#4 P3: hook env prod, env -u OTHER keeps prod (blocked)" 2 "env -u FOO aws dynamodb put-item --table-name t" "$PROD"
bash_case "R3#4 P3: hook env prod, env -i then AWS_PROFILE=prod blocked" 2 "env -i AWS_PROFILE=$PROD aws dynamodb put-item --table-name t" "$PROD"
bash_case "R3#4 P3: env -i keeps shell-scope variables for argument expansion" 0 "P=$DEV; env -i aws --profile \$P dynamodb put-item --table-name t" "$PROD"
bash_case "R3#4 P3: env -u AWS_PROFILE falls back to an exported AWS_DEFAULT_PROFILE=prod" 2 "P=fb-live-; export AWS_DEFAULT_PROFILE=\${P}us-prod/Admin; env -u AWS_PROFILE aws dynamodb put-item --table-name t" "$DEV"
bash_case "R3#4 P3: env -u AWS_PROFILE falls back to an exported AWS_DEFAULT_PROFILE=dev (allowed)" 0 "export AWS_DEFAULT_PROFILE=$DEV; env -u AWS_PROFILE aws dynamodb put-item --table-name t" "$PROD"

# #2: `python -m awscli` is the aws CLI.
bash_case "R3 python3 -m awscli prod put-item blocked" 2 "python3 -m awscli dynamodb put-item --table-name t --profile $PROD"
bash_case "R3 python -m awscli prod put-item blocked" 2 "python -m awscli dynamodb put-item --table-name t --profile $PROD"
bash_case "R3 python3 -m awscli prod read allowed" 0 "python3 -m awscli dynamodb scan --table-name t --profile $PROD"
bash_case "R3 python3 -m awscli, hook env prod, no literal: put-item blocked" 2 "python3 -m awscli dynamodb put-item --table-name t" "$PROD"
bash_case "R3 python3 -I -m awscli, hook env prod: put-item blocked" 2 "python3 -I -m awscli dynamodb put-item --table-name t" "$PROD"
bash_case "R3 python3 -m awscli secret read blocked" 2 "python3 -m awscli secretsmanager get-secret-value --secret-id x"
bash_case "R3 python3 -m awscli on dev, put-item allowed" 0 "python3 -m awscli dynamodb put-item --table-name t" "$DEV"
bash_case "R3 python3 -m pip install awscli allowed" 0 "python3 -m pip install awscli"

# #3: s3 presign only builds a URL.
bash_case "R3 prod s3 presign allowed" 0 "aws --profile $PROD s3 presign s3://b/k"
bash_case "R3 prod s3 presign (trailing --profile) allowed" 0 "aws s3 presign s3://b/k --profile $PROD"
bash_case "R3 hook env prod s3 presign allowed" 0 "aws s3 presign s3://b/k --expires-in 60" "$PROD"

# P1 on terraform / profile-name tricks: when prod is named, only reads pass.
bash_case "R3 P1: prod named, terraform apply under a dev profile blocked" 2 "AWS_PROFILE=$DEV terraform apply -var=target=$PROD"
bash_case "R3 P1: prod named, tofu destroy with no profile blocked" 2 "echo $PROD; tofu destroy"
bash_case "R3 P1: prod named, terraform plan allowed" 0 "terraform plan -var=target=$PROD"
bash_case "R3 P1: prod named, terraform state list allowed" 0 "terraform -chdir=$PROD state list"
bash_case "R3 P1: prod named, dev profile put-item blocked (profile resolution ignored)" 2 "aws --profile $DEV dynamodb put-item --table-name $PROD-table"
bash_case "R3 P1: prod named, read on a prod-looking table name allowed" 0 "aws --profile $DEV dynamodb scan --table-name $PROD-table"
bash_case "R3 P1: prod read then dev put-item blocked" 2 "aws --profile $PROD dynamodb scan --table-name t; aws --profile $DEV dynamodb put-item --table-name t"
bash_case "R3 P1: unknown profile, prod named, read allowed" 0 "aws --profile \$(cat /tmp/p) dynamodb scan --table-name $PROD-t"
bash_case "R3 P1: variable op, prod named, dev profile blocked" 2 "aws --profile $DEV dynamodb \$GUARD_TEST_UNSET_VAR --table-name $PROD-t"
bash_case "R3 P1: aws with no service/op, prod named blocked" 2 "aws --profile $DEV --query $PROD"
bash_case "R3 P1: aws without prod named, no service/op allowed" 0 "aws --version"
# A command cut at `$(...)` hides the service/op from the structural pass.
bash_case "R3 cut at \$(..): hook env prod, put-item after --region \$(..) blocked" 2 "aws --region \$(echo us-east-1) dynamodb put-item --table-name t" "$PROD"
bash_case "R3 cut at \$(..): hook env dev, put-item after --region \$(..) allowed" 0 "aws --region \$(echo us-east-1) dynamodb put-item --table-name t" "$DEV"
bash_case "R3 cut at \$(..): hook env prod, read after --region \$(..) allowed" 0 "aws --region \$(echo us-east-1) dynamodb scan --table-name t" "$PROD"
bash_case "R3 cut at \$(..): prod profile via variable (no literal), put-item after --region \$(..) blocked" 2 "P=fb-live-; AWS_PROFILE=\${P}us-prod/Admin aws --region \$(echo us-east-1) dynamodb put-item --table-name t" "$DEV"
bash_case "R3 redirect before the op does not become the op" 0 "aws --profile $PROD dynamodb > /tmp/o.json scan --table-name t"
bash_case "R3 stdin redirect after xargs aws secretsmanager still blocked" 2 "xargs aws secretsmanager < ops.txt" "$DEV"

# H2 (catastrophic regex) and the other raw-text regexes: linear on big input.
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

payload_json() { # LINES [PREFIX] [SUFFIX]: a Bash command of secret-ARN lines
  N="$1" PREFIX="${2:-}" SUFFIX="${3:-}" python3 -c '
import json, os
lines = ["arn:aws:secretsmanager:us-east-1:111111111111:secret:app/db-%05d" % i
         for i in range(int(os.environ["N"]))]
cmd = os.environ["PREFIX"] + "\n".join(lines) + os.environ["SUFFIX"]
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}}))
'
}

# timed_check NAME WANT_RC MAX_SECONDS JSON
timed_check() {
  local name="$1" want="$2" max="$3" json="$4" out rc secs
  out=$(printf '%s' "$json" | HOOK="$HOOK" python3 -c '
import os, signal, subprocess, sys, time
data = sys.stdin.read()
env = {k: v for k, v in os.environ.items() if k not in ("AWS_PROFILE", "AWS_DEFAULT_PROFILE")}
t0 = time.monotonic()
p = subprocess.Popen(["bash", os.environ["HOOK"]], stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                     env=env, start_new_session=True)
try:
    p.communicate(data, timeout=20)
    print(p.returncode, "%.3f" % (time.monotonic() - t0))
except subprocess.TimeoutExpired:
    os.killpg(p.pid, signal.SIGKILL)
    p.communicate()
    print("TIMEOUT 20.000")
')
  rc=${out%% *}
  secs=${out##* }
  if [ "$rc" = "$want" ] && awk -v s="$secs" -v m="$max" 'BEGIN { exit !(s < m) }'; then
    PASS=$((PASS + 1)); echo "PASS: $name (${secs}s)"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $name (want exit $want in <${max}s, got exit $rc in ${secs}s)"
  fi
}

PAYLOAD_LINES=800 # about 52KB
timed_check "H2 50KB secret-ARN payload allowed in under 1s" 0 1 "$(payload_json $PAYLOAD_LINES)"
timed_check "H2 50KB secret-ARN payload then secret read blocked in under 1s" 2 1 "$(payload_json $PAYLOAD_LINES '' $'\naws secretsmanager get-secret-value --secret-id s')"
timed_check "H2 unparseable heredoc + 50KB secret-ARN payload + prod mutation blocked in under 2s" 2 2 "$(payload_json $PAYLOAD_LINES "$HEREDOC_APOS"$'\n' $'\naws --profile '"$PROD"$' dynamodb delete-table --table-name t')"
timed_check "H2 50KB payload of 'aws' words on one line allowed quickly" 0 2 "$(N=9000 python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": "echo " + "aws x " * int(os.environ["N"])}}))
')"
timed_check "H2 50KB payload of 'aws >' redirects with prod literal in unparseable text finishes quickly (blocked: no service/op after any aws word)" 2 2 "$(N=8000 PROD="$PROD" HEREDOC_APOS="$HEREDOC_APOS" python3 -c '
import json, os
cmd = os.environ["HEREDOC_APOS"] + "\n" + "aws > " * int(os.environ["N"]) + os.environ["PROD"]
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}}))
')"
timed_check "H2 50KB payload of unterminated \${a:-  allowed quickly" 0 2 "$(N=9000 python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": "echo " + "${a:-" * int(os.environ["N"])}}))
')"
timed_check "H2 50KB payload of terraform init words with prod literal allowed quickly" 0 2 "$(N=3000 PROD="$PROD" python3 -c '
import json, os
cmd = "echo " + ("terraform init -upgrade " * int(os.environ["N"])) + os.environ["PROD"]
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}}))
')"

# #13: one huge shell word (shlex is quadratic in token length). Above the caps
# (20KB word / 200KB command) the structural layer is skipped and the linear text
# rules decide.
big_json() { # WORD_CHARS [PREFIX] [SUFFIX]: a Bash command holding one huge word
  N="$1" PREFIX="${2:-}" SUFFIX="${3:-}" python3 -c '
import json, os
cmd = os.environ["PREFIX"] + "echo " + "a" * int(os.environ["N"]) + os.environ["SUFFIX"]
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}}))
'
}
timed_check "#13 300KB single word allowed in under 1s" 0 1 "$(big_json 300000)"
timed_check "#13 25KB single word (over the word cap, under the command cap) allowed in under 1s" 0 1 "$(big_json 25000)"
timed_check "#13 300KB word then prod mutation blocked in under 1s" 2 1 "$(big_json 300000 '' $'\naws --profile '"$PROD"$' dynamodb put-item --table-name t')"
timed_check "#13 300KB word then prod read allowed in under 1s" 0 1 "$(big_json 300000 '' $'\naws --profile '"$PROD"$' dynamodb scan --table-name t')"
timed_check "#13 300KB word then secret read blocked in under 1s" 2 1 "$(big_json 300000 '' $'\naws secretsmanager get-secret-value --secret-id s')"
timed_check "#13 300KB word then xargs-supplied secret read blocked in under 1s" 2 1 "$(big_json 300000 '' $'\necho secretsmanager get-secret-value | xargs aws')"
timed_check "#13 300KB word plus prod literal, no aws: allowed in under 1s" 0 1 "$(big_json 300000 '' " $PROD")"
timed_check "#13 300KB word in front of an indirect prod put-item blocked in under 1s" 2 1 "$(big_json 300000 '' $'\n$(which aws) dynamodb put-item --table-name t --profile '"$PROD")"
timed_check "#13 300KB word then terraform apply with prod literal blocked in under 1s" 2 1 "$(big_json 300000 '' $'\nAWS_PROFILE='"$PROD"$' terraform apply')"

# make_variant OUT OLD NEW [OLD NEW ...]: copy of $HOOK with exact one-time replacements.
make_variant() {
  local out="$1"
  shift
  python3 - "$HOOK" "$out" "$@" <<'PYV'
import sys
src = open(sys.argv[1]).read()
args = sys.argv[3:]
for old, new in zip(args[0::2], args[1::2]):
    if src.count(old) != 1:
        sys.exit("make_variant: %r occurs %d times" % (old, src.count(old)))
    src = src.replace(old, new)
open(sys.argv[2], "w").write(src)
PYV
}

# check_msg NAME WANT_RC JSON STDERR_SUBSTRING
check_msg() {
  local name="$1" want="$2" json="$3" sub="$4" err got
  err=$(printf '%s' "$json" | env -u AWS_PROFILE -u AWS_DEFAULT_PROFILE bash "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [ "$got" -eq "$want" ] && { [ -z "$sub" ] || printf '%s' "$err" | grep -qF -- "$sub"; }; then
    PASS=$((PASS + 1)); echo "PASS: $name"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $name (want exit $want with '$sub', got $got) $err"
  fi
}

# #18: internal time budget. The variant has a 1s budget and a 3s stall in analyze().
HOOK_REAL="$HOOK"
if make_variant "$TMPD/slow.sh" \
  "TIME_BUDGET_SECONDS = 7" "TIME_BUDGET_SECONDS = 1" \
  $'def analyze(cmd, env, depth=0, xa=(False, frozenset())):\n    if depth > 4:' $'def analyze(cmd, env, depth=0, xa=(False, frozenset())):\n    import time\n    time.sleep(3)\n    if depth > 4:'; then
  HOOK="$TMPD/slow.sh"
  check_msg "budget exceeded: command mentioning aws fails closed" 2 "$(json_bash "aws --profile $DEV dynamodb scan --table-name t")" "time budget"
  check_msg "budget exceeded: command mentioning prod literal fails closed" 2 "$(json_bash "echo $PROD")" "time budget"
  check_msg "budget exceeded: command mentioning terraform fails closed" 2 "$(json_bash "terraform plan")" "time budget"
  check_msg "budget exceeded: command mentioning tofu fails closed" 2 "$(json_bash "tofu plan")" "time budget"
  check_msg "budget exceeded: unrelated command allowed with stderr note" 0 "$(json_bash "ls -la")" "time budget exceeded"
  HOOK="$HOOK_REAL"
else
  FAIL=$((FAIL + 1)); echo "FAIL: could not build the time-budget variant"
fi
check_msg "no stall: unrelated command allowed silently" 0 "$(json_bash "ls -la")" ""

# #4: the wrapper fails closed when python3 dies with anything other than 0 or 2.
if make_variant "$TMPD/crash.sh" $'import json\nimport os\n' $'import json\nimport nonexistent_guard_test_module\nimport os\n'; then
  HOOK="$TMPD/crash.sh"
  check_msg "python crash: command mentioning aws fails closed" 2 "$(json_bash "aws --profile $DEV dynamodb scan --table-name t")" "could not run to completion"
  check_msg "python crash: command mentioning prod literal fails closed" 2 "$(json_bash "echo $PROD")" "could not run to completion"
  check_msg "python crash: command mentioning terraform fails closed" 2 "$(json_bash "terraform plan")" "could not run to completion"
  check_msg "python crash: command mentioning tofu fails closed" 2 "$(json_bash "tofu plan")" "could not run to completion"
  check_msg "python crash: unrelated command still allowed" 0 "$(json_bash "ls -la")" ""
  HOOK="$HOOK_REAL"
else
  FAIL=$((FAIL + 1)); echo "FAIL: could not build the crash variant"
fi
# Round-3 mutation guards: with a policy layer disabled, the bypass it closes must
# come back (rc 0). This proves the R3 cases above exercise each layer.
# P1 off: profile resolution is trusted again when prod is named.
if make_variant "$TMPD/p1off.sh" \
  'if not msg and literal and (STATS["nonread"] or STATS["indirect"]):' 'if False:'; then
  HOOK="$TMPD/p1off.sh"
  bash_case "mutation P1 off: dev profile, prod named, put-item bypasses" 0 "aws --profile $DEV dynamodb put-item --table-name $PROD-table"
  bash_case "mutation P1 off: \${AWS_PROFILE:-prod} resolved to dev bypasses" 0 "aws --profile \${AWS_PROFILE:-$PROD} dynamodb put-item --table-name t" "$DEV"
  bash_case "mutation P1 off: xargs supplies everything, prod only on stdin side, bypasses" 0 "echo \"dynamodb put-item --profile $PROD\" | xargs aws" "$DEV"
  bash_case "mutation P1 off: terraform apply under a dev profile with prod named bypasses" 0 "AWS_PROFILE=$DEV terraform apply -var=target=$PROD"
  HOOK="$HOOK_REAL"
else
  FAIL=$((FAIL + 1)); echo "FAIL: could not build the P1-off variant"
fi
# P2 off: the text-level secret rule.
if make_variant "$TMPD/p2off.sh" 'if secret_text_hit(cmd, indirect):' 'if False:'; then
  HOOK="$TMPD/p2off.sh"
  bash_case "mutation P2 off: xargs supplies service+op from text, secret read bypasses" 0 "echo secretsmanager get-secret-value --secret-id x | xargs aws"
  bash_case "mutation P2 off: awscli with get-secret-value before secretsmanager bypasses" 0 "echo get-secret-value | awscli secretsmanager"
  bash_case "mutation P2 off: unresolved command word + get-secret-value bypasses" 0 "\$GUARD_TEST_UNSET_VAR get-secret-value --secret-id s"
  bash_case "mutation P2 off: uppercase xargs secret read bypasses" 0 "echo SECRETSMANAGER GET-SECRET-VALUE | XARGS AWS"
  HOOK="$HOOK_REAL"
else
  FAIL=$((FAIL + 1)); echo "FAIL: could not build the P2-off variant"
fi
# Each of the R3 bypasses is closed by two independent layers (P1 when prod is
# named, P3/structural otherwise), so a single layer off keeps them blocked; both
# off brings the original bypass back.
if make_variant "$TMPD/p1canon.sh" \
  'if not msg and literal and (STATS["nonread"] or STATS["indirect"]):' 'if False:' \
  '    if name in GLOBAL_OPTS or len(name) < 3 or not name.startswith("--"):' '    if True:'; then
  HOOK="$TMPD/p1canon.sh"
  bash_case "mutation P1+canon off: --prof prod put-item bypasses (original #1)" 0 "aws --prof $PROD dynamodb put-item --table-name t" "$DEV"
  bash_case "mutation P1+canon off: --pro= prod purge-queue bypasses (original #1)" 0 "aws --pro=$PROD sqs purge-queue --queue-url x" "$DEV"
  bash_case "mutation P1+canon off: trailing --profil prod put-item bypasses (original #1)" 0 "aws dynamodb put-item --table-name t --profil $PROD" "$DEV"
  HOOK="$HOOK_REAL"
else
  FAIL=$((FAIL + 1)); echo "FAIL: could not build the P1+canon-off variant"
fi
if make_variant "$TMPD/p1env.sh" \
  'if not msg and literal and (STATS["nonread"] or STATS["indirect"]):' 'if False:' \
  '            for op, name in ops:' '            for op, name in []:'; then
  HOOK="$TMPD/p1env.sh"
  bash_case "mutation P1+env ops off: env -u AWS_PROFILE AWS_DEFAULT_PROFILE=prod bypasses (original #4)" 0 "env -u AWS_PROFILE AWS_DEFAULT_PROFILE=$PROD aws dynamodb put-item --table-name t" "$DEV"
  bash_case "mutation P1+env ops off: env -i AWS_DEFAULT_PROFILE=prod bypasses (original #4)" 0 "env -i AWS_DEFAULT_PROFILE=$PROD /usr/local/bin/aws dynamodb put-item --table-name t" "$DEV"
  HOOK="$HOOK_REAL"
else
  FAIL=$((FAIL + 1)); echo "FAIL: could not build the P1+env-ops-off variant"
fi
if make_variant "$TMPD/p1ind.sh" \
  'if not msg and literal and (STATS["nonread"] or STATS["indirect"]):' 'if False:' \
  '            return "aws (no service or operation after the aws word)"' '            continue'; then
  HOOK="$TMPD/p1ind.sh"
  bash_case "mutation P1+backstop missing-service off: \$(which aws) prod put-item bypasses (original #3)" 0 "\$(which aws) dynamodb put-item --table-name t --profile $PROD"
  bash_case "mutation P1+backstop missing-service off: \"\$(command -v aws)\" prod put-item bypasses (original #3)" 0 "\"\$(command -v aws)\" dynamodb put-item --table-name t --profile $PROD"
  HOOK="$HOOK_REAL"
else
  FAIL=$((FAIL + 1)); echo "FAIL: could not build the P1+missing-service-off variant"
fi
# P3 off: abbreviated options not canonicalised / env -u -i not applied.
if make_variant "$TMPD/p3canon.sh" '    if name in GLOBAL_OPTS or len(name) < 3 or not name.startswith("--"):' '    if True:'; then
  HOOK="$TMPD/p3canon.sh"
  bash_case "mutation canon off: abbreviated --prof resolving to prod bypasses" 0 "P=fb-live-; aws --prof \${P}us-prod/Admin dynamodb put-item --table-name t" "$DEV"
  HOOK="$HOOK_REAL"
else
  FAIL=$((FAIL + 1)); echo "FAIL: could not build the canon-off variant"
fi
if make_variant "$TMPD/p3env.sh" '            for op, name in ops:' '            for op, name in []:'; then
  HOOK="$TMPD/p3env.sh"
  bash_case "mutation env ops off: env -u AWS_PROFILE + AWS_DEFAULT_PROFILE prod bypasses" 0 "P=fb-live-; env -u AWS_PROFILE AWS_DEFAULT_PROFILE=\${P}us-prod/Admin aws dynamodb put-item --table-name t" "$DEV"
  bash_case "mutation env ops off: env -i AWS_DEFAULT_PROFILE prod bypasses" 0 "P=fb-live-; env -i AWS_DEFAULT_PROFILE=\${P}us-prod/Admin aws dynamodb put-item --table-name t" "$DEV"
  HOOK="$HOOK_REAL"
else
  FAIL=$((FAIL + 1)); echo "FAIL: could not build the env-ops-off variant"
fi
# R4 mutation guards: with a rule disabled, the bypass it closes comes back (rc 0).
# [1] s3 cp/sync destination expansion off: the raw destination counts as local.
if make_variant "$TMPD/r4s3.sh" \
  '        dest, dvar = classify(pos[1], env or {})' '        dest, dvar = pos[1], False' \
  '            and not has_repl(pos[1], repl)' '            and True'; then
  HOOK="$TMPD/r4s3.sh"
  bash_case "mutation R4#1 off: s3 cp dest from assigned s3 variable bypasses" 0 "D=s3://dst/k; aws s3 cp s3://src/k \$D --profile $PROD"
  bash_case "mutation R4#1 off: s3 cp dest from quoted unset variable bypasses" 0 "aws s3 cp s3://src/k \"\$DEST\" --profile $PROD"
  bash_case "mutation R4#1 off: s3 cp dest from command substitution bypasses" 0 "aws s3 cp s3://src/k \"\$(echo s3://dst/k)\" --profile $PROD"
  bash_case "mutation R4#1 off: s3 cp dest from xargs replace string bypasses" 0 "echo s3://dst/k | xargs -I{} aws s3 cp s3://src/k {} --profile $PROD"
  bash_case "mutation R4#1 off: s3 sync dest from \${D:-s3://...} default bypasses" 0 "aws s3 sync s3://src/ \"\${D:-s3://dst/}\" --profile $PROD"
  HOOK="$HOOK_REAL"
else
  FAIL=$((FAIL + 1)); echo "FAIL: could not build the R4#1-off variant"
fi
# [2] SSM reference path rule off.
if make_variant "$TMPD/r4ssm.sh" '    if ssm_secret_ref(low):' '    if False:'; then
  HOOK="$TMPD/r4ssm.sh"
  bash_case "mutation R4#2 off: ssm get-parameter on the reference path bypasses" 0 "aws ssm get-parameter --name /aws/reference/secretsmanager/x --with-decryption"
  bash_case "mutation R4#2 off: ssm get-parameter on the reference path bypasses on prod" 0 "aws ssm get-parameter --name /aws/reference/secretsmanager/x --with-decryption --profile $PROD"
  HOOK="$HOOK_REAL"
else
  FAIL=$((FAIL + 1)); echo "FAIL: could not build the R4#2-off variant"
fi
# [3] SDK-spelling secret rule off.
if make_variant "$TMPD/r4sdk.sh" '    if MCP_SECRET_RE.search(text) and any(w in low for w in SECRET_SDK_WORDS):' '    if False:'; then
  HOOK="$TMPD/r4sdk.sh"
  bash_case "mutation R4#3 off: boto3 get_secret_value bypasses" 0 "python3 -c \"import boto3; print(boto3.client('secretsmanager').get_secret_value(SecretId='x'))\""
  bash_case "mutation R4#3 off: node GetSecretValueCommand bypasses" 0 "node -e \"const {SecretsManagerClient, GetSecretValueCommand} = require('@aws-sdk/client-secrets-manager'); new GetSecretValueCommand({SecretId:'x'})\""
  HOOK="$HOOK_REAL"
else
  FAIL=$((FAIL + 1)); echo "FAIL: could not build the R4#3-off variant"
fi
# [4] SDK-mutation text rule off.
if make_variant "$TMPD/r4sdkmut.sh" '    if call:' '    if False:'; then
  HOOK="$TMPD/r4sdkmut.sh"
  bash_case "mutation R4#4 off: boto3 delete_item under prod profile bypasses" 0 "AWS_PROFILE=$PROD python3 -c \"import boto3; boto3.client('dynamodb').delete_item(TableName='t', Key={})\""
  bash_case "mutation R4#4 off: node PutItemCommand under prod profile bypasses" 0 "AWS_PROFILE=$PROD node -e \"new DynamoDBClient({}).send(new PutItemCommand({}))\""
  HOOK="$HOOK_REAL"
else
  FAIL=$((FAIL + 1)); echo "FAIL: could not build the R4#4-off variant"
fi
mkdir "$TMPD/nopy"
ln -s "$(command -v cat)" "$TMPD/nopy/cat"
ln -s "$(command -v grep)" "$TMPD/nopy/grep"
nopy_case() { # NAME WANT JSON
  local err got
  err=$(printf '%s' "$3" | env PATH="$TMPD/nopy" /bin/bash "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [ "$got" -eq "$2" ]; then PASS=$((PASS + 1)); echo "PASS: $1"; else FAIL=$((FAIL + 1)); echo "FAIL: $1 (want $2, got $got) $err"; fi
}
nopy_case "python3 missing: command mentioning aws fails closed" 2 "$(json_bash "aws sqs purge-queue --queue-url u")"
nopy_case "python3 missing: unrelated command allowed" 0 "$(json_bash "ls -la")"
# Failure before the command is extracted still judges the raw input text.
check_msg "tool_input not a dict: input mentioning aws fails closed" 2 '{"tool_name":"Bash","tool_input":"aws sqs purge-queue --queue-url u"}' "Failing closed"
check_msg "tool_input not a dict: unrelated input allowed" 0 '{"tool_name":"Bash","tool_input":"ls"}' ""

# MCP run_script
check "mcp run_script GetSecretValue blocked" 2 "$(json_mcp "import boto3; boto3.client('secretsmanager').get_secret_value(SecretId='s')")"
check "mcp run_script GetSecretValue (CamelCase) blocked" 2 "$(json_mcp "aws secretsmanager GetSecretValue")"
check "mcp run_script BatchGetSecretValue blocked" 2 "$(json_mcp "call BatchGetSecretValue now")"
check "mcp run_script other code allowed" 0 "$(json_mcp "aws dynamodb describe-table --table-name t")"
check "mcp run_script mutation code not judged" 0 "$(json_mcp "aws dynamodb put-item --table-name t")"
check "mcp (plugin tool name) GetSecretValue blocked" 2 "$(json_mcp "import boto3; boto3.client('secretsmanager').get_secret_value(SecretId='s')" "$MCP_TOOL_B")"
check "mcp (plugin tool name) BatchGetSecretValue blocked" 2 "$(json_mcp "call BatchGetSecretValue now" "$MCP_TOOL_B")"
check "mcp (plugin tool name) other code allowed" 0 "$(json_mcp "aws dynamodb describe-table --table-name t" "$MCP_TOOL_B")"

# R4 [1]: s3 cp/sync is a read only when the expanded destination is a literal
# local path (or `-`). A variable, substitution or xargs replace string could be an
# s3 URL, so it is a prod write.
bash_case "R4#1 s3 cp dest from assigned s3 variable blocked" 2 "D=s3://dst/k; aws s3 cp s3://src/k \$D --profile $PROD"
bash_case "R4#1 s3 cp dest from quoted unset variable blocked" 2 "aws s3 cp s3://src/k \"\$DEST\" --profile $PROD"
bash_case "R4#1 s3 cp dest from command substitution blocked" 2 "aws s3 cp s3://src/k \"\$(echo s3://dst/k)\" --profile $PROD"
bash_case "R4#1 s3 cp dest from xargs replace string blocked" 2 "echo s3://dst/k | xargs -I{} aws s3 cp s3://src/k {} --profile $PROD"
bash_case "R4#1 s3 sync dest from \${D:-s3://...} default blocked" 2 "aws s3 sync s3://src/ \"\${D:-s3://dst/}\" --profile $PROD"
bash_case "R4#1 s3 cp dest variable, prod from env, blocked" 2 "aws s3 cp s3://src/k \"\$DEST\"" "$PROD"
bash_case "R4#1 s3 cp dest variable (backstop: unparseable text) blocked" 2 "$HEREDOC_APOS
aws s3 cp s3://src/k \$D --profile $PROD"
bash_case "R4#1 s3 cp uppercase S3:// dest blocked" 2 "aws s3 cp s3://src/k S3://dst/k --profile $PROD"
bash_case "R4#1 s3 cp dest variable resolving to a local path allowed" 0 "D=./out; aws s3 cp s3://b/k \$D --profile $PROD"
bash_case "R4#1 s3 cp s3->local allowed (still)" 0 "aws --profile $PROD s3 cp s3://b/k ./out"
bash_case "R4#1 s3 cp s3->stdout allowed (still)" 0 "aws --profile $PROD s3 cp s3://b/k -"
bash_case "R4#1 s3 cp variable dest on dev profile allowed" 0 "aws s3 cp s3://src/k \$D --profile $DEV"
bash_case "R4#1 s3 presign allowed (no destination)" 0 "aws s3 presign s3://b/k --profile $PROD"

# R4 [2]+[3]: Secrets Manager reads through the SSM reference path and through SDK
# spellings in a Bash command, on every profile.
bash_case "R4#2 ssm get-parameter on the secretsmanager reference path blocked (no profile)" 2 "aws ssm get-parameter --name /aws/reference/secretsmanager/x --with-decryption"
bash_case "R4#2 ssm get-parameter secretsmanager reference blocked on dev" 2 "aws ssm get-parameter --name /aws/reference/secretsmanager/x --with-decryption --profile $DEV"
bash_case "R4#2 ssm get-parameter secretsmanager reference blocked on prod" 2 "aws ssm get-parameter --name /aws/reference/secretsmanager/x --with-decryption --profile $PROD"
bash_case "R4#2 ssm get-parameters secretsmanager reference blocked" 2 "aws ssm get-parameters --names /aws/reference/secretsmanager/x --with-decryption"
bash_case "R4#2 ssm get-parameters-by-path secretsmanager reference blocked" 2 "aws ssm get-parameters-by-path --path /aws/reference/secretsmanager --with-decryption"
bash_case "R4#2 ssm get-parameter uppercase reference blocked" 2 "AWS SSM GET-PARAMETER --NAME /AWS/REFERENCE/SECRETSMANAGER/x"
bash_case "R4#2 boto3 ssm get_parameter on the reference path blocked" 2 "python3 -c \"import boto3; boto3.client('ssm').get_parameter(Name='/aws/reference/secretsmanager/x')\""
bash_case "R4#2 ssm get-parameter on an ordinary path allowed" 0 "aws ssm get-parameter --name /app/config/x --profile $DEV"
bash_case "R4#2 grep for the reference path allowed" 0 "grep -rn /aws/reference/secretsmanager docs/"
bash_case "R4#3 boto3 get_secret_value blocked" 2 "python3 -c \"import boto3; print(boto3.client('secretsmanager').get_secret_value(SecretId='x'))\""
bash_case "R4#3 boto3 get_secret_value blocked on prod" 2 "AWS_PROFILE=$PROD python3 -c \"import boto3; print(boto3.client('secretsmanager').get_secret_value(SecretId='x'))\""
bash_case "R4#3 boto3 batch_get_secret_value blocked" 2 "python3 -c \"import boto3; boto3.client('x').batch_get_secret_value(SecretIdList=['a'])\""
bash_case "R4#3 node GetSecretValueCommand blocked" 2 "node -e \"const {SecretsManagerClient, GetSecretValueCommand} = require('@aws-sdk/client-secrets-manager'); new GetSecretValueCommand({SecretId:'x'})\""
bash_case "R4#3 node BatchGetSecretValueCommand blocked" 2 "node -e \"const {BatchGetSecretValueCommand} = require('@aws-sdk/client-secrets-manager')\""
bash_case "R4#3 node aws-sdk v2 getSecretValue blocked" 2 "node -e \"const A = require('aws-sdk'); new A.X().getSecretValue({})\""
bash_case "R4#3 secretsmanagerclient word blocked" 2 "echo SecretsManagerClient GetSecretValue"
bash_case "R4#3 grep for get_secret_value alone allowed" 0 "grep -rn get_secret_value docs/"
bash_case "R4#3 grep for GetSecretValue alone allowed" 0 "grep -rn GetSecretValue src/"

# R4 [4]: a non-aws binary that names prod and holds an SDK-style mutation call.
bash_case "R4#4 python boto3 delete_item under prod profile blocked" 2 "AWS_PROFILE=$PROD python3 -c \"import boto3; boto3.client('dynamodb').delete_item(TableName='t', Key={})\""
bash_case "R4#4 python boto3 Table.put_item under prod profile blocked" 2 "AWS_PROFILE=$PROD python3 -c \"import boto3; boto3.resource('dynamodb').Table('t').put_item(Item={})\""
bash_case "R4#4 boto3 Session(profile_name=prod) update_item blocked" 2 "python3 -c \"import boto3; boto3.Session(profile_name='$PROD').client('dynamodb').update_item(TableName='t')\""
bash_case "R4#4 boto3 sqs send_message blocked" 2 "AWS_PROFILE=$PROD python3 -c \"import boto3; boto3.client('sqs').send_message(QueueUrl='u', MessageBody='b')\""
bash_case "R4#4 boto3 lambda invoke blocked" 2 "AWS_PROFILE=$PROD python3 -c \"import boto3; boto3.client('lambda').invoke(FunctionName='f')\""
bash_case "R4#4 boto3 s3 upload_file blocked" 2 "AWS_PROFILE=$PROD python3 -c \"import boto3; boto3.client('s3').upload_file('f', 'b', 'k')\""
bash_case "R4#4 boto3 sns publish blocked" 2 "AWS_PROFILE=$PROD python3 -c \"import boto3; boto3.client('sns').publish(TopicArn='t', Message='m')\""
bash_case "R4#4 boto3 batch_writer blocked" 2 "AWS_PROFILE=$PROD python3 -c \"import boto3; t = boto3.resource('dynamodb').Table('t'); t.batch_writer()\""
bash_case "R4#4 exported prod profile then python script with put_item( blocked" 2 "export AWS_PROFILE=$PROD; python3 -c \"import boto3; boto3.client('dynamodb').put_item(TableName='t', Item={})\""
bash_case "R4#4 node PutItemCommand under prod profile blocked" 2 "AWS_PROFILE=$PROD node -e \"new DynamoDBClient({}).send(new PutItemCommand({}))\""
bash_case "R4#4 node DeleteCommand (DocumentClient) blocked" 2 "AWS_PROFILE=$PROD node -e \"doc.send(new DeleteCommand({}))\""
bash_case "R4#4 node lambda.invoke( blocked" 2 "AWS_PROFILE=$PROD node -e \"lambda.invoke({FunctionName:'f'})\""
bash_case "R4#4 boto3 put_item without a prod name allowed" 0 "python3 -c \"import boto3; boto3.client('dynamodb').put_item(TableName='t', Item={})\""
bash_case "R4#4 boto3 put_item under dev profile allowed" 0 "AWS_PROFILE=$DEV python3 -c \"import boto3; boto3.client('dynamodb').put_item(TableName='t', Item={})\""
bash_case "R4#4 boto3 get_item under prod profile allowed" 0 "AWS_PROFILE=$PROD python3 -c \"import boto3; print(boto3.client('dynamodb').get_item(TableName='t', Key={}))\""
bash_case "R4#4 boto3 query under prod profile allowed" 0 "AWS_PROFILE=$PROD python3 -c \"import boto3; print(boto3.client('dynamodb').query(TableName='t'))\""
bash_case "R4#4 boto3 describe_table under prod profile allowed" 0 "AWS_PROFILE=$PROD python3 -c \"import boto3; print(boto3.client('dynamodb').describe_table(TableName='t'))\""
bash_case "R4#4 boto3 scan and list_tables under prod profile allowed" 0 "AWS_PROFILE=$PROD python3 -c \"import boto3; c = boto3.client('dynamodb'); c.scan(TableName='t'); c.list_tables()\""
bash_case "R4#4 boto3 logs start_query (Logs Insights read) under prod profile allowed" 0 "AWS_PROFILE=$PROD python3 -c \"import boto3; boto3.client('logs').start_query(logGroupName='g')\""
bash_case "R4#4 node GetItemCommand and QueryCommand under prod profile allowed" 0 "AWS_PROFILE=$PROD node -e \"c.send(new GetItemCommand({})); c.send(new QueryCommand({}))\""
bash_case "R4#4 terragrunt apply under prod profile blocked" 2 "AWS_PROFILE=$PROD terragrunt apply"
bash_case "R4#4 terragrunt apply with prod from env blocked" 2 "terragrunt apply" "$PROD"
bash_case "R4#4 terragrunt plan under prod profile allowed" 0 "AWS_PROFILE=$PROD terragrunt plan"
bash_case "R4#4 terragrunt apply under dev profile allowed" 0 "AWS_PROFILE=$DEV terragrunt apply"
# The P4 regex stays linear on runs of verb-like text.
timed_check "R4#4 200KB run of put_ with prod literal allowed in under 2s" 0 2 "$(N=50000 PROD="$PROD" python3 -c '
import json, os
cmd = "echo " + "put_" * int(os.environ["N"]) + " " + os.environ["PROD"]
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}}))
')"
timed_check "R4#4 200KB run of PutPut with prod literal allowed in under 2s" 0 2 "$(N=50000 PROD="$PROD" python3 -c '
import json, os
cmd = "echo " + "Put" * int(os.environ["N"]) + " " + os.environ["PROD"]
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}}))
')"

# MCP: the SSM reference path is the same secret class as GetSecretValue.
check "R4#2 mcp run_script ssm get_parameter on the secretsmanager reference path blocked" 2 "$(json_mcp "boto3.client('ssm').get_parameter(Name='/aws/reference/secretsmanager/x')")"
check "R4#2 mcp run_script ssm get_parameter on an ordinary path allowed" 0 "$(json_mcp "boto3.client('ssm').get_parameter(Name='/app/x')")"

# settings.json matcher must route the real MCP tool names (and Bash) to the hook.
# The matcher is an unanchored JS regex; python re.search is equivalent for it.
SETTINGS="${SETTINGS:-$(cd "$(dirname "$0")/../.." && pwd)/settings.json}"
matcher_case() { # NAME WANT(match|nomatch) TOOL
  local got
  got=$(SETTINGS="$SETTINGS" TOOL="$3" python3 -c '
import json, os, re
cfg = json.load(open(os.environ["SETTINGS"]))
ms = [e["matcher"] for e in cfg["hooks"]["PreToolUse"]
      if any("guard-prod-readonly.sh" in h.get("command", "") for h in e["hooks"])]
assert len(ms) == 1, ms
print("match" if re.search(ms[0], os.environ["TOOL"]) else "nomatch")
' 2>&1)
  if [ "$got" = "$2" ]; then
    PASS=$((PASS + 1)); echo "PASS: $1"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $1 (want $2, got $got)"
  fi
}
matcher_case "settings matcher routes Bash" match "Bash"
matcher_case "settings matcher routes claude_ai AWS MCP run_script" match "$MCP_TOOL_A"
matcher_case "settings matcher routes plugin aws-mcp run_script" match "$MCP_TOOL_B"
matcher_case "settings matcher routes a tool name with only upper-case AWS" match "mcp__claude_ai_AWS__run_script"
matcher_case "settings matcher ignores Read" nomatch "Read"
matcher_case "settings matcher ignores non-AWS MCP tool" nomatch "mcp__claude_ai_Port_IO__get_entity"

# Robustness
check "empty input allowed" 0 ""
check "garbage input allowed" 0 "not json"
check "other tool allowed" 0 '{"tool_name":"Read","tool_input":{"file_path":"/x"}}'

echo
echo "guard-prod-readonly: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
