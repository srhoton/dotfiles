#!/bin/bash
#
# Tests for review-signals. Each case builds a throwaway git repo with a base commit
# on master and a change on a feature branch, then checks the JSON line. Everything
# here is synthetic.
#
# Usage: bin/tests/review-signals.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
RS="$HERE/../review-signals"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
OUT=""; ERR=""; RC=0

ok()  { PASS=$((PASS + 1)); echo "PASS  $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL  $1"; echo "      $2"; echo "      stdout: $OUT" | head -5; echo "      stderr: $ERR" | head -5; }

assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi; }
assert_out_has()   { if printf '%s\n' "$OUT" | grep -qF -- "$2"; then ok "$1"; else bad "$1" "stdout missing: $2"; fi; }
assert_out_lacks() { if printf '%s\n' "$OUT" | grep -qF -- "$2"; then bad "$1" "stdout unexpectedly has: $2"; else ok "$1"; fi; }

# jget FIELD : a field of the JSON in OUT (booleans as true/false)
jget() { printf '%s' "$OUT" | python3 -c 'import json,sys; v=json.load(sys.stdin)[sys.argv[1]]; print(str(v).lower() if isinstance(v,bool) else v)' "$1" 2>/dev/null; }
signals() { assert_eq "$1 - perf" "$2" "$(jget perf)"; assert_eq "$1 - persistence" "$3" "$(jget persistence)"; }

G() { git -C "$REPO" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }

# new_repo NAME : fresh repo with README.md, a src file full of context words, base commit on master, feature branch checked out
new_repo() {
  REPO="$WORK/$1"
  mkdir -p "$REPO/src" "$REPO/docs"
  git init -q -b master "$REPO"
  printf '# readme\n' > "$REPO/README.md"
  # Context words on UNCHANGED lines: these must never count.
  printf 'const status = 1\nawait Promise.all(items.map(x => client.send(x)))\nconst schemaVersion = 2\nUpdateItem()\n\nfunction a() {}\n' > "$REPO/src/a.ts"
  G add -A && G commit -q -m base
  G checkout -q -b feature
}

run_rs() { # args... : stdout -> OUT, stderr -> ERR, exit -> RC
  local errf="$WORK/stderr.txt"
  OUT=$("$RS" "$@" 2>"$errf" < /dev/null); RC=$?
  ERR=$(cat "$errf")
}

# ---- 1. docs-only change ----------------------------------------------------------
new_repo c1
printf 'Some prose about how to write good docs.\n' >> "$REPO/docs/guide.md"
printf '\nMore words.\n' >> "$REPO/README.md"
G add -A && G commit -q -m docs
run_rs -C "$REPO"
assert_eq "docs-only - exit 0" 0 "$RC"
signals "docs-only" false false
assert_out_has "docs-only - empty match lists" '"perfMatches": []'

# ---- 2. DynamoDB UpdateItem ---------------------------------------------------------
new_repo c2
printf 'const cmd = new UpdateCommand({ TableName: t })\n' >> "$REPO/src/b.ts"
G add -A && G commit -q -m write
run_rs -C "$REPO"
signals "UpdateCommand change" false true
assert_out_has "UpdateCommand change - match names the line" "UpdateCommand"
new_repo c2b
printf 'client.send(new UpdateItemCommand(p))\n' >> "$REPO/src/b.ts"
run_rs -C "$REPO"   # uncommitted (untracked) change counts too
signals "untracked UpdateItem file" false true

# ---- 3. Promise.all loop ------------------------------------------------------------
new_repo c3
printf 'const rs = await Promise.all(ids.map(id => client.get(id)))\n' >> "$REPO/src/b.ts"
G add -A && G commit -q -m perf
run_rs -C "$REPO"
signals "Promise.all loop" true false
assert_out_has "Promise.all loop - match names the pattern" "Promise.all"
new_repo c3b
printf 'for (const id of ids) { await client.get(id) }\n' >> "$REPO/src/b.ts"
G add -A && G commit -q -m loop
run_rs -C "$REPO"
assert_eq "for-of with await - perf" true "$(jget perf)"
new_repo c3c
printf 'for (const id of ids) { total += id }\n' >> "$REPO/src/b.ts"
G add -A && G commit -q -m loop
run_rs -C "$REPO"
signals "plain loop without IO or other pattern" false false

# ---- 4. path signals ---------------------------------------------------------------------
new_repo c4
printf '{}\n' > "$REPO/docs/order.v1.json"
G add -A && G commit -q -m fixture
run_rs -C "$REPO"
signals "*.v1.json path" false true
assert_out_has "*.v1.json path - match names the path" "docs/order.v1.json"
new_repo c4b
mkdir -p "$REPO/infra"
printf 'resource "aws_dynamodb_table" "t" {}\n' > "$REPO/infra/main.tf"
printf 'resource "aws_s4_thing" "t" {}\n' > "$REPO/infra/other.tf"
G add -A && G commit -q -m tf
run_rs -C "$REPO" infra/other.tf
signals "unrelated .tf" false false
run_rs -C "$REPO" infra/main.tf
signals "aws_dynamodb_table .tf" false true

# ---- 5. context-only matches do not count ----------------------------------------------
new_repo c5
printf '// a harmless comment\n' > "$REPO/docs/note.txt"
# touch src/a.ts next to context words (status, Promise.all, schemaVersion, UpdateItem)
python3 - "$REPO/src/a.ts" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().replace("function a() {}", "function a() { return 1 }")
open(p, "w").write(s)
PY
G add -A && G commit -q -m touch
run_rs -C "$REPO" src/a.ts
signals "context-only words" false false
# the same words on a REMOVED line do count
python3 - "$REPO/src/a.ts" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().replace("UpdateItem()\n", "")
open(p, "w").write(s)
PY
run_rs -C "$REPO" src/a.ts
signals "removed UpdateItem line" false true

# ---- 6. file restriction -------------------------------------------------------------------
new_repo c6
printf 'const s = new PutCommand({})\n' >> "$REPO/src/b.ts"
printf 'prose\n' >> "$REPO/docs/x.md"
G add -A && G commit -q -m both
run_rs -C "$REPO" docs/x.md
signals "restricted to docs file" false false
run_rs -C "$REPO" docs/x.md src/b.ts
signals "restricted to both files" false true

# ---- 7. --base and fail-open on git errors -------------------------------------------------
new_repo c7
printf 'x = 1\n' >> "$REPO/docs/y.md"
G add -A && G commit -q -m docs
run_rs -C "$REPO" --base master
signals "explicit --base" false false
run_rs -C "$REPO" --base no-such-branch
assert_eq "bad base - exit 0" 0 "$RC"
signals "bad base fails open" true true
assert_out_has "bad base - error reported" '"error"'
NOGIT="$WORK/nogit"; mkdir -p "$NOGIT"
run_rs -C "$NOGIT"
assert_eq "not a repo - exit 0" 0 "$RC"
signals "not a repo fails open" true true
assert_out_has "not a repo - error reported" '"error"'
run_rs -C "$WORK/does-not-exist"
assert_eq "missing dir - exit 0" 0 "$RC"
signals "missing dir fails open" true true

# ---- 8. output is valid JSON, one line --------------------------------------------------------
new_repo c8
printf 'while (true) { await sleep(1) } // "quotes" and \\ backslash\n' >> "$REPO/src/b.ts"
G add -A && G commit -q -m odd
run_rs -C "$REPO"
if printf '%s\n' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)'; then ok "valid JSON with quotes and backslashes"; else bad "valid JSON with quotes and backslashes" "json.load failed"; fi
assert_eq "output is a single line" 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
for i in 1 2 3 4 5 6 7 8; do printf 'retry(%s)\n' "$i" >> "$REPO/src/b.ts"; done
run_rs -C "$REPO"
assert_eq "matches capped at 5" 5 "$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["perfMatches"]))')"
# the failure path is valid JSON too
run_rs -C "$NOGIT"
if printf '%s\n' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)'; then ok "valid JSON on the error path"; else bad "valid JSON on the error path" "json.load failed"; fi

# ---- 10. regression cases from a live sample of real branches ------------------------------------
# one_file NAME PATH CONTENT : commit a single new file (CONTENT via printf, so \n works) and run
one_file() {
  new_repo "$1"
  mkdir -p "$(dirname "$REPO/$2")"
  printf '%b' "$3" > "$REPO/$2"
  G add -A && G commit -q -m case
  run_rs -C "$REPO"
}

one_file r1 docs/notes.md 'how to query the cache with a stream, then set status\n'
signals ".md with query/cache/stream/status" false false
one_file r2 harness-mcp.log 'query cache stream status PutItem await Promise.all\n'
signals ".log file" false false
one_file r3 pom.xml '<?xml version="1.0"?>\n<project xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>\n'
signals "pom.xml boilerplate" false false
one_file r3b config/app.yaml 'status: ACTIVE\nschemaVersion: 2\nbatch: scan\n'
signals ".yaml is not a source file" false false
one_file r3c package.json '{"version": "1.0.0", "schema": 1}\n'
signals "package.json lines are not scanned" false false
one_file r4 src/foo.test.tsx 'screen.queryByTestId("x")\nawait Promise.all([a, b])\n'
signals "test file with queryByTestId and Promise.all" false false
one_file r4b src/__tests__/foo.ts 'await Promise.all([a, b])\n'
signals "__tests__ dir skips perf" false false
one_file r4c src/test/java/Foo.java 'repo.query(sql);\n'
signals "src/test dir skips perf" false false
one_file r4d src/foo.test.ts 'const s = new PutObjectCommand({})\n'
signals "persistence still scans test files" false true
one_file r5 src/main/java/Foo.java 'import java.util.stream.Stream;\n'
signals "java.util.stream import alone" false false
one_file r5b src/main/java/Foo.java 'String d = "Downstream"; // cache\n'
signals "Downstream and cache words" false false
one_file r6 src/repo.ts 'const rows = await db.query(sql)\n'
signals ".query( in src" true false
one_file r6a src/repo.ts 'const queryName = "x"; const scanned = 1; const batchSize = 2\n'
signals "bare query/scan/batch words" false false
one_file r6b src/repo.ts 'const cmd = new ScanCommand({})\n'
signals "ScanCommand" true false
one_file r6c src/repo.ts 'items.flatMap(i => i.tags)\n'
signals "flatMap without IO" false false
one_file r6d src/repo.ts 'ids.flatMap(id => client.get(id))\n'
signals "flatMap with IO" true false
one_file r6e src/repo.ts 'await retry(() => call())\n'
signals "retry call" true false
one_file r6f src/Foo.java 'list.parallelStream().count();\n'
signals "parallelStream" true false
one_file r7 src/svc.ts 'row.status = "ACTIVE"\n'
signals "status = in .ts source" false true
one_file r7b src/svc.ts 'if (res.status === 200) {}\n'
signals "status comparison is not a write" false false
one_file r8 src/svc.ts 'const schemaVersion: number = 2\n'
signals "schemaVersion" false true
one_file r9 src/svc.ts '// artifacts in S3\n'
signals "S3 in a comment" false false
one_file r10 src/svc.ts 'await c.send(new PutObjectCommand({}))\n'
assert_eq "PutObjectCommand - persistence" true "$(jget persistence)"
one_file r10b src/svc.ts 'const h = createHash("sha256")\n'
signals "createHash" false true
one_file r10c src/svc.ts 'const k = hashCode()\n'
signals "hash...( call" false true
one_file r10d src/svc.ts 'import { run } from "./transform/run"\n'
signals "import from a transform module" false true
one_file r10e src/svc.ts 'const out = migrateAccount(a)\n'
signals "migrate...( call" false true
one_file r11 src/order.v1.json '{}\n'
signals "*.v1.json path under src" false true
one_file r11b docs/order-schema.json '{}\n'
signals "schema-named .json path" false true
one_file r11c src/schemas/order.ts 'export const x = 1\n'
signals "schemas dir .ts path" false true
one_file r11d docs/schema-notes.md 'prose\n'
signals "schema-named .md is not a schema path" false false
one_file r11e src/db/migration/v2.md 'prose\n'
signals "migration path, any file type" false true

# ---- 9. usage -----------------------------------------------------------------------------------
run_rs --bogus
assert_eq "unknown flag - exit 2" 2 "$RC"
run_rs -C
assert_eq "missing -C value - exit 2" 2 "$RC"
run_rs --help
assert_eq "help - exit 0" 0 "$RC"
assert_out_has "help - prints header usage" "review-signals [-C DIR] [--base BRANCH] [FILE...]"
assert_out_lacks "help - stops at end of header" "import json"

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
