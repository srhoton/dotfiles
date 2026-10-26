#!/bin/bash
#
# Tests for athena-q. A stub aws (selected via ATHENA_Q_AWS) answers each
# `aws athena <subcommand>` from fixture files in $STUB_DIR: exec-N.json per
# get-query-execution poll (the last one repeats), results-first.json /
# results-<token>.json per get-query-results page, start.err to make
# start-query-execution fail. It logs every subcommand to calls.log and writes the
# --query-string it received, byte for byte, to query.txt. ATHENA_Q_SLEEP=0 skips
# sleeping and ATHENA_Q_FAKE_CLOCK advances elapsed time per poll, so the suite
# needs no wall-clock time and never touches AWS. All data is synthetic: profile
# fake-profile, workgroup wg-test, query id qid-0001, tables acme_db.orders.
#
# Usage: bin/tests/athena-q.sh        (exit 1 if any case fails)
# ATHENA_Q_UNDER_TEST=<path> runs the suite against another copy of the script
# (used for hand mutation checks).

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
Q="${ATHENA_Q_UNDER_TEST:-$HERE/../athena-q}"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

check() { # NAME EXIT-STATUS-OF-CONDITION
  if [ "$2" -eq 0 ]; then PASS=$((PASS + 1)); echo "ok   $1"
  else FAIL=$((FAIL + 1)); echo "FAIL $1"; fi
}

cat > "$WORK/aws" <<'STUB'
#!/bin/bash
D="$STUB_DIR"
[ "$1" = "athena" ] || { echo "stub aws: unexpected service: $*" >&2; exit 99; }
sub="$2"
echo "$sub" >> "$D/calls.log"
printf '%s\n' "$@" > "$D/argv-$sub.txt"
tok=""; prev=""
for a in "$@"; do
  case "$a" in --query-string=*) printf '%s' "${a#--query-string=}" > "$D/query.txt" ;; esac
  [ "$prev" = "--query-string" ] && printf '%s' "$a" > "$D/query.txt"
  [ "$prev" = "--next-token" ] && tok="$a"
  prev="$a"
done
case "$sub" in
  start-query-execution)
    if [ -e "$D/start.err" ]; then cat "$D/start.err" >&2; exit 255; fi
    echo '{"QueryExecutionId":"qid-0001"}' ;;
  get-query-execution)
    n=$(( $(cat "$D/counter" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$D/counter"
    f="$D/exec-$n.json"; [ -e "$f" ] || f=$(ls "$D"/exec-*.json | sort -t- -k2 -n | tail -1)
    case "$(cat "$f")" in
      ERROR-SSO) echo "The SSO session associated with this profile has expired or is otherwise invalid." >&2; exit 255 ;;
      ERROR) echo "Could not connect to the endpoint URL" >&2; exit 255 ;;
    esac
    cat "$f" ;;
  get-query-results)
    echo "${tok:-first}" >> "$D/pages.log"
    cat "$D/results-${tok:-first}.json" ;;
  stop-query-execution) echo '{}' ;;
  *) echo "stub aws: unexpected subcommand: $sub" >&2; exit 99 ;;
esac
STUB
chmod +x "$WORK/aws"

new_case() { STUB_DIR="$WORK/$1"; mkdir -p "$STUB_DIR"; export STUB_DIR; }
calls() { grep -c "^$1\$" "$STUB_DIR/calls.log" 2>/dev/null || true; }
no_calls() { [ ! -e "$STUB_DIR/calls.log" ]; }

# qe N STATE [REASON] -> the N-th get-query-execution answer
qe() {
  printf '{"QueryExecution":{"QueryExecutionId":"qid-0001","Status":{"State":"%s","StateChangeReason":"%s"},"Statistics":{"EngineExecutionTimeInMillis":1234,"DataScannedInBytes":1572864}}}' \
    "$2" "${3:-}" > "$STUB_DIR/exec-$1.json"
}
cell() { if [ "$1" = "NULL" ]; then printf '{}'; else printf '{"VarCharValue":"%s"}' "$1"; fi; }
row() { local out="" c; for c in "$@"; do out="$out${out:+,}$(cell "$c")"; done; printf '{"Data":[%s]}' "$out"; }
IDNAME='[{"Name":"id","Label":"id"},{"Name":"name","Label":"name"}]'
# page FILE NEXT-TOKEN-OR-EMPTY ROW...   (ROWs built with row(); COLINFO overrides the columns)
page() {
  local f=$1 next=$2 rows="" r; shift 2
  for r in "$@"; do rows="$rows${rows:+,}$r"; done
  printf '{"ResultSet":{"Rows":[%s],"ResultSetMetadata":{"ColumnInfo":%s}}%s}' \
    "$rows" "${COLINFO:-$IDNAME}" "${next:+,\"NextToken\":\"$next\"}" > "$STUB_DIR/$f"
}
H=$(row id name)

# aq ARGS... : athena-q with the stub aws, no sleeping, 1 fake second per poll
aq() { ATHENA_Q_AWS="$WORK/aws" ATHENA_Q_SLEEP=0 ATHENA_Q_FAKE_CLOCK=${CLOCK:-1} "$Q" --profile fake-profile --workgroup wg-test "$@" </dev/null; }

# --- success: status line first, header row not repeated, NULL -> empty/null -------
new_case ok
qe 1 RUNNING; qe 2 SUCCEEDED; qe 3 SUCCEEDED
page results-first.json "" "$H" "$(row 1 alpha)" "$(row 2 NULL)"
OUT=$(aq -e 'SELECT id, name FROM acme_db.orders' --tsv 2>&1); RC=$?
check "success: exit 0" $([ "$RC" -eq 0 ]; echo $?)
check "success: first line is the status line" $([ "$(echo "$OUT" | head -1)" = "athena-q: SUCCEEDED qid=qid-0001 runtime=1234ms scanned=1.5 MB" ]; echo $?)
check "success: TSV is header + rows, header not duplicated, NULL is empty" \
  $([ "$(echo "$OUT" | tail -n +2)" = "$(printf 'id\tname\n1\talpha\n2\t')" ]; echo $?)
OUT=$(aq -e 'SELECT id, name FROM acme_db.orders' --json 2>&1); RC=$?
check "success --json: list of objects with NULL as null" \
  $(echo "$OUT" | tail -n +2 | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d==[{"id":"1","name":"alpha"},{"id":"2","name":None}], d'; echo $?)
OUT=$(aq -e 'SELECT id, name FROM acme_db.orders' 2>&1)
check "success: default output is an aligned table" $(echo "$OUT" | grep -qE '^id  name$' && echo "$OUT" | grep -qE '^1   alpha$'; echo $?)

# --- SHOW-style result: first row is data, not a header --------------------------------
new_case show
qe 1 SUCCEEDED
COLINFO='[{"Name":"tab_name","Label":"tab_name"}]' page results-first.json "" "$(row orders)" "$(row customers)"
OUT=$(aq -e 'SHOW TABLES' --tsv 2>&1)
check "show: a first row that is not the column names is kept" $([ "$(echo "$OUT" | tail -n +2)" = "$(printf 'tab_name\norders\ncustomers')" ]; echo $?)

# --- pagination across 3 pages -------------------------------------------------------------
new_case pages
qe 1 SUCCEEDED
page results-first.json T1 "$H" "$(row 1 a)" "$(row 2 b)"
page results-T1.json T2 "$(row 3 c)" "$(row 4 d)"
page results-T2.json "" "$(row 5 e)"
OUT=$(aq -e 'SELECT * FROM acme_db.orders' --tsv --max-rows 100 2>&1); RC=$?
check "pages: exit 0 and all 5 rows" $([ "$RC" -eq 0 ] && [ "$(echo "$OUT" | grep -cE '^[0-9]\s')" -eq 5 ]; echo $?)
check "pages: 3 get-query-results calls using the tokens in order" $([ "$(tr '\n' ' ' < "$STUB_DIR/pages.log")" = "first T1 T2 " ]; echo $?)
check "pages: header printed once, no truncation message" $([ "$(echo "$OUT" | grep -c '^id')" -eq 1 ] && ! echo "$OUT" | grep -q 'more rows'; echo $?)

# --- --max-rows truncation -----------------------------------------------------------------------
new_case cap
qe 1 SUCCEEDED
page results-first.json "" "$H" "$(row 1 a)" "$(row 2 b)" "$(row 3 c)" "$(row 4 d)" "$(row 5 e)"
OUT=$(aq -e 'SELECT * FROM acme_db.orders' --tsv --max-rows 2 2>&1)
check "max-rows: only 2 rows shown" $([ "$(echo "$OUT" | grep -cE '^[0-9]\s')" -eq 2 ] && ! echo "$OUT" | grep -qE '^3\s'; echo $?)
check "max-rows: says how many more" $(echo "$OUT" | grep -qxF '... 3 more rows (use --out FILE)'; echo $?)
new_case cap2
qe 1 SUCCEEDED
page results-first.json T1 "$H" "$(row 1 a)" "$(row 2 b)" "$(row 3 c)"
page results-T1.json "" "$(row 4 d)" "$(row 5 e)"
OUT=$(aq -e 'SELECT * FROM acme_db.orders' --tsv --max-rows 2 2>&1)
check "max-rows: stops paging once the cap is passed" $([ "$(cat "$STUB_DIR/pages.log")" = "first" ]; echo $?)
check "max-rows: unknown remainder is shown as N+" $(echo "$OUT" | grep -qxF '... 1+ more rows (use --out FILE)'; echo $?)
page results-first.json "" "$H" "$(row 1 a)" "$(row 2 b)"
OUT=$(aq -e 'SELECT * FROM acme_db.orders' --tsv --max-rows 2 2>&1)
check "max-rows: no message when the result fits exactly" $(! echo "$OUT" | grep -q 'more rows'; echo $?)

# --- long cells are cut in the table, not in --tsv ---------------------------------------------
new_case wide
qe 1 SUCCEEDED
LONG=$(printf 'x%.0s' $(seq 1 100))
page results-first.json "" "$H" "$(row 1 "$LONG")"
OUT=$(aq -e 'SELECT * FROM acme_db.orders' 2>&1)
check "table: cell cut at 60 chars with ..." $(echo "$OUT" | grep -qE '^1   x{57}\.\.\.$'; echo $?)
OUT=$(aq -e 'SELECT * FROM acme_db.orders' --tsv 2>&1)
check "tsv: cell not cut" $(echo "$OUT" | grep -q "$LONG"; echo $?)

# --- --out: full result to the file, only path and count on stdout ------------------------
new_case outfile
qe 1 SUCCEEDED
page results-first.json T1 "$H" "$(row 1 alpha)" "$(row 2 NULL)"
page results-T1.json T2 "$(row 3 gamma)" "$(row 4 delta)"
page results-T2.json "" "$(row 5 epsilon)"
OUT=$(aq -e 'SELECT * FROM acme_db.orders' --max-rows 1 --out "$WORK/out/r.tsv" 2>&1); RC=$?
check "out: missing directory is a usage error (exit 3, no aws call)" $([ "$RC" -eq 3 ] && no_calls; echo $?)
mkdir "$WORK/out"
OUT=$(aq -e 'SELECT * FROM acme_db.orders' --max-rows 1 --out "$WORK/out/r.tsv" 2>&1); RC=$?
check "out: exit 0" $([ "$RC" -eq 0 ]; echo $?)
check "out: file has header and all 5 rows (max-rows does not apply)" $([ "$(cat "$WORK/out/r.tsv")" = "$(printf 'id\tname\n1\talpha\n2\t\n3\tgamma\n4\tdelta\n5\tepsilon')" ]; echo $?)
check "out: stdout has the path and row count, no row data" $(echo "$OUT" | grep -qF "wrote 5 rows to $WORK/out/r.tsv" && ! echo "$OUT" | grep -qE 'alpha|gamma|epsilon'; echo $?)
check "out: no temp file left behind" $([ "$(ls "$WORK/out")" = "r.tsv" ]; echo $?)
rm -f "$STUB_DIR/pages.log"
OUT=$(aq -e 'SELECT * FROM acme_db.orders' --json --out "$WORK/out/r.json" 2>&1)
check "out --json: valid JSON list of 5 objects" $(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert len(d)==5 and d[1]=={"id":"2","name":None}, d' "$WORK/out/r.json"; echo $?)

# --- FAILED / CANCELLED -----------------------------------------------------------------------
new_case failed
qe 1 RUNNING; qe 2 FAILED "SYNTAX_ERROR: line 1:8: Column 'x' cannot be resolved"
OUT=$(aq -e 'SELECT x FROM acme_db.orders' 2>&1); RC=$?
check "failed: exit 1" $([ "$RC" -eq 1 ]; echo $?)
check "failed: status line and StateChangeReason shown" $(echo "$OUT" | head -1 | grep -q '^athena-q: FAILED qid=qid-0001' && echo "$OUT" | grep -qF "Column 'x' cannot be resolved"; echo $?)
check "failed: results never fetched" $([ "$(calls get-query-results)" -eq 0 ]; echo $?)
new_case cancelled
qe 1 CANCELLED "Query cancelled by user"
OUT=$(aq -e 'SELECT 1' 2>&1); RC=$?
check "cancelled: exit 1 with reason" $([ "$RC" -eq 1 ] && echo "$OUT" | grep -qF 'Query cancelled by user'; echo $?)

# --- timeout ------------------------------------------------------------------------------------
new_case timeout
qe 1 RUNNING
OUT=$(CLOCK=100 aq -e 'SELECT 1' --timeout 300 2>&1); RC=$?
check "timeout: exit 2" $([ "$RC" -eq 2 ]; echo $?)
check "timeout: stop-query-execution called for the query" $([ "$(calls stop-query-execution)" -eq 1 ] && grep -qx 'qid-0001' "$STUB_DIR/argv-stop-query-execution.txt"; echo $?)
check "timeout: gave up at 300s of fake clock (3 polls)" $([ "$(cat "$STUB_DIR/counter")" -eq 3 ]; echo $?)
check "timeout: results never fetched" $([ "$(calls get-query-results)" -eq 0 ]; echo $?)
# A terminal state first seen at or after the deadline still gets its confirming poll.
new_case late-terminal
qe 1 RUNNING; qe 2 RUNNING; qe 3 SUCCEEDED; qe 4 SUCCEEDED
page results-first.json "" "$H" "$(row 1 a)"
OUT=$(CLOCK=100 aq -e 'SELECT 1' --timeout 250 --tsv 2>&1); RC=$?
check "late terminal: SUCCEEDED first seen past the deadline is confirmed, exit 0" $([ "$RC" -eq 0 ] && [ "$(cat "$STUB_DIR/counter")" -eq 4 ]; echo $?)
check "late terminal: the finished query is not stopped" $([ "$(calls stop-query-execution)" -eq 0 ]; echo $?)
check "late terminal: results are fetched" $([ "$(calls get-query-results)" -eq 1 ]; echo $?)
new_case late-failed
qe 1 RUNNING; qe 2 RUNNING; qe 3 FAILED "late failure"; qe 4 FAILED "late failure"
OUT=$(CLOCK=100 aq -e 'SELECT 1' --timeout 250 2>&1); RC=$?
check "late terminal: FAILED confirmed past the deadline reports exit 1, not a timeout" $([ "$RC" -eq 1 ] && [ "$(calls stop-query-execution)" -eq 0 ]; echo $?)
new_case late-flicker
qe 1 RUNNING; qe 2 RUNNING; qe 3 SUCCEEDED; qe 4 FAILED "x"; qe 5 SUCCEEDED
OUT=$(CLOCK=100 aq -e 'SELECT 1' --timeout 250 2>&1); RC=$?
check "late terminal: the grace is one poll; a flickering state times out (exit 2) after poll 4" $([ "$RC" -eq 2 ] && [ "$(cat "$STUB_DIR/counter")" -eq 4 ] && [ "$(calls stop-query-execution)" -eq 1 ]; echo $?)
new_case late-running
qe 1 RUNNING
OUT=$(CLOCK=100 aq -e 'SELECT 1' --timeout 250 2>&1); RC=$?
check "late terminal: a query still RUNNING at the deadline gets no grace poll" $([ "$RC" -eq 2 ] && [ "$(cat "$STUB_DIR/counter")" -eq 3 ]; echo $?)
# The confirming poll waits POLL_START even when the deadline has passed (the wait must not be
# clamped to the 0 seconds left), or a flickering state is polled twice back to back. ATHENA_Q_SLEEP
# would hide the amounts, so this drives wait_for_query directly with a recording sleep.
python3 -B -I - "$Q" <<'PY' >"$WORK/sleep-probe.out" 2>&1
import importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("athena_q_mod", sys.argv[1])
mod = importlib.util.module_from_spec(importlib.util.spec_from_loader("athena_q_mod", loader))
loader.exec_module(mod)
os.environ["ATHENA_Q_FAKE_CLOCK"] = "1"
os.environ.pop("ATHENA_Q_SLEEP", None)

class FakeAws:
    def __init__(self, states):
        self.states, self.n = states, 0
    def call(self, args):
        state = self.states[min(self.n, len(self.states) - 1)]
        self.n += 1
        return {"QueryExecution": {"Status": {"State": state}}}

def waits(states, timeout):
    slept = []
    mod.sleep = slept.append
    qe = mod.wait_for_query(FakeAws(states), "qid-0001", timeout)
    return slept, qe["Status"]["State"]

# deadline already passed on the first poll (fake clock: 1s per poll, timeout 1s)
assert waits(["SUCCEEDED", "SUCCEEDED"], 1) == ([mod.POLL_START], "SUCCEEDED"), waits(["SUCCEEDED", "SUCCEEDED"], 1)
# well before the deadline: the interval wait, then the confirming wait
assert waits(["RUNNING", "SUCCEEDED", "SUCCEEDED"], 100) == ([mod.POLL_START, mod.POLL_START], "SUCCEEDED")
# a non-terminal wait is still clamped to the time left: timeout 2.5 -> after poll 2 (elapsed 2) only 0.5s is left
slept, _ = waits(["RUNNING", "RUNNING", "SUCCEEDED", "SUCCEEDED"], 2.5)
assert slept[:2] == [1.0, 0.5], slept
PY
PYRC=$?
check "late confirming poll still sleeps POLL_START; ordinary waits stay clamped to the time left" $PYRC
[ "$PYRC" -eq 0 ] || sed 's/^/     | /' "$WORK/sleep-probe.out"

# --- result location in the status line --------------------------------------------------------------
new_case location
printf '{"QueryExecution":{"QueryExecutionId":"qid-0001","Status":{"State":"SUCCEEDED"},"Statistics":{"EngineExecutionTimeInMillis":1234,"DataScannedInBytes":1572864},"ResultConfiguration":{"OutputLocation":"s3://example-bucket/results/qid-0001.csv"}}}' > "$STUB_DIR/exec-1.json"
page results-first.json "" "$H" "$(row 1 a)"
OUT=$(aq -e 'SELECT 1' --tsv 2>&1); RC=$?
check "status line carries result=<S3 output location> when Athena reports one" \
  $([ "$RC" -eq 0 ] && [ "$(echo "$OUT" | head -1)" = "athena-q: SUCCEEDED qid=qid-0001 runtime=1234ms scanned=1.5 MB result=s3://example-bucket/results/qid-0001.csv" ]; echo $?)
OUT=$(aq -e 'SELECT 1' --out "$WORK/loc.tsv" 2>&1)
check "  also with --out" $(echo "$OUT" | head -1 | grep -qF 'result=s3://example-bucket/results/qid-0001.csv'; echo $?)

# --- flicker: a lone terminal state is not trusted ----------------------------------------------
new_case flicker
qe 1 RUNNING; qe 2 SUCCEEDED; qe 3 RUNNING; qe 4 SUCCEEDED; qe 5 SUCCEEDED
page results-first.json "" "$H" "$(row 1 a)"
OUT=$(aq -e 'SELECT 1' --tsv 2>&1); RC=$?
check "flicker: RUNNING,SUCCEEDED,RUNNING,SUCCEEDED,SUCCEEDED -> trusted only at poll 5" $([ "$RC" -eq 0 ] && [ "$(cat "$STUB_DIR/counter")" -eq 5 ]; echo $?)
new_case flicker2
qe 1 SUCCEEDED; qe 2 FAILED "late failure"; qe 3 FAILED "late failure"
OUT=$(aq -e 'SELECT 1' 2>&1); RC=$?
check "flicker: SUCCEEDED then FAILED, FAILED -> the confirmed state (FAILED) wins" $([ "$RC" -eq 1 ] && [ "$(cat "$STUB_DIR/counter")" -eq 3 ]; echo $?)

# --- usage errors ----------------------------------------------------------------------------------
new_case usage
RAW() { ATHENA_Q_AWS="$WORK/aws" "$Q" "$@" </dev/null; }
OUT=$(RAW --workgroup wg-test -e 'SELECT 1' 2>&1); RC=$?
check "no --profile: exit 3, names the option, no aws call" $([ "$RC" -eq 3 ] && echo "$OUT" | grep -q -- '--profile' && no_calls; echo $?)
OUT=$(RAW --profile fake-profile -e 'SELECT 1' 2>&1); RC=$?
check "no --workgroup: exit 3, names the option, no aws call" $([ "$RC" -eq 3 ] && echo "$OUT" | grep -q -- '--workgroup' && no_calls; echo $?)
AWS_PROFILE=fake-profile RAW --workgroup wg-test -e 'SELECT 1' >/dev/null 2>&1; RC=$?
check "AWS_PROFILE in the environment does not default --profile" $([ "$RC" -eq 3 ]; echo $?)
RAW --profile fake-profile --workgroup wg-test -e 'SELECT 1' -f /dev/null >/dev/null 2>&1; RC=$?
check "-e and -f together: exit 3" $([ "$RC" -eq 3 ]; echo $?)
RAW --profile fake-profile --workgroup wg-test --tsv --json -e 'SELECT 1' >/dev/null 2>&1; RC=$?
check "--tsv and --json together: exit 3" $([ "$RC" -eq 3 ]; echo $?)
RAW --profile fake-profile --workgroup wg-test -f "$WORK/does-not-exist.sql" >/dev/null 2>&1; RC=$?
check "unreadable -f file: exit 3" $([ "$RC" -eq 3 ]; echo $?)
RAW --profile fake-profile --workgroup wg-test -e '   ' >/dev/null 2>&1; RC=$?
check "empty SQL: exit 3" $([ "$RC" -eq 3 ]; echo $?)
RAW --profile fake-profile --workgroup wg-test --bogus -e 'SELECT 1' >/dev/null 2>&1; RC=$?
check "unknown option: exit 3" $([ "$RC" -eq 3 ]; echo $?)
check "usage errors made no aws call" $(no_calls; echo $?)

# --- guard: read-only statements pass (dry run shows the verdict, makes no aws call) -------------------
new_case guard
allowed() { # NAME SQL
  OUT=$(aq -n -e "$2" 2>&1); RC=$?
  check "guard allows: $1" $([ "$RC" -eq 0 ] && echo "$OUT" | grep -q 'guard: read-only'; echo $?)
}
refused() { # NAME SQL [extra athena-q args]
  OUT=$(aq -n -e "$2" "${@:3}" 2>&1); RC=$?
  check "guard refuses: $1" $([ "$RC" -eq 3 ] && echo "$OUT" | grep -q 'REFUSED'; echo $?)
}
allowed "SELECT" 'SELECT 1'
allowed "lowercase select" 'select * from acme_db.orders limit 5'
allowed "WITH ... SELECT" 'WITH t AS (SELECT 1 AS a) SELECT a FROM t'
allowed "SHOW" 'SHOW TABLES IN acme_db'
allowed "SHOW CREATE TABLE (has CREATE, still read-only)" 'SHOW CREATE TABLE acme_db.orders'
allowed "DESCRIBE" 'DESCRIBE acme_db.orders'
allowed "EXPLAIN" 'EXPLAIN SELECT 1'
allowed "VALUES" 'VALUES (1), (2)'
allowed "parenthesised SELECT" '(SELECT 1) UNION ALL (SELECT 2)'
allowed "trailing semicolon" 'SELECT 1;'
allowed "leading -- comment" $'-- fetch one row\nSELECT 1'
allowed "leading block comment" '/* DELETE FROM x; */ SELECT 1'
allowed "comment after the statement hiding DROP" $'SELECT 1 -- ; DROP TABLE t'
allowed "the word delete inside a string literal" "SELECT 'DELETE FROM t; DROP TABLE t' AS note"
allowed "an escaped quote inside a literal" "SELECT 'it''s; DELETE FROM t'"
allowed "a quoted identifier named delete" 'SELECT "delete" FROM acme_db.orders'
allowed "WITH whose literal mentions INSERT" "WITH t AS (SELECT 'insert into x' AS s) SELECT s FROM t"
refused "DELETE" 'DELETE FROM acme_db.orders WHERE id = 1'
refused "lowercase delete" 'delete from acme_db.orders'
refused "INSERT" 'INSERT INTO acme_db.orders SELECT * FROM acme_db.staging'
refused "CREATE" 'CREATE TABLE acme_db.t AS SELECT 1'
refused "DROP" 'DROP TABLE acme_db.orders'
refused "MERGE" 'MERGE INTO acme_db.orders t USING s ON t.id = s.id WHEN MATCHED THEN DELETE'
refused "ALTER" 'ALTER TABLE acme_db.orders ADD COLUMNS (c int)'
refused "UNLOAD" "UNLOAD (SELECT 1) TO 's3://example-bucket/x/' WITH (format = 'PARQUET')"
refused "UPDATE" 'UPDATE acme_db.orders SET name = 1'
refused "OPTIMIZE" 'OPTIMIZE acme_db.orders REWRITE DATA USING BIN_PACK'
refused "VACUUM" 'VACUUM acme_db.orders'
refused "MSCK" 'MSCK REPAIR TABLE acme_db.orders'
refused "WITH ... DELETE" 'WITH t AS (SELECT 1 AS id) DELETE FROM acme_db.orders WHERE id IN (SELECT id FROM t)'
refused "WITH ... INSERT" 'WITH t AS (SELECT 1 AS id) INSERT INTO acme_db.orders SELECT * FROM t'
refused "EXPLAIN ANALYZE DELETE" 'EXPLAIN ANALYZE DELETE FROM acme_db.orders'
refused "two statements (SELECT; SELECT)" 'SELECT 1; SELECT 2'
refused "two statements (SELECT; DELETE)" 'SELECT 1; DELETE FROM acme_db.orders'
refused "a statement hidden after a comment" $'SELECT 1 /* x */;\n-- again\nDROP TABLE acme_db.orders'
refused "unterminated string literal" "SELECT 'abc"
refused "unterminated block comment" 'SELECT 1 /* never closed'
refused "a comment-only statement" '-- nothing here'
# SHOW/DESCRIBE go through Athena's Hive-style DDL parser, where a backslash inside a quoted
# string escapes the next character (a quote too), so the guard cannot tell where the string ends.
refused "SHOW with a backslash inside a quoted string" "SHOW TABLES LIKE 'a\\_b'"
refused "SHOW with a backslash-escaped quote hiding a second statement" "SHOW TABLES LIKE 'x\\'; DROP TABLE acme_db.orders; --'"
refused "DESCRIBE with a backslash inside a quoted identifier" 'DESCRIBE "acme_db"."or\ders"'
refused "lowercase show with a backslash in a string" "show tables like 'a\\_b'"
OUT=$(aq -n -e "SHOW TABLES LIKE 'a\\_b'" 2>&1); RC=$?
check "  the refusal explains the Hive-style escape reason (exit 3)" $([ "$RC" -eq 3 ] && echo "$OUT" | grep -q 'backslash inside a quoted string' && echo "$OUT" | grep -q 'Hive-style'; echo $?)
new_case show-backslash
OUT=$(aq -e "SHOW TABLES LIKE 'a\\_b'" 2>&1); RC=$?
check "  a real run is refused too, with no aws call" $([ "$RC" -eq 3 ] && no_calls; echo $?)
allowed "a backslash in a SELECT string literal (Trino has no backslash escapes)" "SELECT 'a\\b' AS c"
# A -- comment ends at CR or LF in the engine's lexer (SIMPLE_COMMENT: '--' ~[\r\n]*).
refused "EXPLAIN ANALYZE, comment ended by a bare CR, then INSERT" $'EXPLAIN ANALYZE --x\rINSERT INTO t VALUES (1)'
refused "SELECT, comment ended by a bare CR, then ; DELETE" $'SELECT 1 --x\r; DELETE FROM t'
refused "EXPLAIN ANALYZE, comment ended by CRLF, then INSERT" $'EXPLAIN ANALYZE --x\r\nINSERT INTO t VALUES (1)'
refused "SELECT, comment ended by CRLF, then ; DELETE" $'SELECT 1 --x\r\n; DELETE FROM t'
refused "WITH, comment ended by CR, then DELETE" $'WITH t AS (SELECT 1 AS id) --x\rDELETE FROM acme_db.orders'
refused "two comments ended by CR, then ; DROP" $'SELECT 1 -- a\r-- b\r; DROP TABLE t'
refused "CR after a block comment, then ; DELETE" $'SELECT 1 /* x */\r; DELETE FROM t'
refused "CR as the only separator before a second statement" $'SELECT 1;\rDROP TABLE t'
refused "form feed between EXPLAIN and ANALYZE INSERT" $'EXPLAIN\fANALYZE INSERT INTO t VALUES (1)'
refused "vertical tab between EXPLAIN and ANALYZE INSERT" $'EXPLAIN\vANALYZE INSERT INTO t VALUES (1)'
refused "no-break space around INSERT in EXPLAIN ANALYZE" $'EXPLAIN ANALYZE\xc2\xa0INSERT\xc2\xa0INTO t VALUES (1)'
refused "ideographic space before DELETE as a second statement" $'SELECT 1;\xe3\x80\x80DELETE FROM t'
allowed "a comment ended by a bare CR, then more SELECT" $'SELECT 1 --x\r, 2'
allowed "a comment ended by CRLF, then more SELECT" $'SELECT 1 --x\r\n, 2'
allowed "CR inside a string literal" $'SELECT \'a\r; DELETE FROM t\' AS s'
allowed "CRLF inside a quoted identifier" $'SELECT "a\r\n--" FROM acme_db.orders'
allowed "CR inside a block comment hiding a DELETE" $'SELECT 1 /*\r; DELETE FROM t\r*/'
allowed "form feed stays inside a -- comment (the engine does not end it there)" $'SELECT 1 --x\f; DELETE FROM t'
allowed "vertical tab stays inside a -- comment" $'SELECT 1 --x\v; DELETE FROM t'
allowed "no-break space stays inside a -- comment" $'SELECT 1 --x\xc2\xa0; DELETE FROM t'
check "dry run made no aws call across all guard cases" $(no_calls; echo $?)

# --- guard in the real path: refusal never reaches aws; --allow-write does ---------------------------------
new_case guard-real
qe 1 SUCCEEDED
page results-first.json "" "$H" "$(row 1 a)"
OUT=$(aq -e 'DELETE FROM acme_db.orders WHERE id = 1' 2>&1); RC=$?
check "DELETE without --allow-write: exit 3 with the reason, nothing sent to aws" $([ "$RC" -eq 3 ] && echo "$OUT" | grep -q 'refused' && echo "$OUT" | grep -q -- '--allow-write' && no_calls; echo $?)
OUT=$(aq -e 'SELECT 1; DELETE FROM acme_db.orders' 2>&1); RC=$?
check "two statements: exit 3, nothing sent to aws" $([ "$RC" -eq 3 ] && no_calls; echo $?)
OUT=$(aq -e 'DELETE FROM acme_db.orders WHERE id = 1' --allow-write 2>&1); RC=$?
check "--allow-write permits DELETE: reaches aws, exit 0" $([ "$RC" -eq 0 ] && [ "$(calls start-query-execution)" -eq 1 ]; echo $?)
check "--allow-write prints the one-line warning on stderr" $(aq -e 'DELETE FROM acme_db.orders' --allow-write 2>&1 >/dev/null | grep -qxF 'athena-q: --allow-write: running a statement that can modify data'; echo $?)
check "--allow-write on a read-only statement stays quiet" $([ -z "$(aq -e 'SELECT 1' --allow-write 2>&1 >/dev/null)" ]; echo $?)

# --- SQL reaches aws verbatim; options map to the right flags ---------------------------------------------------
new_case verbatim
qe 1 SUCCEEDED
page results-first.json "" "$H" "$(row 1 a)"
SQL=$'-- note: $HOME "dq" `bt` \\ $(touch '"$WORK"$'/pwned)\nSELECT \'it\'\'s $PATH `x` $(touch '"$WORK"$'/pwned)\' AS "q$1"'
printf '%s' "$SQL" > "$WORK/expected.sql"
aq -e "$SQL" --database acme_db --catalog AwsDataCatalog --output-location s3://example-bucket/results/ --region eu-west-1 >/dev/null 2>&1; RC=$?
check "verbatim: exit 0" $([ "$RC" -eq 0 ]; echo $?)
check "verbatim: quotes, \$, backticks, comments and newlines arrive unchanged" $(cmp -s "$WORK/expected.sql" "$STUB_DIR/query.txt"; echo $?)
check "verbatim: nothing was shell-evaluated" $([ ! -e "$WORK/pwned" ]; echo $?)
A=$STUB_DIR/argv-start-query-execution.txt
check "argv: workgroup, profile, region flags" $(grep -qx -- '--work-group' "$A" && grep -qx 'wg-test' "$A" && grep -qx 'fake-profile' "$A" && grep -qx 'eu-west-1' "$A"; echo $?)
check "argv: database/catalog and output location as JSON" $(grep -qxF '{"Database": "acme_db", "Catalog": "AwsDataCatalog"}' "$A" && grep -qxF '{"OutputLocation": "s3://example-bucket/results/"}' "$A"; echo $?)
aq -e 'SELECT 1' >/dev/null 2>&1
check "argv: region defaults to us-west-2; no context flags unless asked" $(grep -qx 'us-west-2' "$A" && ! grep -q -- '--query-execution-context' "$A" && ! grep -q -- '--result-configuration' "$A"; echo $?)
check "argv: poll and results calls carry the query id and profile" $(grep -qx 'qid-0001' "$STUB_DIR/argv-get-query-execution.txt" && grep -qx 'fake-profile' "$STUB_DIR/argv-get-query-results.txt"; echo $?)

# --- SQL from -f and from stdin -----------------------------------------------------------------------------------------
new_case input
qe 1 SUCCEEDED
page results-first.json "" "$H" "$(row 1 a)"
printf 'SELECT id\nFROM acme_db.orders\nWHERE name = %s' "'x'" > "$WORK/q.sql"
aq -f "$WORK/q.sql" >/dev/null 2>&1; RC=$?
check "-f FILE: query sent verbatim" $([ "$RC" -eq 0 ] && cmp -s "$WORK/q.sql" "$STUB_DIR/query.txt"; echo $?)
rm -f "$STUB_DIR/query.txt"
ATHENA_Q_AWS="$WORK/aws" ATHENA_Q_SLEEP=0 ATHENA_Q_FAKE_CLOCK=1 "$Q" --profile fake-profile --workgroup wg-test < "$WORK/q.sql" >/dev/null 2>&1; RC=$?
check "stdin: query sent verbatim" $([ "$RC" -eq 0 ] && cmp -s "$WORK/q.sql" "$STUB_DIR/query.txt"; echo $?)
rm -f "$STUB_DIR/query.txt"
ATHENA_Q_AWS="$WORK/aws" ATHENA_Q_SLEEP=0 ATHENA_Q_FAKE_CLOCK=1 "$Q" --profile fake-profile --workgroup wg-test -f - < "$WORK/q.sql" >/dev/null 2>&1; RC=$?
check "-f -: reads stdin" $([ "$RC" -eq 0 ] && cmp -s "$WORK/q.sql" "$STUB_DIR/query.txt"; echo $?)
printf 'DELETE FROM acme_db.orders' | ATHENA_Q_AWS="$WORK/aws" "$Q" --profile fake-profile --workgroup wg-test >/dev/null 2>&1; RC=$?
check "guard also applies to SQL read from stdin" $([ "$RC" -eq 3 ]; echo $?)

# --- AWS errors ---------------------------------------------------------------------------------------------------------------
new_case sso
echo "The SSO session associated with this profile has expired or is otherwise invalid. To refresh this SSO session run aws sso login with the corresponding profile." > "$STUB_DIR/start.err"
OUT=$(aq -e 'SELECT 1' 2>&1); RC=$?
check "expired SSO at start: exit 4 with the exact login command" $([ "$RC" -eq 4 ] && echo "$OUT" | grep -qF 'aws sso login --profile fake-profile'; echo $?)
new_case sso-poll
qe 1 ERROR-SSO
echo ERROR-SSO > "$STUB_DIR/exec-1.json"
OUT=$(aq -e 'SELECT 1' 2>&1); RC=$?
check "expired SSO while polling: exit 4 at once (no retries), login command shown" $([ "$RC" -eq 4 ] && [ "$(cat "$STUB_DIR/counter")" -eq 1 ] && echo "$OUT" | grep -qF 'aws sso login --profile fake-profile'; echo $?)
check "  the started query's qid is printed (it may still be running)" $(echo "$OUT" | grep -q 'query qid=qid-0001 may still be running'; echo $?)
check "  a best-effort stop-query-execution is sent for it" $([ "$(calls stop-query-execution)" -eq 1 ] && grep -qx 'qid-0001' "$STUB_DIR/argv-stop-query-execution.txt"; echo $?)
check "  the qid line comes before the login hint" $([ "$(echo "$OUT" | grep -n 'may still be running' | head -1 | cut -d: -f1)" -lt "$(echo "$OUT" | grep -n 'aws sso login --profile' | head -1 | cut -d: -f1)" ]; echo $?)
new_case sso-start
echo "The SSO session associated with this profile has expired or is otherwise invalid." > "$STUB_DIR/start.err"
OUT=$(aq -e 'SELECT 1' 2>&1); RC=$?
check "expired SSO at start: no query exists, so no stop is attempted" $([ "$RC" -eq 4 ] && [ "$(calls stop-query-execution)" -eq 0 ] && ! echo "$OUT" | grep -q 'may still be running'; echo $?)
new_case awserr
echo "An error occurred (InvalidRequestException) when calling the StartQueryExecution operation: WorkGroup wg-test is not found." > "$STUB_DIR/start.err"
OUT=$(aq -e 'SELECT 1' 2>&1); RC=$?
check "other aws error: exit 4, shows the message, no login hint" $([ "$RC" -eq 4 ] && echo "$OUT" | grep -qF 'WorkGroup wg-test is not found' && ! echo "$OUT" | grep -q 'sso login'; echo $?)
new_case noprofile
echo "The config profile (fake-profile) could not be found" > "$STUB_DIR/start.err"
OUT=$(aq -e 'SELECT 1' 2>&1); RC=$?
check "unconfigured profile: exit 4, says so, no login hint" $([ "$RC" -eq 4 ] && echo "$OUT" | grep -q "not configured" && ! echo "$OUT" | grep -q 'sso login'; echo $?)
new_case transient
echo ERROR > "$STUB_DIR/exec-1.json"; qe 2 SUCCEEDED
page results-first.json "" "$H" "$(row 1 a)"
OUT=$(aq -e 'SELECT 1' --tsv 2>&1); RC=$?
check "one failed poll is retried" $([ "$RC" -eq 0 ] && [ "$(cat "$STUB_DIR/counter")" -eq 3 ]; echo $?)
new_case transient3
echo ERROR > "$STUB_DIR/exec-1.json"
OUT=$(aq -e 'SELECT 1' 2>&1); RC=$?
check "three failed polls in a row: exit 4" $([ "$RC" -eq 4 ] && [ "$(cat "$STUB_DIR/counter")" -eq 3 ]; echo $?)
check "  the query is named and a stop is attempted here too" $([ "$(calls stop-query-execution)" -eq 1 ] && echo "$OUT" | grep -q 'query qid=qid-0001 may still be running'; echo $?)
OUT=$(ATHENA_Q_AWS="$WORK/no-such-aws" ATHENA_Q_SLEEP=0 "$Q" --profile fake-profile --workgroup wg-test -e 'SELECT 1' 2>&1 </dev/null); RC=$?
check "missing aws binary: exit 4" $([ "$RC" -eq 4 ] && echo "$OUT" | grep -q 'not installed'; echo $?)

# --- dry run ----------------------------------------------------------------------------------------------------------------------
new_case dry
OUT=$(aq -n -e 'SELECT 1 AS c' --database acme_db 2>&1); RC=$?
check "dry run: exit 0, no aws call" $([ "$RC" -eq 0 ] && no_calls; echo $?)
check "dry run: prints the start-query-execution argv and the verdict" $(echo "$OUT" | grep -q 'start-query-execution' && echo "$OUT" | grep -qF 'SELECT 1 AS c' && echo "$OUT" | grep -qF 'acme_db' && echo "$OUT" | grep -q -- '--work-group wg-test' && echo "$OUT" | grep -q 'guard: read-only SELECT'; echo $?)
OUT=$(aq -n -e 'DROP TABLE acme_db.orders' --allow-write 2>&1); RC=$?
check "dry run with --allow-write: says the guard is overridden, exit 0" $([ "$RC" -eq 0 ] && echo "$OUT" | grep -q 'would refuse' && no_calls; echo $?)

echo
echo "athena-q: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
