#!/bin/bash
#
# Tests for risk-score. Each case builds a throwaway git repo (a base commit on master, a
# change on a feature branch) and checks the JSON line. A fake `aws` on PATH, a fake
# aws-target (RISK_SCORE_AWS_TARGET) and a fake pr-context (RISK_SCORE_PR_CONTEXT) stand
# in for the live calls; no real AWS or GitHub call is made. Repo and function names are
# made up.
#
# Usage: bin/tests/risk-score.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
RS="$HERE/../risk-score"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
OUT=""; ERR=""; RC=0

ok()  { PASS=$((PASS + 1)); echo "PASS  $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL  $1"; echo "      $2"; echo "      stdout: $OUT" | head -8; echo "      stderr: $ERR" | head -5; }

assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi; }
assert_ge() { if [ "$3" -ge "$2" ] 2>/dev/null; then ok "$1"; else bad "$1" "expected >= $2, got [$3]"; fi; }
assert_lt() { if [ "$3" -lt "$2" ] 2>/dev/null; then ok "$1"; else bad "$1" "expected < $2, got [$3]"; fi; }
assert_out_has()   { if printf '%s\n' "$OUT" | grep -qF -- "$2"; then ok "$1"; else bad "$1" "stdout missing: $2"; fi; }
assert_out_lacks() { if printf '%s\n' "$OUT" | grep -qF -- "$2"; then bad "$1" "stdout unexpectedly has: $2"; else ok "$1"; fi; }

# jget PATH : a field of the JSON in OUT by dotted path (lists joined with " | ")
jget() {
  printf '%s' "$OUT" | python3 -c '
import json, sys
v = json.load(sys.stdin)
for k in sys.argv[1].split("."):
    v = v[k]
print(" | ".join(map(str, v)) if isinstance(v, list) else v)' "$1" 2>/dev/null
}
dims() { echo "hot=$(jget dims.hot) complexity=$(jget dims.complexity) config=$(jget dims.config) gap=$(jget dims.reviewGap)"; }

G() { git -C "$REPO" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }

# new_repo NAME : repo with a README and one tiny source file, base commit on master,
# feature branch checked out. NAME is the directory (and so the repo name).
new_repo() {
  REPO="$WORK/$1"
  mkdir -p "$REPO/src" "$REPO/docs"
  git init -q -b master "$REPO"
  printf '# readme\n' > "$REPO/README.md"
  printf 'export const a = 1\n' > "$REPO/src/a.ts"
  G add -A && G commit -q -m base
  G checkout -q -b feature
}
commit_all() { G add -A && G commit -q -m "${1:-change}"; }
# put PATH CONTENT : write a file (CONTENT via printf %b)
put() { mkdir -p "$(dirname "$REPO/$1")"; printf '%b' "$2" > "$REPO/$1"; }
# gen PATH N LINE : N copies of LINE (LINE may contain %d for the index)
gen() {
  mkdir -p "$(dirname "$REPO/$1")"
  python3 - "$REPO/$1" "$2" "$3" <<'PY'
import sys
path, n, line = sys.argv[1], int(sys.argv[2]), sys.argv[3]
open(path, "w").write("".join((line % i if "%d" in line else line) + "\n" for i in range(n)))
PY
}

run_rs() { # args... : stdout -> OUT, stderr -> ERR, exit -> RC
  local errf="$WORK/stderr.txt"
  OUT=$("$RS" "$@" 2>"$errf" < /dev/null); RC=$?
  ERR=$(cat "$errf")
}

# ---- fakes -------------------------------------------------------------------------
BIN="$WORK/fakebin"; mkdir -p "$BIN"
AWS_LOG="$WORK/aws.log"

# fake aws: logs "<AWS_PROFILE> <argv>" (and the credential env vars it saw to $AWS_LOG.env);
# FAKE_FN_MISSING / FAKE_METRIC_FAIL shape failures, FAKE_SUM is the 7-day Sum. A leading
# --profile P is consumed before the subcommand, as the real aws CLI does.
cat > "$BIN/aws" <<'EOF'
#!/bin/bash
echo "${AWS_PROFILE:-} $*" >> "$AWS_LOG"
echo "key=${AWS_ACCESS_KEY_ID-unset} secret=${AWS_SECRET_ACCESS_KEY-unset} token=${AWS_SESSION_TOKEN-unset}" >> "$AWS_LOG.env"
if [ "${1:-}" = "--profile" ]; then shift 2; fi
case "$1 $2" in
  "lambda get-function")
    if [ -n "${FAKE_FN_MISSING:-}" ]; then echo "An error occurred (ResourceNotFoundException) when calling the GetFunction operation: Function not found" >&2; exit 254; fi
    echo "demo-fn"; exit 0 ;;
  "cloudwatch get-metric-statistics")
    if [ -n "${FAKE_METRIC_FAIL:-}" ]; then echo "AccessDenied" >&2; exit 254; fi
    printf '{"Datapoints": [{"Sum": %s, "Unit": "Count"}]}\n' "${FAKE_SUM:-0}"; exit 0 ;;
esac
echo "unexpected aws call: $*" >&2; exit 99
EOF
chmod +x "$BIN/aws"

# fake aws-target: prints the export line, or fails with FAKE_TARGET_RC
cat > "$WORK/fake-aws-target" <<'EOF'
#!/bin/bash
echo "$*" >> "$AWS_LOG.target"
if [ -n "${FAKE_TARGET_RC:-}" ]; then echo "aws-target: sts failed" >&2; echo "run: aws sso login --profile demo-prod" >&2; exit "$FAKE_TARGET_RC"; fi
echo "export AWS_PROFILE='demo-prod-readonly'"
EOF
chmod +x "$WORK/fake-aws-target"

# fake pr-context --json: FAKE_PR_HEAD, FAKE_PR_THREADS, FAKE_PR_APPROVALS, FAKE_PR_RC
cat > "$WORK/fake-pr-context" <<'EOF'
#!/bin/bash
echo "$*" >> "$AWS_LOG.pr"
if [ -n "${FAKE_PR_RC:-}" ]; then echo "pr-context: boom" >&2; exit "$FAKE_PR_RC"; fi
python3 - <<'PY'
import json, os
n = int(os.environ.get("FAKE_PR_THREADS", "0"))
a = int(os.environ.get("FAKE_PR_APPROVALS", "0"))
print(json.dumps({
    "pr": {"headRefOid": os.environ["FAKE_PR_HEAD"]},
    "actionable": {"threads": [{"id": i} for i in range(n)], "comments": []},
    "reviews": ["oops"] if os.environ.get("FAKE_PR_BAD_REVIEW") else
               [{"author": "someone", "state": "APPROVED"}] * a + [{"author": "ci[bot]", "state": "APPROVED"}],
    "truncated": {"threads": 0},
}))
PY
EOF
chmod +x "$WORK/fake-pr-context"

export PATH="$BIN:$PATH"
export AWS_LOG
export RISK_SCORE_AWS_TARGET="$WORK/fake-aws-target"
export RISK_SCORE_PR_CONTEXT="$WORK/fake-pr-context"
unset RISK_SCORE_AWS FAKE_FN_MISSING FAKE_METRIC_FAIL FAKE_SUM FAKE_TARGET_RC FAKE_PR_RC FAKE_PR_BAD_REVIEW

# ---- 1. docs-only: every dim 1, one valid JSON line, the documented keys --------------
new_repo c1
put docs/guide.md 'Some prose.\n'
commit_all docs
run_rs -C "$REPO"
assert_eq "docs-only - exit 0" 0 "$RC"
assert_eq "docs-only - all dims 1" "hot=1 complexity=1 config=1 gap=1" "$(dims)"
assert_eq "docs-only - score 1" 1 "$(jget score)"
assert_eq "docs-only - phase pre" pre "$(jget phase)"
assert_eq "docs-only - nothing unknown" "" "$(jget unknown)"
assert_eq "docs-only - no drivers" "" "$(jget drivers)"
assert_eq "output is a single line" 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
assert_eq "JSON keys are the documented ones" "dims,drivers,phase,score,unknown" \
  "$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(",".join(sorted(json.load(sys.stdin))))')"

# ---- 2. hot: fan-in -------------------------------------------------------------------
new_repo h1
put src/leaf.ts 'export const leaf = 1\n'
commit_all leaf
run_rs -C "$REPO"
assert_eq "hot low - a leaf module nobody imports" 1 "$(jget dims.hot)"

new_repo h2
G checkout -q master
put src/shared.ts 'export const x = 1\n'
for i in $(seq 1 31); do put "src/users/u$i.ts" "import { x } from '../shared'\nexport const u$i = x\n"; done
commit_all consumers
G checkout -q feature && G merge -q master
put src/shared.ts 'export const x = 2\n'
commit_all change-shared
run_rs -C "$REPO"
assert_eq "hot high - 31 importers" 5 "$(jget dims.hot)"
assert_out_has "hot high - driver names the fan-in" "fan-in 31"

new_repo h2b
G checkout -q master
put src/shared.ts 'export const x = 1\n'
for i in $(seq 1 9); do put "src/users/u$i.ts" "import { x } from './shared'\n"; done
commit_all consumers
G checkout -q feature && G merge -q master
put src/shared.ts 'export const x = 2\n'
commit_all change-shared
run_rs -C "$REPO"
assert_eq "hot mid - 9 importers" 3 "$(jget dims.hot)"

# ---- 3. hot: churn counts only the 90 days before the change --------------------------
new_repo h3
G checkout -q master
for i in $(seq 1 9); do
  printf 'export const v = %s\n' "$i" > "$REPO/src/busy.ts"
  G add -A && G commit -q -m "busy $i"
done
G checkout -q feature && G merge -q master
printf 'export const v = 99\n' > "$REPO/src/busy.ts"
commit_all change-busy
run_rs -C "$REPO"
assert_eq "hot churn - 9 recent commits" 3 "$(jget dims.hot)"
assert_out_has "hot churn - driver names the churn" "churn 9"

new_repo h3b
G checkout -q master
for i in $(seq 1 9); do
  printf 'export const v = %s\n' "$i" > "$REPO/src/busy.ts"
  G add -A
  GIT_AUTHOR_DATE="2020-01-0${i}T00:00:00Z" GIT_COMMITTER_DATE="2020-01-0${i}T00:00:00Z" G commit -q -m "old busy $i"
done
printf 'x\n' > "$REPO/src/other.ts"; G add -A && G commit -q -m recent
G checkout -q feature && G merge -q master
printf 'export const v = 99\n' > "$REPO/src/busy.ts"
commit_all change-busy
run_rs -C "$REPO"
assert_eq "hot churn - commits older than 90 days do not count" 1 "$(jget dims.hot)"

# ---- 4. hot: entry points and the shared-library floor ------------------------------------
new_repo h4
put src/handler.ts 'export const handler = async () => 1\n'
commit_all handler
run_rs -C "$REPO"
assert_eq "hot - handler path is an entry point" 4 "$(jget dims.hot)"
new_repo h4b
put src/main/java/acme/OrderResource.java 'class OrderResource {}\n'
commit_all resource
run_rs -C "$REPO"
assert_eq "hot - *Resource.java is an entry point" 4 "$(jget dims.hot)"

new_repo demo-core-lib
put src/leaf.ts 'export const leaf = 1\n'
commit_all leaf
run_rs -C "$REPO"
assert_eq "hot - *-core-lib repo floors at 3" 3 "$(jget dims.hot)"
assert_out_has "hot - floor is a driver" "shared library demo-core-lib"
new_repo h4c
put docs/x.md 'prose\n'
commit_all docs
G remote add origin https://example.invalid/acme/demo-commons-lib.git
put src/leaf.ts 'export const leaf = 1\n'
commit_all leaf
run_rs -C "$REPO"
assert_eq "hot - lib name comes from the origin URL, not the directory" 3 "$(jget dims.hot)"
new_repo demo-core-lib-docs
put docs/x.md 'prose\n'
commit_all docs
mv "$REPO" "$WORK/demo-core-lib-docs-x"; REPO="$WORK/demo-core-lib-docs-x"
run_rs -C "$REPO"
assert_eq "hot - a docs-only change in a lib stays 1" 1 "$(jget dims.hot)"

# ---- 5. complexity -----------------------------------------------------------------------
new_repo x1
printf 'export const a = 2\n' > "$REPO/src/a.ts"
commit_all one-line
run_rs -C "$REPO"
assert_eq "complexity low - one line" 1 "$(jget dims.complexity)"

new_repo x2
for i in $(seq 1 15); do gen "src/d$i/f.ts" 50 '                    if (a && b) { x = y }'; done
commit_all big
run_rs -C "$REPO"
assert_eq "complexity high - 750 deep branching lines in 15 dirs" 5 "$(jget dims.complexity)"
assert_out_has "complexity high - driver names the lines" "source lines changed"

new_repo x3
gen src/flat.ts 30 'const v%d = 1'
commit_all flat
run_rs -C "$REPO"
assert_eq "complexity mid - 30 flat lines" 1 "$(jget dims.complexity)"

new_repo x4
gen src/big.test.ts 800 '        if (a && b) { x = y }'
commit_all big-test
run_rs -C "$REPO"
assert_eq "complexity ignores test files" 1 "$(jget dims.complexity)"

new_repo x5
gen src/new.ts 300 '            if (a && b) { x = y }'
run_rs -C "$REPO"   # uncommitted: untracked file counts
assert_ge "complexity counts untracked files" 4 "$(jget dims.complexity)"

# ---- 6. config ---------------------------------------------------------------------------
new_repo f1
put infra/iam.tf 'resource "aws_iam_role" "r" {\n  name = "demo"\n  assume_role_policy = "a"\n}\n'
put infra/bucket.tf 'resource "aws_s3_bucket" "b" {\n  bucket = "demo-bucket"\n  tags = {\n    Team = "a"\n  }\n}\n'
G add -A && G commit -q -m infra
G checkout -q master && G merge -q feature && G checkout -q -b feature2
put infra/bucket.tf 'resource "aws_s3_bucket" "b" {\n  bucket = "demo-bucket"\n  tags = {\n    Team = "b"\n  }\n}\n'
commit_all tag
run_rs -C "$REPO"
assert_eq "config low - a tag-only terraform change" 1 "$(jget dims.config)"
put infra/iam.tf 'resource "aws_iam_role" "r" {\n  name = "demo"\n  assume_role_policy = "b"\n}\n'
commit_all iam
run_rs -C "$REPO" infra/iam.tf
assert_eq "config mid - an IAM change" 3 "$(jget dims.config)"
assert_out_has "config mid - driver names the resource kind" "aws_iam_role"

new_repo f2
put infra/main.tf 'resource "aws_iam_role" "r" {\n  name = "d"\n}\nresource "aws_dynamodb_table" "t" {\n  name = "d"\n}\nresource "aws_sqs_queue" "q" {\n  name = "d"\n}\nresource "aws_sns_topic" "n" {\n  name = "d"\n}\n'
put config/application.yml 'quarkus:\n  log: debug\n'
commit_all infra
run_rs -C "$REPO"
assert_eq "config high - four high-risk resources plus app config" 5 "$(jget dims.config)"

new_repo f3
put package.json '{\n  "name": "demo",\n  "dependencies": {\n    "left-pad": "^1.0.0"\n  }\n}\n'
G add -A && G commit -q -m pkg && G checkout -q master && G merge -q feature && G checkout -q -b feature2
put package.json '{\n  "name": "demo",\n  "dependencies": {\n    "left-pad": "^1.1.0"\n  }\n}\n'
commit_all bump
run_rs -C "$REPO"
assert_eq "config - a version bump counts" 2 "$(jget dims.config)"
new_repo f3b
put pnpm-lock.yaml 'lockfileVersion: 9\n'
commit_all lock
run_rs -C "$REPO"
assert_eq "config - a lockfile does not count" 1 "$(jget dims.config)"
new_repo f4
put src/env.ts 'export const t = process.env.DEMO_TABLE_NAME\n'
commit_all env
run_rs -C "$REPO"
assert_eq "config - an env-var key added" 2 "$(jget dims.config)"
new_repo f5
put docs/order.v1.json '{}\n'
commit_all schema
run_rs -C "$REPO"
assert_eq "config - a *.v1.json schema" 3 "$(jget dims.config)"

# ---- 7. review gap, pre-review -------------------------------------------------------------
new_repo g1
printf 'export const a = 2\n' > "$REPO/src/a.ts"
printf 'test("a", () => {})\n' > "$REPO/src/a.test.ts"
commit_all with-test
run_rs -C "$REPO"
assert_eq "gap low - source with a sibling test" 1 "$(jget dims.reviewGap)"

new_repo g2
gen src/big.ts 500 'export const v%d = 1'
put infra/iam.tf 'resource "aws_iam_role" "r" {\n  name = "d"\n}\n'
gen dist/bundle.js 600 'var v%d = 1;'
commit_all untested-big
run_rs -C "$REPO"
assert_eq "gap high - 500 untested lines, IAM without a test, generated files mixed in" 4 "$(jget dims.reviewGap)"
assert_out_has "gap high - names the untested files" "have no sibling test change"

new_repo g3
printf 'export const a = 2\n' > "$REPO/src/a.ts"
commit_all untested
run_rs -C "$REPO"
assert_eq "gap mid - an untested source change" 3 "$(jget dims.reviewGap)"

# a test covers a source file only when the stems are equal, not when one contains the other
new_repo g4
printf 'export const u = 2\n' > "$REPO/src/util.ts"
printf 'test("u", () => {})\n' > "$REPO/src/utilities.test.ts"
commit_all substring-test
run_rs -C "$REPO"
assert_out_has "untested - utilities.test.ts does not cover util.ts" "1 of 1 changed source files have no sibling test change"
new_repo g5
printf 'export const u = 2\n' > "$REPO/src/util.ts"
printf 'test("u", () => {})\n' > "$REPO/src/util.test.ts"
commit_all exact-test
run_rs -C "$REPO"
assert_out_lacks "untested - util.test.ts covers util.ts" "have no sibling test change"
new_repo g6
mkdir -p "$REPO/src/main/java" "$REPO/src/test/java"
printf 'class Foo {}\n' > "$REPO/src/main/java/Foo.java"
printf 'class FooTest {}\n' > "$REPO/src/test/java/FooTest.java"
printf 'class Latest {}\n' > "$REPO/src/main/java/La.java"
commit_all java-test
run_rs -C "$REPO"
assert_out_has "untested - FooTest.java covers Foo.java but not La.java" "1 of 2 changed source files have no sibling test change"

# ---- 8. overall score ----------------------------------------------------------------------
# max - 1 floor: one config 5, the rest low; the weighted mean alone would round to 2
new_repo o1
put infra/main.tf 'resource "aws_iam_role" "r" {\n  name = "d"\n}\nresource "aws_dynamodb_table" "t" {\n  name = "d"\n}\nresource "aws_sqs_queue" "q" {\n  name = "d"\n}\nresource "aws_sns_topic" "n" {\n  name = "d"\n}\n'
put config/application.yml 'quarkus:\n  log: debug\n'
commit_all infra
run_rs -C "$REPO"
assert_eq "floor - dims" "hot=1 complexity=1 config=5 gap=2" "$(dims)"
assert_eq "floor - score is max(dim) - 1, not the rounded mean" 4 "$(jget score)"
assert_lt "floor - the weighted mean alone would be lower" 3 "$(python3 -c 'print(int(.3*1+.25*1+.2*5+.25*2+.5))')"

# unknown -> 3
run_rs -C "$WORK/nogit-dir-that-is-not-there"
assert_eq "git failure - exit 0" 0 "$RC"
assert_eq "git failure - all four dims unknown" "hot | complexity | config | reviewGap" "$(jget unknown)"
assert_eq "git failure - each unknown dim counts as 3" "hot=3 complexity=3 config=3 gap=3" "$(dims)"
assert_eq "git failure - score 3" 3 "$(jget score)"
assert_out_has "git failure - errors reported" '"errors"'
mkdir -p "$WORK/plain"; run_rs -C "$WORK/plain"
assert_eq "not a repo - unknown, score 3" "3 hot | complexity | config | reviewGap" "$(jget score) $(jget unknown)"
new_repo o2
run_rs -C "$REPO" --base no-such-branch
assert_eq "missing base - unknown, never a clean 1" "3 hot | complexity | config | reviewGap" "$(jget score) $(jget unknown)"
new_repo o3
put docs/x.md 'prose\n'
commit_all docs
run_rs -C "$REPO" --fanout "$WORK/does-not-exist.json"
assert_eq "unreadable fanout - reviewGap unknown" reviewGap "$(jget unknown)"
assert_eq "unreadable fanout - reviewGap counts as 3" 3 "$(jget dims.reviewGap)"
assert_eq "unreadable fanout - the other dims keep their values" "hot=1 complexity=1 config=1 gap=3" "$(dims)"
assert_out_has "unreadable fanout - error reported" "fanout:"

# ---- 9. --range ------------------------------------------------------------------------------
new_repo r1
put docs/x.md 'prose\n'
commit_all docs
put infra/iam.tf 'resource "aws_iam_role" "r" {\n  name = "d"\n}\n'
commit_all iam
put infra/extra.tf 'resource "aws_dynamodb_table" "t" {\n}\nresource "aws_sqs_queue" "q" {\n}\nresource "aws_sns_topic" "n" {\n}\n'   # untracked: outside the range
run_rs -C "$REPO" --range HEAD~1..HEAD
assert_eq "range - scores only the range" 3 "$(jget dims.config)"
run_rs -C "$REPO" --range HEAD~2..HEAD~1
assert_eq "range - an earlier docs-only range" 1 "$(jget dims.config)"
run_rs -C "$REPO" --range HEAD~1..HEAD infra/iam.tf
assert_eq "range - FILE restriction" 3 "$(jget dims.config)"
run_rs -C "$REPO" --range HEAD~1..no-such-rev
assert_eq "range - unknown revision is unknown, not clean" "3 hot | complexity | config | reviewGap" "$(jget score) $(jget unknown)"
run_rs -C "$REPO" --range HEAD~1
assert_eq "range - one-sided range is a usage error" 2 "$RC"
run_rs -C "$REPO" --range HEAD~1...HEAD
assert_eq "range - three dots is a usage error" 2 "$RC"
run_rs -C "$REPO" --range HEAD~1..HEAD --base master
assert_eq "range - with --base is a usage error" 2 "$RC"

# ---- 10. --fanout -----------------------------------------------------------------------------
new_repo n1
put infra/iam.tf 'resource "aws_iam_role" "r" {\n  name = "d"\n}\n'
printf 'export const a = 2\n' > "$REPO/src/a.ts"
printf 'test("a", () => {})\n' > "$REPO/src/a.test.ts"
commit_all iam-with-test
CLEAN='{"actionable":[],"informational":[],"refuted":[],"reviewersSkipped":[],"reviewersGated":[]}'
GATED='{"actionable":[],"informational":[],"refuted":[],"reviewersSkipped":[],"reviewersGated":[{"key":"data-side-effects","reason":"no persistence signal"}]}'
printf '%s' "$CLEAN" > "$WORK/clean.json"
printf '%s' "$GATED" > "$WORK/gated.json"
run_rs -C "$REPO"
assert_eq "fanout - pre phase without --fanout, gap" 1 "$(jget dims.reviewGap)"
run_rs -C "$REPO" --fanout "$WORK/clean.json"
assert_eq "fanout - final phase" final "$(jget phase)"
assert_eq "fanout - a clean review leaves the gap low" 1 "$(jget dims.reviewGap)"
run_rs -C "$REPO" --fanout "$WORK/gated.json"
assert_eq "fanout - data-side-effects gated on a config>=3 change floors the gap at 4" 4 "$(jget dims.reviewGap)"
assert_out_has "fanout - driver names the gated reviewer" "gated off on a config-risk dim: data-side-effects"
printf '%s' '{"actionable":[],"informational":[],"refuted":[],"reviewersSkipped":[],"reviewersGated":[{"key":"performance","reason":"no perf signal"}]}' > "$WORK/gated-perf.json"
run_rs -C "$REPO" --fanout "$WORK/gated-perf.json"
assert_eq "fanout - performance gated while hot is low is no gap" 1 "$(jget dims.reviewGap)"

# the same result in the three input shapes scores identically
printf '{"summary":"s","agentCount":3,"logs":[],"result":%s}' "$GATED" > "$WORK/wrapped.json"
printf 'log line {not json}\nResult: %s\ntrailing {"x": 1}\n' "$GATED" > "$WORK/embedded.txt"
run_rs -C "$REPO" --fanout "$WORK/gated.json";    bare="$OUT"
run_rs -C "$REPO" --fanout "$WORK/wrapped.json";  wrapped="$OUT"
run_rs -C "$REPO" --fanout "$WORK/embedded.txt";  embedded="$OUT"
assert_eq "fanout - wrapped shape matches bare" "$bare" "$wrapped"
assert_eq "fanout - embedded shape matches bare" "$bare" "$embedded"
printf 'no result here' > "$WORK/garbage.txt"
run_rs -C "$REPO" --fanout "$WORK/garbage.txt"
assert_eq "fanout - unparseable input leaves reviewGap unknown" reviewGap "$(jget unknown)"

new_repo n2
put docs/x.md 'prose\n'
commit_all docs
python3 - "$WORK" <<'PY'
import json, sys
w = sys.argv[1]
act = lambda n, r=False: [{"severity": "HIGH", "file": "src/a.ts", "line": i, "description": "d", "source": "functional", "verified": True, **({"resolved": True} if r else {})} for i in range(n)]
base = {"informational": [], "refuted": [], "reviewersSkipped": [], "reviewersGated": []}
json.dump({**base, "actionable": act(5)}, open(w + "/open.json", "w"))
json.dump({**base, "actionable": act(5, True)}, open(w + "/resolved.json", "w"))
json.dump({**base, "actionable": [], "reviewersSkipped": ["performance"]}, open(w + "/skipped.json", "w"))
json.dump({**base, "actionable": [], "files": ["src/other.ts"]}, open(w + "/files.json", "w"))
json.dump({**base, "actionable": act(1), "refuted": act(4)}, open(w + "/refuted.json", "w"))
PY
run_rs -C "$REPO" --fanout "$WORK/open.json"
assert_ge "fanout - five unresolved actionable findings raise the gap" 2 "$(jget dims.reviewGap)"
assert_out_has "fanout - driver counts them" "5 actionable finding(s) from review"
run_rs -C "$REPO" --fanout "$WORK/resolved.json"
assert_eq "fanout - resolved findings do not count" 1 "$(jget dims.reviewGap)"
run_rs -C "$REPO" --fanout "$WORK/skipped.json"
assert_out_has "fanout - a skipped reviewer is a driver" "reviewers returned nothing: performance"
run_rs -C "$REPO" --fanout "$WORK/files.json"
assert_out_has "fanout - diff files outside the reviewed list are a driver" "not in the fanout's reviewed list"
run_rs -C "$REPO" --fanout "$WORK/refuted.json"
assert_out_has "fanout - a high refuted ratio is a driver" "4 of 5 findings refuted"

# the workflow returns its reviewed `files`; a diff file missing from it is a driver
new_repo n3
put docs/x.md 'prose\n'
put docs/y.md 'prose\n'
commit_all two-docs
BASE3='"actionable":[],"informational":[],"refuted":[],"reviewersSkipped":[],"reviewersGated":[]'
printf '{%s,"files":["docs/x.md","docs/y.md"]}' "$BASE3" > "$WORK/files-all.json"
printf '{%s,"files":["docs/x.md"]}' "$BASE3" > "$WORK/files-missing-one.json"
printf '{"summary":"s","logs":[],"result":{%s,"files":["docs/x.md"]}}' "$BASE3" > "$WORK/files-missing-one-wrapped.json"
run_rs -C "$REPO" --fanout "$WORK/files-all.json"
assert_out_lacks "fanout files - a full reviewed list raises nothing" "not in the fanout's reviewed list"
run_rs -C "$REPO" --fanout "$WORK/files-missing-one.json"
assert_out_has "fanout files - one diff file missing from files is a driver" "1 diff file(s) not in the fanout's reviewed list"
run_rs -C "$REPO" --fanout "$WORK/files-missing-one-wrapped.json"
assert_out_has "fanout files - same for the wrapped shape" "1 diff file(s) not in the fanout's reviewed list"
printf '{%s,"files":"docs/x.md"}' "$BASE3" > "$WORK/files-bad.json"
run_rs -C "$REPO" --fanout "$WORK/files-bad.json"
assert_eq "fanout files - a non-list files leaves reviewGap unknown, exit 0" "0 reviewGap" "$RC $(jget unknown)"
assert_eq "review-fanout.js returns files" 1 "$(grep -c '^return { .*reviewersGated, files }' "$HERE/../../workflows/review-fanout.js")"

# a relative --fanout path is resolved before -C changes directory
printf '%s' "$GATED" > "$WORK/rel-gated.json"
new_repo n4
put infra/iam.tf 'resource "aws_iam_role" "r" {\n  name = "d"\n}\n'
commit_all iam
( cd "$WORK" && "$RS" -C "$REPO" --fanout rel-gated.json 2>/dev/null </dev/null ) > "$WORK/rel.out"; OUT=$(cat "$WORK/rel.out")
assert_eq "fanout - a relative path works from another cwd" "final" "$(jget phase)"
assert_eq "fanout - a relative path is read, not an error" "" "$(printf '%s' "$OUT" | grep -o '"errors"')"
assert_out_has "fanout - the relative file's gated reviewer is seen" "gated off on a config-risk dim: data-side-effects"

# malformed fields give reviewGap unknown, never a traceback
printf '%s' '{"actionable":[],"informational":[],"refuted":[],"reviewersSkipped":3,"reviewersGated":[]}' > "$WORK/skipped-int.json"
printf '%s' '{"actionable":[],"informational":[],"refuted":[],"reviewersSkipped":[],"reviewersGated":"x"}' > "$WORK/gated-str.json"
for f in skipped-int gated-str; do
  run_rs -C "$REPO" --fanout "$WORK/$f.json"
  assert_eq "fanout malformed ($f) - exit 0, reviewGap unknown, counted 3" "0 reviewGap 3" "$RC $(jget unknown) $(jget dims.reviewGap)"
  assert_eq "fanout malformed ($f) - no traceback" 0 "$(printf '%s\n' "$ERR" | grep -c Traceback)"
  assert_out_has "fanout malformed ($f) - names the field" "is not a list"
done

# ---- 11. --pr ----------------------------------------------------------------------------------------
new_repo p1
put docs/x.md 'prose\n'
commit_all docs
HEAD_SHA=$(git -C "$REPO" rev-parse HEAD)
rm -f "$AWS_LOG.pr"
FAKE_PR_HEAD="$HEAD_SHA" FAKE_PR_APPROVALS=1 run_rs -C "$REPO" --pr 12 -R acme/demo-orders-svc
assert_eq "pr - head equals the reviewed SHA, one approval: no gap" 1 "$(jget dims.reviewGap)"
assert_eq "pr - nothing unknown" "" "$(jget unknown)"
assert_eq "pr - the PR number and repo reach pr-context" "12 --json -R acme/demo-orders-svc" "$(cat "$AWS_LOG.pr")"
FAKE_PR_HEAD="$HEAD_SHA" FAKE_PR_THREADS=5 FAKE_PR_APPROVALS=0 run_rs -C "$REPO" --pr 12
assert_eq "pr - five threads and no human approval raise the gap (a bot approval does not count)" 2 "$(jget dims.reviewGap)"
assert_out_has "pr - driver counts the threads" "5 unresolved review thread(s)"
FAKE_PR_HEAD="0000000000000000000000000000000000000000" FAKE_PR_APPROVALS=1 run_rs -C "$REPO" --pr 12
assert_eq "pr - head SHA differs from the reviewed SHA forces 5" 5 "$(jget dims.reviewGap)"
assert_eq "pr - SHA mismatch lifts the score to max-1" 4 "$(jget score)"
assert_out_has "pr - driver says the head moved" "is not the reviewed SHA"
FAKE_PR_HEAD="0000000000000000000000000000000000000000" run_rs -C "$REPO" --range HEAD~1..HEAD --pr 12
assert_eq "pr - with --range the reviewed SHA is the range end" 5 "$(jget dims.reviewGap)"
FAKE_PR_HEAD="$HEAD_SHA" FAKE_PR_RC=2 run_rs -C "$REPO" --pr 12
assert_eq "pr - pr-context failure leaves reviewGap unknown" reviewGap "$(jget unknown)"
assert_eq "pr - failed pr lookup counts as at least 3" 3 "$(jget dims.reviewGap)"
assert_out_has "pr - failure reported" "pr: pr-context exit 2"
FAKE_PR_HEAD="0000000000000000000000000000000000000000" FAKE_PR_RC=2 run_rs -C "$REPO" --pr 12
assert_eq "pr - failure is not a silent clean" "reviewGap" "$(jget unknown)"
FAKE_PR_HEAD="$HEAD_SHA" FAKE_PR_BAD_REVIEW=1 run_rs -C "$REPO" --pr 12
assert_eq "pr - a non-dict review entry: exit 0, reviewGap unknown, counted 3" "0 reviewGap 3" "$RC $(jget unknown) $(jget dims.reviewGap)"
assert_eq "pr - a non-dict review entry: no traceback" 0 "$(printf '%s\n' "$ERR" | grep -c Traceback)"
assert_out_has "pr - a non-dict review entry: reported" "pr-context output is not the expected JSON"

# ---- 12. --live -----------------------------------------------------------------------------------------
new_repo demo-orders-svc
put src/handler.ts 'export const handler = async () => 1\n'
commit_all handler
rm -f "$AWS_LOG" "$AWS_LOG.target"
FAKE_SUM=56000000 run_rs -C "$REPO" --live
assert_eq "live - status ok" ok "$(jget live.status)"
assert_eq "live - 56M over 7 days is 8M per day" 8000000 "$(jget live.perDay)"
assert_eq "live - 8M/day lifts a level-4 entry point to 5" 5 "$(jget dims.hot)"
assert_out_has "live - driver cites invocations" "8.0M invocations/day in prod"
assert_eq "live - aws-target was asked for prod only" "prod" "$(cat "$AWS_LOG.target")"
assert_eq "live - exactly two AWS calls" 2 "$(wc -l < "$AWS_LOG" | tr -d ' ')"
assert_eq "live - only get-function and get-metric-statistics" 0 "$(grep -vcE '^demo-prod-readonly --profile demo-prod-readonly (lambda get-function|cloudwatch get-metric-statistics) ' "$AWS_LOG")"
assert_eq "live - the profile aws-target chose is used" 2 "$(grep -c '^demo-prod-readonly ' "$AWS_LOG")"
assert_eq "live - --profile is passed explicitly on both aws calls" 2 "$(grep -c -- '--profile demo-prod-readonly ' "$AWS_LOG")"
assert_eq "live - function name is the repo name, in us-west-2" 2 "$(grep -c -- '--region us-west-2' "$AWS_LOG")"
assert_eq "live - function name is the repo name" 2 "$(grep -c 'demo-orders-svc' "$AWS_LOG")"
assert_eq "live - 7 days of daily Sum on AWS/Lambda Invocations" 1 "$(grep -c -- '--namespace AWS/Lambda --metric-name Invocations .*--period 86400 --statistics Sum' "$AWS_LOG")"

FAKE_SUM=14000000 run_rs -C "$REPO" --live
assert_eq "live - 14M over 7 days is 2M per day, level 4 like the entry point" "2000000 4" "$(jget live.perDay) $(jget dims.hot)"
FAKE_SUM=350 run_rs -C "$REPO" --live
assert_eq "live - low traffic never lowers the static score" 4 "$(jget dims.hot)"
run_rs -C "$REPO"
assert_eq "live - without --live there is no live key" "" "$(printf '%s' "$OUT" | grep -o '"live"')"

rm -f "$AWS_LOG" "$AWS_LOG.env"
AWS_ACCESS_KEY_ID=leakkey AWS_SECRET_ACCESS_KEY=leaksecret AWS_SESSION_TOKEN=leaktoken FAKE_SUM=1 run_rs -C "$REPO" --live
assert_eq "live - credential env vars are dropped from both aws calls" "2 0" \
  "$(wc -l < "$AWS_LOG.env" | tr -d ' ') $(grep -vc 'key=unset secret=unset token=unset' "$AWS_LOG.env")"

rm -f "$AWS_LOG"
FAKE_TARGET_RC=2 run_rs -C "$REPO" --live
assert_eq "live - aws-target failure: live unknown" unknown "$(jget live.status)"
assert_out_has "live - aws-target failure: reason names the exit code" "aws-target prod exit 2"
assert_eq "live - aws-target failure: hot is the static value" 4 "$(jget dims.hot)"
assert_eq "live - aws-target failure: hot is not in unknown" "" "$(jget unknown)"
assert_eq "live - aws-target failure: no AWS call was made" 0 "$([ -f "$AWS_LOG" ] && wc -l < "$AWS_LOG" | tr -d ' ' || echo 0)"
FAKE_FN_MISSING=1 run_rs -C "$REPO" --live
assert_eq "live - no such function: live unknown" unknown "$(jget live.status)"
assert_out_has "live - no such function: reason" "no Lambda function named demo-orders-svc in us-west-2"
assert_eq "live - no such function: hot is the static value" 4 "$(jget dims.hot)"
FAKE_METRIC_FAIL=1 run_rs -C "$REPO" --live
assert_eq "live - metric failure: live unknown" unknown "$(jget live.status)"
RISK_SCORE_AWS="$WORK/no-such-aws" run_rs -C "$REPO" --live
assert_eq "live - missing aws binary: live unknown" unknown "$(jget live.status)"
RISK_SCORE_AWS_TARGET="$WORK/no-such-target" run_rs -C "$REPO" --live
assert_eq "live - missing aws-target: live unknown" unknown "$(jget live.status)"
assert_eq "live - missing aws-target: score is the static one" 4 "$(jget dims.hot)"

new_repo demo-core-lib-live
put src/leaf.ts 'export const leaf = 1\n'
commit_all leaf
mv "$REPO" "$WORK/demo-core-lib"; REPO="$WORK/demo-core-lib"
FAKE_FN_MISSING=1 run_rs -C "$REPO" --live
assert_eq "live - a lib with no function reports live unknown" unknown "$(jget live.status)"
assert_eq "live - a lib with no function still gets the floor" 3 "$(jget dims.hot)"
run_rs -C "$WORK/plain" --live
assert_eq "live - unreadable repo: live unknown" unknown "$(jget live.status)"
assert_eq "live - docs-only change ignores prod traffic" 1 "$(FAKE_SUM=140000000 run_rs -C "$WORK/c1" --live; jget dims.hot)"

# ---- 13. --md -----------------------------------------------------------------------------------------------
new_repo m1
put src/handler.ts 'export const handler = async () => 1\n'
commit_all handler
run_rs -C "$REPO" --md
assert_eq "md - first line is the score" '**Risk 3/5** (pre-review)' "$(printf '%s\n' "$OUT" | sed -n 1p)"
assert_eq "md - second line lists the four dims" "hot 4 | complexity 1 | config 1 | review gap 3" "$(printf '%s\n' "$OUT" | sed -n 2p)"
assert_out_has "md - drivers are bullets" "- hot: handler.ts entry point"
assert_eq "md - 6 to 8 lines at most" 1 "$([ "$(printf '%s\n' "$OUT" | wc -l)" -le 8 ] && echo 1 || echo 0)"
assert_out_lacks "md - not JSON" '{"score"'
FAKE_FN_MISSING=1 run_rs -C "$REPO" --md --live
assert_out_has "md - live unknown shown" "live: unknown (no Lambda function named"
run_rs -C "$WORK/plain" --md
assert_out_has "md - unknown dims shown with their errors" "unknown, counted as at least 3: hot, complexity, config, reviewGap ("
assert_eq "md - at most 8 lines with unknowns" 1 "$([ "$(printf '%s\n' "$OUT" | wc -l)" -le 8 ] && echo 1 || echo 0)"
run_rs -C "$REPO" --md --fanout "$WORK/clean.json"
assert_out_has "md - final phase" "(final, after review)"
run_rs -C "$WORK/c1" --md
assert_out_has "md - no drivers still prints a line" "- no notable risk inputs"

# ---- 14. usage ------------------------------------------------------------------------------------------------
run_rs --bogus
assert_eq "unknown flag - exit 2" 2 "$RC"
run_rs -C
assert_eq "missing -C value - exit 2" 2 "$RC"
run_rs --pr abc
assert_eq "non-numeric --pr - exit 2" 2 "$RC"
run_rs -R acme/demo
assert_eq "-R without --pr - exit 2" 2 "$RC"
run_rs --help
assert_eq "help - exit 0" 0 "$RC"
assert_out_has "help - prints header usage" "risk-score [-C DIR] [--base BRANCH | --range A..B]"
assert_out_lacks "help - stops at end of header" "import json"

# ---- 15. shared helpers -----------------------------------------------------------------------------------------
for f in review-signals risk-score; do
  assert_eq "$f imports lib/diff_scope" 1 "$(grep -c '^from diff_scope import' "$HERE/../$f")"
done
assert_eq "no copy of resolve_base outside lib/diff_scope" 0 "$(grep -l '^def resolve_base' "$HERE/../review-signals" "$HERE/../risk-score" "$HERE/../fanout-report" 2>/dev/null | wc -l | tr -d ' ')"

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
