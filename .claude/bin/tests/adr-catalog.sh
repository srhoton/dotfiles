#!/bin/bash
#
# Tests for adr-catalog. Builds a throwaway ADR repository (3 synthetic ADRs, a
# bare "origin" and a second clone to advance it) so the branch and
# behind-origin warnings can be exercised without any network or real ADR text.
#
# Usage: bin/tests/adr-catalog.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CAT="$HERE/../adr-catalog"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
unset ADR_ROOT

check() { # NAME EXPECTED ACTUAL
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   - $1"
  else FAIL=$((FAIL + 1)); echo "FAIL - $1"; echo "  expected: $2"; echo "  actual:   $3"; fi
}
contains() { # NAME HAYSTACK NEEDLE
  case "$2" in *"$3"*) PASS=$((PASS + 1)); echo "ok   - $1" ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL - $1 (missing: $3)"; echo "  in: $(printf '%s' "$2" | head -c 1200 | tr '\n' '|')" ;; esac
}
lacks() { # NAME HAYSTACK NEEDLE
  case "$2" in *"$3"*) FAIL=$((FAIL + 1)); echo "FAIL - $1 (unexpected: $3)" ;;
    *) PASS=$((PASS + 1)); echo "ok   - $1" ;; esac
}

# ---- fixture: origin (bare) -> seed clone -> root ---------------------------------
ORIGIN="$WORK/origin.git"
SEED="$WORK/seed"
ROOT="$WORK/adr-root"
git init -q --bare -b master "$ORIGIN"
git init -q -b master "$SEED"
mkdir -p "$SEED/adrs" "$SEED/implGuides"

cat > "$SEED/adrs/20260101-alpha-widget-ADR.md" <<'EOF'
# ADR: Alpha Widget Handling

**Status:** Accepted

## Context

Synthetic context for alpha.

## Decision

Alpha widgets are handled by the alpha handler.

- Rule one for alpha.
- Rule two for alpha.
- Rule three for alpha.
- Rule four for alpha.
- Rule five for alpha.
- Rule six for alpha.
- Rule seven for alpha.

## Trade-offs Accepted

Alpha tradeoffs.
EOF
cat > "$SEED/implGuides/20260101-alpha-widget-ImplGuide.md" <<'EOF'
# Implementation Guide: Alpha Widget Handling

**Applies to:** Backend Lambda services that handle widgets
**Related ADR:** `adrs/20260101-alpha-widget-ADR.md`

## Rules

1. Use the alpha handler.

## Prohibited Patterns

Synthetic intro prose that is not a row.

| Pattern | Why Prohibited |
|---------|---------------|
| Calling `legacyAlpha()` | Replaced by the handler |
| Hand-rolled alpha parsing | Drifts from the shared parser |

Trailing prose note that is not a row.

## PR and Commit Conventions

| Not a prohibited row | Must not be captured |
|---|---|
EOF

cat > "$SEED/adrs/20260102-beta-widget-ADR.md" <<'EOF'
# ADR: Beta Widget Naming

## Decision

Beta widgets carry a beta prefix.
EOF
cat > "$SEED/implGuides/20260102-beta-widget-ImplGuide.md" <<'EOF'
# Implementation Guide: Beta Widget Naming

**Applies to:** All
**Related ADR:** `adrs/20260102-beta-widget-ADR.md`

## Prohibited Patterns

| Pattern | Why Prohibited |
| :--- | :--- |
| Unprefixed beta names | Collides with gamma names |
EOF

cat > "$SEED/adrs/20260103-gamma-gizmo-ADR.md" <<'EOF'
# ADR: Gamma Gizmo Policy

## Decision

Gamma gizmos are reviewed monthly.
EOF
# gamma has NO guide on purpose

git -C "$SEED" add -A && git -C "$SEED" commit -q -m "seed adrs"
git -C "$SEED" remote add origin "$ORIGIN"
git -C "$SEED" push -q origin master
git clone -q "$ORIGIN" "$ROOT"

run() { "$CAT" --root "$ROOT" "$@" 2>&1; }

# 1. clean catalog, no warnings
OUT=$(run --no-fetch); RCODE=$?
check    "clean: exit 0" "0" "$RCODE"
lacks    "clean: no WARN lines" "$OUT" "WARN:"
contains "header: repo path" "$OUT" "ADR repository: $ROOT"
contains "header: branch" "$OUT" "Branch: master"
contains "counts footer" "$OUT" "Loaded: 3 | with guide: 2 | IMPLGUIDE MISSING: 1"
contains "title parsed from '# ADR:' heading" "$OUT" "Title: Alpha Widget Handling"
contains "status shown when present" "$OUT" "== 20260101-alpha-widget  [Status: Accepted]"
lacks    "no status marker when absent" "$OUT" "== 20260102-beta-widget  [Status"
contains "decision first lines" "$OUT" "  Alpha widgets are handled by the alpha handler."
contains "decision truncated at 6 lines" "$OUT" "... (+2 more lines; use --show)"
lacks    "decision beyond summary omitted" "$OUT" "Rule seven for alpha"
contains "guide path derived" "$OUT" "Guide: implGuides/20260101-alpha-widget-ImplGuide.md"
contains "missing guide flagged" "$OUT" "Guide: IMPLGUIDE MISSING (implGuides/20260103-gamma-gizmo-ImplGuide.md)"
contains "applies-to value" "$OUT" "Applies to: Backend Lambda services that handle widgets"
contains "table row verbatim" "$OUT" "| Calling \`legacyAlpha()\` | Replaced by the handler |"
contains "table header+separator verbatim" "$OUT" $'| Pattern | Why Prohibited |\n|---------|---------------|'
contains "alignment-style separator verbatim" "$OUT" "| :--- | :--- |"
lacks    "tables from later sections not captured" "$OUT" "Not a prohibited row"
lacks    "prose around the table not captured (before)" "$OUT" "Synthetic intro prose"
lacks    "prose around the table not captured (after)" "$OUT" "Trailing prose note"
contains "universal marked" "$OUT" "Applies to: All [ALL: treated as applying to everything]"
contains "missing guide treated as universal" "$OUT" "[no Applies to: field - treated as applying to everything]"

# sorted order
ORDER=$(printf '%s\n' "$OUT" | grep '^== ' | sed 's/^== \([^ ]*\).*/\1/' | tr '\n' ' ')
check "ADRs sorted by slug" "20260101-alpha-widget 20260102-beta-widget 20260103-gamma-gizmo " "$ORDER"

# 2. --applies filter
OUT=$(run --no-fetch --applies frontend)
lacks    "frontend filter excludes backend-only ADR" "$OUT" "== 20260101-alpha-widget"
contains "frontend filter keeps universal ADR" "$OUT" "== 20260102-beta-widget"
contains "frontend filter keeps missing-field ADR" "$OUT" "== 20260103-gamma-gizmo"
contains "filter footer counts three groups" "$OUT" "Filter --applies frontend: applies 2, possible 0, excluded 1"
contains "excluded listed by slug + Applies-to value" "$OUT" "20260101-alpha-widget | Applies to: Backend Lambda services that handle widgets"
contains "reviewer must confirm footer" "$OUT" "REVIEWER MUST CONFIRM: the 1 excluded ADRs above were filtered by keyword only."
contains "total count unaffected by filter" "$OUT" "Loaded: 3 | with guide: 2 | IMPLGUIDE MISSING: 1"
OUT=$(run --no-fetch --applies BACKEND)
contains "backend filter (case-insensitive) keeps match" "$OUT" "== 20260101-alpha-widget"
contains "backend filter marks match" "$OUT" "[matches backend]"
contains "backend filter nothing excluded" "$OUT" "Filter --applies backend: applies 3, possible 0, excluded 0"
lacks    "no confirm footer when nothing excluded" "$OUT" "REVIEWER MUST CONFIRM"
OUT=$(run --no-fetch --applies infra)
contains "infra filter: Lambda technology makes backend ADR possible" "$OUT" "[possible: matched lambda]"
OUT=$(run --no-fetch --applies fullstack)
contains "fullstack includes backend ADRs" "$OUT" "== 20260101-alpha-widget"
run --no-fetch --applies bogus >/dev/null; check "bad --applies value exits 2" "2" "$?"

# 2b. possible group: dedicated fixture (no origin; --no-fetch)
FILT="$WORK/filter-root"
git init -q -b master "$FILT"; mkdir -p "$FILT/adrs" "$FILT/implGuides"
mk() { # SLUG TITLE APPLIES DECISION [PATTERN-ROW]
  printf '# ADR: %s\n\n## Decision\n\n%s\n' "$2" "$4" > "$FILT/adrs/$1-ADR.md"
  { printf '# Implementation Guide: %s\n\n**Applies to:** %s\n\n## Prohibited Patterns\n\n| Pattern | Why Prohibited |\n|---|---|\n' "$2" "$3"
    printf '%s\n' "${5:-| Doing it wrong | Because |}"; } > "$FILT/implGuides/$1-ImplGuide.md"
}
mk 20260301-fe "Frontend Thing" "Frontend React apps" "Use plain components."
mk 20260302-decision-only "Decision Mentions Tech" "All widget teams" "Route every widget alarm through CloudWatch."
mk 20260303-pattern-only "Pattern Mentions Tech" "Gadget owners" "Gadgets are labelled." "| Mutating gadget state without zustand set() | Bypasses reactivity |"
mk 20260304-applies-only "Applies Mentions Tech" "Teams using DynamoDB tables" "Tables are named."
mk 20260305-unrelated "Unrelated Thing" "Everyone in finance" "Finance closes monthly."
printf '# ADR: Fe\n\n## Context\n\nC1\nC2\nC3\nC4\nC5\nC6\n\n## Decision\n\nD.\n' > "$FILT/adrs/20260301-fe-ADR.md"
frun() { "$CAT" --root "$FILT" --no-fetch "$@" 2>&1; }
group() { # OUTPUT NAME  -> text of one "### NAME" group
  local rest=${1#*"### $2 ("}; rest=${rest%%$'\n'### *}; printf '%s' "$rest"; }

OUT=$(frun --applies infra)
check    "infra: group counts" "Filter --applies infra: applies 0, possible 2, excluded 3" "$(printf '%s\n' "$OUT" | grep '^Filter')"
POSS=$(group "$OUT" "POSSIBLY APPLIES")
contains "possible group shows decision-only ADR in full" "$POSS" "== 20260302-decision-only"
contains "possible: terms from Decision text" "$POSS" "[possible: matched cloudwatch, alarm]"
contains "possible group shows Decision body" "$POSS" "Route every widget alarm through CloudWatch."
contains "possible: terms from Applies-to text" "$POSS" "[possible: matched dynamodb]"
contains "possible group includes the Prohibited table" "$POSS" "| Doing it wrong | Because |"
lacks    "possible group omits excluded ADR" "$POSS" "== 20260305-unrelated"
EXC=$(group "$OUT" "EXCLUDED")
contains "excluded group lists slug + Applies-to" "$EXC" "20260305-unrelated | Applies to: Everyone in finance"
contains "excluded group lists fe ADR" "$EXC" "20260301-fe | Applies to: Frontend React apps"
lacks    "excluded ADRs are not printed in full" "$OUT" "== 20260305-unrelated"
contains "must-confirm footer counts excluded" "$OUT" "REVIEWER MUST CONFIRM: the 3 excluded ADRs above were filtered by keyword only."

OUT=$(frun --applies frontend)
check    "frontend: group counts" "Filter --applies frontend: applies 1, possible 1, excluded 3" "$(printf '%s\n' "$OUT" | grep '^Filter')"
contains "possible: terms from Prohibited Patterns only" "$(group "$OUT" "POSSIBLY APPLIES")" "[possible: matched zustand]"
contains "applies group has keyword match" "$(group "$OUT" "APPLIES")" "== 20260301-fe"
contains "applies group marker" "$(group "$OUT" "APPLIES")" "[matches frontend]"

OUT=$(frun --applies backend)
contains "backend: decision-only CloudWatch ADR possible" "$(group "$OUT" "POSSIBLY APPLIES")" "== 20260302-decision-only"
OUT=$(frun)
lacks    "no filter: no group headings" "$OUT" "### "
lacks    "no filter: no confirm footer" "$OUT" "REVIEWER MUST CONFIRM"
contains "no filter: every ADR printed" "$OUT" "== 20260305-unrelated"

# Vocabulary: every term must put a decision-only ADR in POSSIBLY APPLIES for its type
VOC="$WORK/vocab-root"
git init -q -b master "$VOC"; mkdir -p "$VOC/adrs" "$VOC/implGuides"
vocab_files() { # TERM...  (one decision-only ADR + neutral guide per term)
  find "$VOC/adrs" "$VOC/implGuides" -name '*.md' -delete
  local i=0 term slug
  for term in "$@"; do
    i=$((i + 1)); slug="2026${i}-$(printf '%s' "$term" | tr ' ' '-')"
    printf '# ADR: T\n\n## Decision\n\nWe use %s here.\n' "$term" > "$VOC/adrs/$slug-ADR.md"
    printf '# Guide\n\n**Applies to:** Everyone in finance\n' > "$VOC/implGuides/$slug-ImplGuide.md"
  done
}
vocab_case() { # TYPE TERM...  (asserts each term's ADR is possible for TYPE)
  local type=$1; shift
  vocab_files "$@"
  local i=0 term slug
  local out poss block
  out=$("$CAT" --root "$VOC" --no-fetch --applies "$type" 2>&1)
  poss=$(group "$out" "POSSIBLY APPLIES")
  i=0
  for term in "$@"; do
    i=$((i + 1)); slug="2026${i}-$(printf '%s' "$term" | tr ' ' '-')"
    block=${poss#*"== $slug"}; block=${block%%$'\n'== *}
    case "$poss" in *"== $slug"*) contains "$type vocab: '$term' is possible" "$block" "matched ${term}" ;;
      *) FAIL=$((FAIL + 1)); echo "FAIL - $type vocab: '$term' not in POSSIBLY APPLIES" ;; esac
  done
}
vocab_case infra terraform iac cloudwatch alarm eventbridge "event bus" "api gateway" apigw appsync lambda dynamodb s3 iam sqs sns "step function" sfn
vocab_case backend java quarkus api service graphql lambda appsync eventbridge dynamodb cloudwatch
vocab_case frontend react ui vite micro-frontend "module federation" zustand tailwind
vocab_case fullstack full-stack zustand java dynamodb
# word boundaries: substrings of ordinary words are not technologies
find "$VOC/adrs" "$VOC/implGuides" -name '*.md' -delete
printf '# ADR: T\n\n## Decision\n\nWe build a guide for quiet reactive classes, s3x and sqsx.\n' > "$VOC/adrs/20261-words-ADR.md"
printf '# Guide\n\n**Applies to:** Everyone in finance\n' > "$VOC/implGuides/20261-words-ImplGuide.md"
for t in frontend infra; do
  check "substrings of ordinary words do not match ($t)" "Filter --applies $t: applies 0, possible 0, excluded 1" "$("$CAT" --root "$VOC" --no-fetch --applies $t 2>&1 | grep '^Filter')"
done
# technologies of another type do not leak in
vocab_files zustand tailwind java
check "frontend/java terms excluded for infra" "Filter --applies infra: applies 0, possible 0, excluded 3" "$("$CAT" --root "$VOC" --no-fetch --applies infra 2>&1 | grep '^Filter')"

# Context summary (first 4 lines, truncation marker)
OUT=$(frun)
CTX=${OUT#*"== 20260301-fe"}; CTX=${CTX%%"== 20260302"*}
contains "context first lines shown" "$CTX" $'Context:\n  C1\n  C2\n  C3\n  C4\n  ... (+2 more lines; use --show)'
lacks    "context beyond 4 lines omitted" "$CTX" "C5"
contains "context section shown in main fixture" "$(run --no-fetch)" $'Context:\n  Synthetic context for alpha.\nDecision:'
contains "missing Context section noted" "$(run --no-fetch)" "(no Context section found)"

# 3. --show
OUT=$(run --no-fetch --show widget); RCODE=$?
check    "show ambiguous: exit 1" "1" "$RCODE"
contains "show ambiguous: lists candidate 1" "$OUT" "20260101-alpha-widget"
contains "show ambiguous: lists candidate 2" "$OUT" "20260102-beta-widget"
lacks    "show ambiguous: does not print an ADR" "$OUT" "Synthetic context for alpha"
OUT=$(run --no-fetch --show nothing-matches); RCODE=$?
check    "show none: exit 1" "1" "$RCODE"
contains "show none: lists all candidates" "$OUT" "20260103-gamma-gizmo"
OUT=$(run --no-fetch --show ALPHA); RCODE=$?
check    "show single (case-insensitive): exit 0" "0" "$RCODE"
contains "show prints full ADR" "$OUT" "Rule seven for alpha."
contains "show prints ADR context" "$OUT" "Synthetic context for alpha."
contains "show prints full guide" "$OUT" "## PR and Commit Conventions"
OUT=$(run --no-fetch --show gamma)
contains "show with missing guide says so" "$OUT" "===== IMPLGUIDE MISSING: implGuides/20260103-gamma-gizmo-ImplGuide.md"
OUT=$(run --no-fetch --show 20260102-beta-widget); RCODE=$?
check    "show exact slug wins" "0" "$RCODE"

# exact slug beats substring: a slug that is a prefix of another resolves to itself
PFX="$WORK/prefix-root"
git init -q -b master "$PFX"; mkdir -p "$PFX/adrs"
printf '# ADR: Foo\n\n## Decision\n\nFoo only.\n' > "$PFX/adrs/20260201-foo-ADR.md"
printf '# ADR: Foo Bar\n\n## Decision\n\nFoo bar.\n' > "$PFX/adrs/20260201-foo-bar-ADR.md"
OUT=$("$CAT" --root "$PFX" --no-fetch --show 20260201-foo 2>&1); RCODE=$?
check    "show exact slug that prefixes another: exit 0" "0" "$RCODE"
contains "show exact slug picks the exact ADR" "$OUT" "Foo only."
lacks    "show exact slug does not print the longer ADR" "$OUT" "Foo bar."
"$CAT" --root "$PFX" --no-fetch --show 2026020 >/dev/null 2>&1; check "show non-exact prefix of both: ambiguous" "1" "$?"

# 4. ADR_ROOT env var
OUT=$(ADR_ROOT="$ROOT" "$CAT" --no-fetch 2>&1)
contains "ADR_ROOT env honored" "$OUT" "Loaded: 3"

# 5. stray non-ADR file is reported, not silently ignored
echo "# not an adr" > "$ROOT/adrs/draft-proposal.md"
OUT=$(run --no-fetch)
contains "stray file warned" "$OUT" "WARN: 1 file(s) in adrs/ do not match *-ADR.md and were NOT loaded: draft-proposal.md"
contains "stray file not counted" "$OUT" "Loaded: 3 |"
rm "$ROOT/adrs/draft-proposal.md"

# 6. behind origin: advance origin from a second clone
SECOND="$WORK/second"
git clone -q "$ORIGIN" "$SECOND"
echo "x" > "$SECOND/adrs/20260104-delta-ADR.md"
git -C "$SECOND" add -A && git -C "$SECOND" commit -q -m "advance origin" && git -C "$SECOND" push -q origin master
OUT=$(run --no-fetch)
lacks    "--no-fetch does not see new origin commit" "$OUT" "behind origin/master"
OUT=$(run); RCODE=$?
check    "behind origin: still exit 0" "0" "$RCODE"
contains "behind origin: warns with count" "$OUT" "WARN: ADR repository is 1 commit(s) behind origin/master."
# the fetch must not have modified the working tree
check    "fetch leaves the work tree alone" "" "$(ls "$ROOT/adrs" | grep delta || true)"

# 7. not on master
git -C "$ROOT" checkout -q -b feature/some-work
OUT=$(run --no-fetch)
contains "non-master branch warns" "$OUT" "WARN: ADR repository is on branch \`feature/some-work\`, not \`master\`."
contains "non-master branch shown" "$OUT" "Branch: feature/some-work"
git -C "$ROOT" checkout -q master

# 8. offline / unreachable origin tolerated
git -C "$ROOT" remote set-url origin "$WORK/does-not-exist.git"
OUT=$(run); RCODE=$?
check    "offline fetch: exit 0" "0" "$RCODE"
contains "offline fetch: warns" "$OUT" "WARN: \`git fetch -q origin\` failed"
contains "offline fetch: catalog still printed" "$OUT" "Loaded: 3"
git -C "$ROOT" remote set-url origin "$ORIGIN"

# 9. no origin remote: warn, do not fail
git -C "$ROOT" remote remove origin
OUT=$(run); RCODE=$?
check    "no origin: exit 0" "0" "$RCODE"
contains "no origin: warns" "$OUT" "WARN: no \`origin\` remote"

# 10. repository errors
OUT=$("$CAT" --root "$WORK/nope" --no-fetch 2>&1); RCODE=$?
check    "missing root: exit 1" "1" "$RCODE"
contains "missing root: reviewer error text" "$OUT" "Error: ADR repository not found at \`$WORK/nope\`. Clone the repository before running compliance checks."
mkdir "$WORK/plain"
GIT_CEILING_DIRECTORIES="$WORK" "$CAT" --root "$WORK/plain" --no-fetch >/dev/null 2>&1
check    "non-git root: exit 1" "1" "$?"
git init -q -b master "$WORK/empty"
OUT=$("$CAT" --root "$WORK/empty" --no-fetch 2>&1); RCODE=$?
check    "no ADRs: exit 1" "1" "$RCODE"
contains "no ADRs: says so" "$OUT" "no adrs/*-ADR.md files found"

# 11. usage
"$CAT" --bogus >/dev/null 2>&1; check "unknown flag exits 2" "2" "$?"
"$CAT" --root >/dev/null 2>&1; check "flag without value exits 2" "2" "$?"
contains "-h prints header" "$("$CAT" -h)" "adr-catalog [--applies"

echo
echo "adr-catalog tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
