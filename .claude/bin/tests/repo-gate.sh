#!/bin/bash
#
# Tests for repo-gate. Every case builds a synthetic git repo in a temp dir and
# puts stub runners (pnpm, mise, terraform, go, uv, gradlew, ...) on PATH via
# REPO_GATE_FAKE_BIN, so no real installs or builds happen. Fixtures are
# invented for these tests; nothing is copied from a real repository.
#
# Usage: bin/tests/repo-gate.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
GATE="$HERE/../repo-gate"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tmp"
PASS=0; FAIL=0
OUT=""; RC=0
ESC=$(printf '\033')

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

ok()  { PASS=$((PASS + 1)); echo "PASS  $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL  $1"; echo "      $2"; echo "$OUT" | sed 's/^/      | /' | head -40; }

assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi
}
assert_has() { # name needle
  if printf '%s\n' "$OUT" | grep -qF -- "$2"; then ok "$1"; else bad "$1" "output missing: $2"; fi
}
assert_lacks() { # name needle
  if printf '%s\n' "$OUT" | grep -qF -- "$2"; then bad "$1" "output unexpectedly has: $2"; else ok "$1"; fi
}
assert_file_has() { # name file needle
  if grep -qF -- "$3" "$2" 2>/dev/null; then ok "$1"; else bad "$1" "$2 missing: $3"; fi
}
assert_file_lacks() { # name file needle
  if grep -qF -- "$3" "$2" 2>/dev/null; then bad "$1" "$2 unexpectedly has: $3"; else ok "$1"; fi
}

newrepo() { # name -> path (git init, no commits)
  local d="$WORK/$1"
  mkdir -p "$d" "$WORK/bin-$1"
  git -C "$d" init -q
  printf '%s' "$d"
}

# run_gate REPO [args...] : runs repo-gate with the repo's stub bin dir
run_gate() {
  local name=$1; shift
  OUT=$(cd "$WORK" && REPO_GATE_FAKE_BIN="$WORK/bin-$name" TMPDIR="$WORK/tmp" STUB_LOG="$WORK/bin-$name/calls.log" \
        "$GATE" -C "$WORK/$name" "$@" 2>&1)
  RC=$?
}

stub() { # path ; body on stdin
  cat > "$1"
  chmod +x "$1"
}

# pnpm stub: logs every call, creates node_modules on frozen install, and
# replays canned test output/exit code from STUB_TEST_OUT / STUB_TEST_RC.
write_pnpm_stub() { # bindir
  stub "$1/pnpm" <<'EOF'
#!/bin/bash
echo "pnpm $*" >> "${STUB_LOG:-/dev/null}"
if [ "$1" = install ] && [ "${2:-}" = "--frozen-lockfile" ]; then mkdir -p node_modules; exit "${STUB_INSTALL_RC:-0}"; fi
if [ "$1" = run ] && [ "${2:-}" = test ]; then cat "$STUB_TEST_OUT"; exit "${STUB_TEST_RC:-0}"; fi
if [ "$1" = run ] && [ "${2:-}" = typecheck ]; then echo "typecheck stub"; exit "${STUB_TC_RC:-0}"; fi
if [ "$1" = exec ]; then cat "$STUB_TEST_OUT"; exit "${STUB_TEST_RC:-0}"; fi
exit 0
EOF
}

node_repo() { # name test-script [extra-package-json-fragment]
  local d; d=$(newrepo "$1")
  printf '{"name":"synthetic-app","scripts":{"test":"%s"%s}}\n' "$2" "${3:-}" > "$d/package.json"
  : > "$d/pnpm-lock.yaml"
  write_pnpm_stub "$WORK/bin-$1"
}

# fresh_nm DIR MARKER : node_modules whose install marker is newer than the lockfile
fresh_nm() {
  mkdir -p "$1/node_modules"
  local lf
  for lf in pnpm-lock.yaml package-lock.json yarn.lock; do
    if [ -f "$1/$lf" ]; then touch -t 202001010000 "$1/$lf"; fi
  done
  : > "$1/node_modules/$2"
}

JEST_PASS="$WORK/jest-pass.out"
printf 'PASS src/calc.test.ts\nTest Suites: 1 passed, 1 total\n%sTests:%s       412 passed, 412 total\n' "${ESC}[1m" "${ESC}[22m" > "$JEST_PASS"
JEST_FAIL="$WORK/jest-fail.out"
cat > "$JEST_FAIL" <<'EOF'
FAIL src/calc.test.ts
  ● calc › adds numbers

    expect(received).toBe(expected)

    Expected: 4
    Received: 5

      at Object.<anonymous> (src/calc.test.ts:5:20)

Test Suites: 1 failed, 1 total
Tests:       1 failed, 3 passed, 4 total
EOF
for i in $(seq 1 60); do echo "LATE-NOISE-LINE-$i"; done >> "$JEST_FAIL"
VITEST_FAIL="$WORK/vitest-fail.out"
cat > "$VITEST_FAIL" <<'EOF'
 FAIL  src/widget.test.ts > widget > renders label
AssertionError: expected 'a' to be 'b'

 Test Files  1 failed (1)
      Tests  1 failed | 3 passed (4)
EOF

# ---- 1. node pnpm, tests pass ---------------------------------------------------
node_repo n_pass jest
fresh_nm "$WORK/n_pass" .modules.yaml
STUB_TEST_OUT="$JEST_PASS" run_gate n_pass --no-install
assert_eq "node pass - exit code 0" 0 "$RC"
assert_has "node pass - counts parsed through ANSI codes" "node TESTS PASS"
assert_has "node pass - passed count" "412 passed, 0 failed"
assert_has "node pass - final line" "REPO-GATE: PASS"
assert_has "node pass - logs dir printed" "logs: $WORK/tmp/repo-gate."
assert_has "node pass - install skipped when node_modules present and fresh" "node INSTALL SKIPPED (0s) node_modules present"
assert_file_lacks "node pass - fresh node_modules does not reinstall" "$WORK/bin-n_pass/calls.log" "pnpm install"
assert_has "node pass - skipped core gates listed on the PASS line" "REPO-GATE: PASS (skipped: node TYPECHECK, node LINT)"

# ---- 2. node test failure -------------------------------------------------------
node_repo n_fail jest
mkdir -p "$WORK/n_fail/node_modules"
STUB_TEST_OUT="$JEST_FAIL" STUB_TEST_RC=1 run_gate n_fail --no-install
assert_eq "node fail - exit code 1" 1 "$RC"
assert_has "node fail - TESTS FAIL line" "node TESTS FAIL"
assert_has "node fail - counts" "3 passed"
assert_has "node fail - failing test name in excerpt" "- calc › adds numbers"
assert_has "node fail - first failure body in excerpt" "Expected: 4"
assert_has "node fail - final line counts gates" "REPO-GATE: FAIL (1 gates)"
assert_lacks "node fail - excerpt bounded, not the full log" "LATE-NOISE-LINE-55"

# ---- 3. missing node_modules -> frozen install; --no-install skips -------------
node_repo n_inst jest
STUB_TEST_OUT="$JEST_PASS" run_gate n_inst
assert_eq "install - exit 0" 0 "$RC"
assert_has "install - INSTALL gate ran" "node INSTALL PASS"
assert_file_has "install - frozen lockfile flag used" "$WORK/bin-n_inst/calls.log" "pnpm install --frozen-lockfile"

node_repo n_noinst jest
STUB_TEST_OUT="$JEST_PASS" run_gate n_noinst --no-install
assert_has "no-install - INSTALL skipped" "node INSTALL SKIPPED (0s) --no-install"
assert_file_lacks "no-install - pnpm install never invoked" "$WORK/bin-n_noinst/calls.log" "pnpm install"

node_repo n_instfail jest
STUB_INSTALL_RC=1 STUB_TEST_OUT="$JEST_PASS" run_gate n_instfail
assert_eq "install failure - exit 1" 1 "$RC"
assert_has "install failure - INSTALL FAIL" "node INSTALL FAIL"
assert_has "install failure - tests skipped not run" "node TESTS SKIPPED (0s) install failed"

# ---- 4. typecheck selection -----------------------------------------------------
node_repo n_notsc jest
mkdir -p "$WORK/n_notsc/node_modules"
STUB_TEST_OUT="$JEST_PASS" run_gate n_notsc --no-install
assert_has "typecheck - no tsconfig and no script is SKIPPED" "node TYPECHECK SKIPPED"

node_repo n_tcscript jest ',"typecheck":"tsc --noEmit"'
mkdir -p "$WORK/n_tcscript/node_modules"
STUB_TEST_OUT="$JEST_PASS" run_gate n_tcscript --no-install
assert_has "typecheck - script runs via package manager" "node TYPECHECK PASS"
assert_file_has "typecheck - pnpm run typecheck invoked" "$WORK/bin-n_tcscript/calls.log" "pnpm run typecheck"

node_repo n_tcfail jest ',"typecheck":"tsc --noEmit"'
mkdir -p "$WORK/n_tcfail/node_modules"
STUB_TC_RC=2 STUB_TEST_OUT="$JEST_PASS" run_gate n_tcfail --no-install
assert_eq "typecheck - failing script exits 1" 1 "$RC"
assert_has "typecheck - FAIL line" "node TYPECHECK FAIL"
assert_has "typecheck - excerpt shows output" "typecheck stub"

node_repo n_tsc jest
mkdir -p "$WORK/n_tsc/node_modules/.bin"
echo '{}' > "$WORK/n_tsc/tsconfig.json"
stub "$WORK/n_tsc/node_modules/.bin/tsc" <<'EOF'
#!/bin/bash
echo "tsc $*" >> "$STUB_LOG"
EOF
STUB_TEST_OUT="$JEST_PASS" run_gate n_tsc --no-install
assert_has "typecheck - tsc fallback with tsconfig" "node TYPECHECK PASS"
assert_file_has "typecheck - tsc --noEmit invoked" "$WORK/bin-n_tsc/calls.log" "tsc --noEmit"

# ---- 5. lint maps vet-diff exit code --------------------------------------------
node_repo n_lint jest
mkdir -p "$WORK/n_lint/node_modules"
stub "$WORK/vet-fail" <<'EOF'
#!/bin/bash
echo "vet-diff: eslint — FINDINGS"
echo "    src/a.ts:1:1: Error - no-eval"
exit 1
EOF
REPO_GATE_VET_DIFF="$WORK/vet-fail" STUB_TEST_OUT="$JEST_PASS" run_gate n_lint --no-install
assert_eq "lint - vet-diff exit 1 fails the gate" 1 "$RC"
assert_has "lint - LINT FAIL" "node LINT FAIL"
assert_has "lint - finding in excerpt" "no-eval"
stub "$WORK/vet-ok" <<'EOF'
#!/bin/bash
echo "vet-diff: 1 changed JS/TS file(s)"
echo "vet-diff: eslint — clean"
echo "vet-diff: all checks passed"
EOF
REPO_GATE_VET_DIFF="$WORK/vet-ok" STUB_TEST_OUT="$JEST_PASS" run_gate n_lint --no-install
assert_has "lint - vet-diff exit 0 passes" "node LINT PASS"

# ---- 6. mise wrapper ------------------------------------------------------------
node_repo n_mise jest
mkdir -p "$WORK/n_mise/node_modules"
echo 'node = "22"' > "$WORK/n_mise/mise.toml"
stub "$WORK/bin-n_mise/mise" <<'EOF'
#!/bin/bash
echo "mise $*" >> "$STUB_LOG"
shift 2
exec "$@"
EOF
STUB_TEST_OUT="$JEST_PASS" run_gate n_mise --no-install
assert_eq "mise - exit 0" 0 "$RC"
assert_file_has "mise - pnpm wrapped in mise exec --" "$WORK/bin-n_mise/calls.log" "mise exec -- pnpm run test"

node_repo n_nomise jest
mkdir -p "$WORK/n_nomise/node_modules"
stub "$WORK/bin-n_nomise/mise" <<'EOF'
#!/bin/bash
echo "mise $*" >> "$STUB_LOG"
EOF
STUB_TEST_OUT="$JEST_PASS" run_gate n_nomise --no-install
assert_file_lacks "mise - not used without a mise config" "$WORK/bin-n_nomise/calls.log" "mise "

# ---- 7. --changed ---------------------------------------------------------------
node_repo n_chg_jest jest
mkdir -p "$WORK/n_chg_jest/node_modules" "$WORK/n_chg_jest/src"
git -C "$WORK/n_chg_jest" add -A >/dev/null
git -C "$WORK/n_chg_jest" commit -qm base
echo 'export const a = 1;' > "$WORK/n_chg_jest/src/a.ts"
echo 'export const b = 2;' > "$WORK/n_chg_jest/README.md"
STUB_TEST_OUT="$JEST_PASS" run_gate n_chg_jest --no-install --changed
assert_eq "changed jest - exit 0" 0 "$RC"
assert_file_has "changed jest - findRelatedTests with the changed file" "$WORK/bin-n_chg_jest/calls.log" "pnpm exec jest --passWithNoTests --findRelatedTests src/a.ts"
assert_file_lacks "changed jest - non-source files excluded" "$WORK/bin-n_chg_jest/calls.log" "README.md"
assert_has "changed jest - detail says related" "jest related to 1 changed file(s)"

node_repo n_chg_vi "vitest run"
mkdir -p "$WORK/n_chg_vi/node_modules" "$WORK/n_chg_vi/src"
git -C "$WORK/n_chg_vi" add -A >/dev/null
git -C "$WORK/n_chg_vi" commit -qm base
echo 'export const w = 1;' > "$WORK/n_chg_vi/src/w.ts"
git -C "$WORK/n_chg_vi" add src/w.ts
STUB_TEST_OUT="$VITEST_FAIL" STUB_TEST_RC=1 run_gate n_chg_vi --no-install --changed
assert_file_has "changed vitest - related --run with staged file" "$WORK/bin-n_chg_vi/calls.log" "pnpm exec vitest related --run --passWithNoTests src/w.ts"
assert_eq "changed vitest - failure exit 1" 1 "$RC"
assert_has "changed vitest - counts parsed" "3 passed"
assert_has "changed vitest - failing name from FAIL line" "- src/widget.test.ts > widget > renders label"

node_repo n_chg_none jest
mkdir -p "$WORK/n_chg_none/node_modules"
git -C "$WORK/n_chg_none" add -A >/dev/null
git -C "$WORK/n_chg_none" commit -qm base
STUB_TEST_OUT="$JEST_PASS" run_gate n_chg_none --no-install --changed
assert_has "changed - nothing changed is SKIPPED not PASS" "node TESTS SKIPPED (0s) --changed: no changed source files"

# ---- 8. gradle -------------------------------------------------------------------
GRADLE_XML_DIR="build/test-results/test"
gradle_repo() { # name has_spotless gradlew-body
  local d; d=$(newrepo "$1")
  if [ "$2" = yes ]; then echo "plugins { id 'com.diffplug.spotless' }" > "$d/build.gradle"; else echo "plugins { id 'java' }" > "$d/build.gradle"; fi
  stub "$d/gradlew" <<<"$3"
}
gradle_repo g_fail yes '#!/bin/bash
echo "gradlew $*" >> "$STUB_LOG"
mkdir -p build/test-results/test
cat > build/test-results/test/TEST-com.example.FooTest.xml <<XML
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="com.example.FooTest" tests="3" skipped="1" failures="1" errors="0">
  <testcase name="shouldAdd" classname="com.example.FooTest"><failure message="expected 4 but was 5">java.lang.AssertionError: expected 4 but was 5
	at com.example.FooTest.shouldAdd(FooTest.java:12)</failure></testcase>
  <testcase name="shouldSub" classname="com.example.FooTest"/>
  <testcase name="shouldSkip" classname="com.example.FooTest"><skipped/></testcase>
</testsuite>
XML
exit 1'
run_gate g_fail
assert_eq "gradle fail - exit 1" 1 "$RC"
assert_has "gradle fail - counts from XML" "gradle BUILD FAIL"
assert_has "gradle fail - tests/failures/skipped attrs" "3 tests, 1 failures, 0 errors, 1 skipped"
assert_has "gradle fail - failing testcase name" "- com.example.FooTest.shouldAdd"
assert_has "gradle fail - failure message in excerpt" "expected 4 but was 5"
assert_file_has "gradle - spotlessApply included when build applies spotless" "$WORK/bin-g_fail/calls.log" "gradlew spotlessApply build"

gradle_repo g_plain no '#!/bin/bash
echo "gradlew $*" >> "$STUB_LOG"
mkdir -p build/test-results/test
echo "<testsuite name=\"x.YTest\" tests=\"5\" skipped=\"0\" failures=\"0\" errors=\"0\"/>" > build/test-results/test/TEST-x.YTest.xml
exit 0'
run_gate g_plain
assert_eq "gradle pass - exit 0" 0 "$RC"
assert_has "gradle pass - counts" "gradle BUILD PASS"
assert_has "gradle pass - test count" "5 tests, 0 failures"
assert_file_has "gradle - plain build without spotless" "$WORK/bin-g_plain/calls.log" "gradlew build"
assert_file_lacks "gradle - no spotlessApply without spotless" "$WORK/bin-g_plain/calls.log" "spotlessApply"

# exit 0 from gradle but failures recorded in XML (ignoreFailures=true) must still FAIL
gradle_repo g_ignore no '#!/bin/bash
mkdir -p build/test-results/test
echo "<testsuite name=\"x.ZTest\" tests=\"2\" skipped=\"0\" failures=\"0\" errors=\"1\"><testcase name=\"boom\" classname=\"x.ZTest\"><error message=\"npe\">java.lang.NullPointerException</error></testcase></testsuite>" > build/test-results/test/TEST-x.ZTest.xml
exit 0'
run_gate g_ignore
assert_eq "gradle ignoreFailures - XML errors fail the gate despite exit 0" 1 "$RC"
assert_has "gradle ignoreFailures - error testcase named" "- x.ZTest.boom"

# stale XML from an earlier run must not be reported as this run's results
gradle_repo g_stale no '#!/bin/bash
echo "compile error: cannot find symbol" >&2
exit 1'
mkdir -p "$WORK/g_stale/build/test-results/test"
echo '<testsuite name="old.OldTest" tests="9" skipped="0" failures="0" errors="0"/>' > "$WORK/g_stale/build/test-results/test/TEST-old.OldTest.xml"
touch -t 202001010000 "$WORK/g_stale/build/test-results/test/TEST-old.OldTest.xml"
run_gate g_stale
assert_eq "gradle stale - exit 1" 1 "$RC"
assert_has "gradle stale - old XML ignored" "no test results found"
assert_lacks "gradle stale - old counts absent" "9 tests"
assert_has "gradle stale - log tail shown" "cannot find symbol"

# ---- 9. terraform ---------------------------------------------------------------
write_tf_stub() { # bindir
  stub "$1/terraform" <<'EOF'
#!/bin/bash
echo "terraform $*" >> "$STUB_LOG"
case "$1" in
  init) mkdir -p .terraform; touch .terraform/fresh; exit "${STUB_INIT_RC:-0}" ;;
  fmt) [ "${STUB_FMT_RC:-0}" -ne 0 ] && echo "main.tf"; exit "${STUB_FMT_RC:-0}" ;;
  validate)
    if [ -n "${STUB_STALE:-}" ] && [ ! -f .terraform/fresh ]; then
      echo "Error: Missing required provider"
      echo "This configuration requires provider registry.terraform.io/hashicorp/null, but that provider isn't available. You may be able to install it automatically by running: terraform init"
      exit 1
    fi
    [ "${STUB_VALIDATE_RC:-0}" -ne 0 ] && echo "Error: Missing required argument"; exit "${STUB_VALIDATE_RC:-0}" ;;
esac
exit 0
EOF
}
d=$(newrepo tf_ok); write_tf_stub "$WORK/bin-tf_ok"
echo 'resource "null_resource" "x" {}' > "$d/main.tf"
run_gate tf_ok
assert_eq "terraform - exit 0" 0 "$RC"
assert_has "terraform - LINT PASS" "terraform LINT PASS"
assert_has "terraform - TYPECHECK PASS" "terraform TYPECHECK PASS"
assert_file_has "terraform - init -backend=false when .terraform missing" "$WORK/bin-tf_ok/calls.log" "terraform init -backend=false -input=false"
assert_file_has "terraform - fmt -check -recursive" "$WORK/bin-tf_ok/calls.log" "terraform fmt -check -recursive"
assert_file_lacks "terraform - never plans" "$WORK/bin-tf_ok/calls.log" "plan"
assert_file_lacks "terraform - never applies" "$WORK/bin-tf_ok/calls.log" "apply"

d=$(newrepo tf_init); write_tf_stub "$WORK/bin-tf_init"
echo 'resource "null_resource" "x" {}' > "$d/main.tf"; mkdir -p "$d/.terraform"
run_gate tf_init
assert_file_lacks "terraform - no init when .terraform exists" "$WORK/bin-tf_init/calls.log" "terraform init"

d=$(newrepo tf_noinit); write_tf_stub "$WORK/bin-tf_noinit"
echo 'resource "null_resource" "x" {}' > "$d/main.tf"
run_gate tf_noinit --no-install
assert_file_lacks "terraform - --no-install suppresses init" "$WORK/bin-tf_noinit/calls.log" "terraform init"
assert_has "terraform - --no-install validate SKIPPED" "terraform TYPECHECK SKIPPED"

d=$(newrepo tf_fmt); write_tf_stub "$WORK/bin-tf_fmt"
mkdir -p "$d/terraform"; echo 'resource "null_resource" "x" {}' > "$d/terraform/main.tf"
STUB_FMT_RC=3 run_gate tf_fmt
assert_eq "terraform fmt fail - exit 1" 1 "$RC"
assert_has "terraform fmt fail - LINT FAIL for terraform/ dir" "terraform LINT FAIL"
assert_has "terraform fmt fail - needs formatting detail" "terraform/: 1 file(s) need formatting"
assert_has "terraform fmt fail - file listed" "main.tf"

d=$(newrepo tf_val); write_tf_stub "$WORK/bin-tf_val"
echo 'resource "null_resource" "x" {}' > "$d/main.tf"
STUB_VALIDATE_RC=1 run_gate tf_val
assert_has "terraform validate fail - TYPECHECK FAIL" "terraform TYPECHECK FAIL"
assert_has "terraform validate fail - excerpt" "Missing required argument"

# stale .terraform (provider added since init): re-init once and re-validate
d=$(newrepo tf_stale); write_tf_stub "$WORK/bin-tf_stale"
echo 'resource "null_resource" "x" {}' > "$d/main.tf"; mkdir -p "$d/.terraform"
STUB_STALE=1 run_gate tf_stale
assert_eq "terraform stale - exit 0 after re-init" 0 "$RC"
assert_has "terraform stale - TYPECHECK PASS noting re-init" "terraform TYPECHECK PASS"
assert_has "terraform stale - detail notes re-initialised" "(re-initialised)"
assert_file_has "terraform stale - init -backend=false ran" "$WORK/bin-tf_stale/calls.log" "terraform init -backend=false -input=false"
assert_eq "terraform stale - validate ran exactly twice" 2 "$(grep -c '^terraform validate' "$WORK/bin-tf_stale/calls.log")"
assert_eq "terraform stale - init ran exactly once" 1 "$(grep -c '^terraform init' "$WORK/bin-tf_stale/calls.log")"

# stale + --no-install: environment problem, SKIPPED not FAIL, no init
d=$(newrepo tf_stale_ni); write_tf_stub "$WORK/bin-tf_stale_ni"
echo 'resource "null_resource" "x" {}' > "$d/main.tf"; mkdir -p "$d/.terraform"
STUB_STALE=1 run_gate tf_stale_ni --no-install
assert_eq "terraform stale --no-install - exit 0" 0 "$RC"
assert_has "terraform stale --no-install - SKIPPED with reason" "terraform TYPECHECK SKIPPED"
assert_has "terraform stale --no-install - detail" "needs terraform init (stale .terraform)"
assert_file_lacks "terraform stale --no-install - init never run" "$WORK/bin-tf_stale_ni/calls.log" "terraform init"

# genuine validate error in an initialised dir still FAILs and is not re-inited
d=$(newrepo tf_real); write_tf_stub "$WORK/bin-tf_real"
echo 'resource "null_resource" "x" {}' > "$d/main.tf"; mkdir -p "$d/.terraform"
STUB_VALIDATE_RC=1 run_gate tf_real
assert_eq "terraform genuine error - exit 1" 1 "$RC"
assert_has "terraform genuine error - TYPECHECK FAIL" "terraform TYPECHECK FAIL"
assert_file_lacks "terraform genuine error - no re-init" "$WORK/bin-tf_real/calls.log" "terraform init"

# init hint right after our own init is a real failure (no re-init loop)
d=$(newrepo tf_loop); write_tf_stub "$WORK/bin-tf_loop"
stub "$WORK/bin-tf_loop/terraform" <<'EOF'
#!/bin/bash
echo "terraform $*" >> "$STUB_LOG"
case "$1" in
  init) mkdir -p .terraform; exit 0 ;;
  validate) echo "Error: Missing required provider (run terraform init)"; exit 1 ;;
esac
exit 0
EOF
echo 'resource "null_resource" "x" {}' > "$d/main.tf"
run_gate tf_loop
assert_eq "terraform init-hint after fresh init - exit 1" 1 "$RC"
assert_eq "terraform init-hint after fresh init - init ran once" 1 "$(grep -c '^terraform init' "$WORK/bin-tf_loop/calls.log")"

# ---- 10. go / python ------------------------------------------------------------
d=$(newrepo go_r); echo 'module example.com/synthetic' > "$d/go.mod"
stub "$WORK/bin-go_r/go" <<'EOF'
#!/bin/bash
echo "go $*" >> "$STUB_LOG"
if [ "$1" = test ]; then
  printf 'ok  \texample.com/synthetic/a\t0.01s\n--- FAIL: TestWidget (0.00s)\n    widget_test.go:9: got 1 want 2\nFAIL\nFAIL\texample.com/synthetic/b\t0.02s\n'
  exit 1
fi
exit 0
EOF
run_gate go_r
assert_eq "go - exit 1 on failing package" 1 "$RC"
assert_has "go - build PASS" "go TYPECHECK PASS"
assert_has "go - package counts" "1 ok packages, 1 failed packages, 1 failing tests"
assert_has "go - failing test name" "- TestWidget (0.00s)"
assert_has "go - lint skipped without config" "go LINT SKIPPED"

d=$(newrepo py_r)
printf '[tool.ruff]\nline-length = 88\n' > "$d/pyproject.toml"
stub "$WORK/bin-py_r/uv" <<'EOF'
#!/bin/bash
echo "uv $*" >> "$STUB_LOG"
case " $* " in *" pytest "*)
  printf '.F..\n=== FAILURES ===\n___ test_adds ___\nassert 1 == 2\nFAILED tests/test_calc.py::test_adds - assert 1 == 2\n1 failed, 3 passed in 0.12s\n'
  exit 1 ;;
esac
exit 0
EOF
run_gate py_r
assert_eq "python - exit 1" 1 "$RC"
assert_has "python - mypy not configured is SKIPPED" "python TYPECHECK SKIPPED"
assert_has "python - ruff configured runs" "python LINT PASS"
assert_has "python - pytest counts" "3 passed, 1 failed"
assert_has "python - failing test name" "tests/test_calc.py::test_adds"

# ---- H1: unparseable package.json must FAIL, not SKIP ---------------------------
node_repo n_badpkg jest
printf '<<<<<<< HEAD\n{"name":"a","scripts":{"test":"jest"}}\n=======\n{"name":"b"}\n>>>>>>> base\n' > "$WORK/n_badpkg/package.json"
fresh_nm "$WORK/n_badpkg" .modules.yaml
STUB_TEST_OUT="$JEST_PASS" run_gate n_badpkg --no-install
assert_eq "unparseable package.json - exit 1" 1 "$RC"
assert_has "unparseable package.json - PACKAGE FAIL" "node PACKAGE FAIL"
assert_has "unparseable package.json - names the problem" "package.json unparseable"
assert_has "unparseable package.json - parse error in excerpt" "package.json: Expecting"
assert_lacks "unparseable package.json - not a green run" "REPO-GATE: PASS"

node_repo n_arrpkg jest
echo '[1,2]' > "$WORK/n_arrpkg/package.json"
STUB_TEST_OUT="$JEST_PASS" run_gate n_arrpkg --no-install
assert_eq "non-object package.json - exit 1" 1 "$RC"
assert_has "non-object package.json - PACKAGE FAIL" "node PACKAGE FAIL"

node_repo n_noscript jest
echo '{"name":"synthetic-app"}' > "$WORK/n_noscript/package.json"
fresh_nm "$WORK/n_noscript" .modules.yaml
STUB_TEST_OUT="$JEST_PASS" run_gate n_noscript --no-install
assert_eq "valid package.json without test script - exit 0" 0 "$RC"
assert_has "valid package.json without test script - TESTS SKIPPED" "node TESTS SKIPPED (0s) no test script"

# ---- M1: stale node_modules (lockfile newer than the install marker) ------------
node_repo n_stale jest
fresh_nm "$WORK/n_stale" .modules.yaml
touch -t 203001010000 "$WORK/n_stale/pnpm-lock.yaml"
STUB_TEST_OUT="$JEST_PASS" run_gate n_stale
assert_eq "stale lockfile - exit 0 after reinstall" 0 "$RC"
assert_has "stale lockfile - INSTALL ran" "node INSTALL PASS"
assert_has "stale lockfile - reason in detail" "(lockfile newer than node_modules)"
assert_file_has "stale lockfile - frozen install invoked" "$WORK/bin-n_stale/calls.log" "pnpm install --frozen-lockfile"

STUB_TEST_OUT="$JEST_PASS" run_gate n_stale --no-install
assert_eq "stale lockfile --no-install - exit 0" 0 "$RC"
assert_has "stale lockfile --no-install - visible SKIPPED warning" "node INSTALL SKIPPED (0s) lockfile newer than node_modules (--no-install)"
assert_has "stale lockfile --no-install - listed on the PASS line" "node INSTALL"

node_repo n_stale_fail jest
fresh_nm "$WORK/n_stale_fail" .modules.yaml
touch -t 203001010000 "$WORK/n_stale_fail/pnpm-lock.yaml"
STUB_INSTALL_RC=1 STUB_TEST_OUT="$JEST_PASS" run_gate n_stale_fail
assert_eq "stale lockfile - failing frozen install fails the run" 1 "$RC"
assert_has "stale lockfile - INSTALL FAIL" "node INSTALL FAIL"

node_repo n_nomarker jest
mkdir -p "$WORK/n_nomarker/node_modules"
STUB_TEST_OUT="$JEST_PASS" run_gate n_nomarker
assert_file_has "missing install marker counts as stale" "$WORK/bin-n_nomarker/calls.log" "pnpm install --frozen-lockfile"

# npm and yarn markers: a fresh marker must prevent a reinstall
d=$(newrepo n_npm); mkdir -p "$WORK/bin-n_npm"
echo '{"name":"x","scripts":{"test":"jest"}}' > "$d/package.json"; : > "$d/package-lock.json"
fresh_nm "$d" .package-lock.json
stub "$WORK/bin-n_npm/npm" <<'EOF'
#!/bin/bash
echo "npm $*" >> "$STUB_LOG"
cat "$STUB_TEST_OUT"
EOF
STUB_TEST_OUT="$JEST_PASS" run_gate n_npm
assert_eq "npm fresh marker - exit 0" 0 "$RC"
assert_file_lacks "npm fresh .package-lock.json marker - no npm ci" "$WORK/bin-n_npm/calls.log" "npm ci"
touch -t 203001010000 "$d/package-lock.json"
STUB_TEST_OUT="$JEST_PASS" run_gate n_npm
assert_file_has "npm stale lockfile - npm ci" "$WORK/bin-n_npm/calls.log" "npm ci"

d=$(newrepo n_yarn); mkdir -p "$WORK/bin-n_yarn"
echo '{"name":"x","scripts":{"test":"jest"}}' > "$d/package.json"; : > "$d/yarn.lock"
fresh_nm "$d" .yarn-state.yml
stub "$WORK/bin-n_yarn/yarn" <<'EOF'
#!/bin/bash
echo "yarn $*" >> "$STUB_LOG"
cat "$STUB_TEST_OUT"
EOF
STUB_TEST_OUT="$JEST_PASS" run_gate n_yarn
assert_eq "yarn fresh marker - exit 0" 0 "$RC"
assert_file_lacks "yarn fresh .yarn-state.yml marker - no install" "$WORK/bin-n_yarn/calls.log" "yarn install"
touch -t 203001010000 "$d/yarn.lock"
STUB_TEST_OUT="$JEST_PASS" run_gate n_yarn
assert_file_has "yarn stale lockfile - immutable install" "$WORK/bin-n_yarn/calls.log" "yarn install --immutable"

# ---- M2: tsconfig without tsc FAILs; skipped gates are listed -------------------
node_repo n_tsconly jest
fresh_nm "$WORK/n_tsconly" .modules.yaml
echo '{}' > "$WORK/n_tsconly/tsconfig.json"
STUB_TEST_OUT="$JEST_PASS" run_gate n_tsconly --no-install
assert_eq "tsconfig without tsc - exit 1" 1 "$RC"
assert_has "tsconfig without tsc - TYPECHECK FAIL" "node TYPECHECK FAIL (0s) tsconfig.json present but no tsc"

STUB_TEST_OUT="$JEST_PASS" run_gate n_pass --no-install --json
J=$(printf '%s' "$OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d["status"], d["skipped"])
' 2>&1)
assert_eq "json - skipped array lists skipped core gates" "PASS ['node TYPECHECK', 'node LINT']" "$J"

# ---- L4: uv never rewrites uv.lock ----------------------------------------------
assert_file_has "uv - pytest runs with --frozen" "$WORK/bin-py_r/calls.log" "uv run --frozen pytest -q"
assert_file_has "uv - ruff runs with --frozen" "$WORK/bin-py_r/calls.log" "uv run --frozen ruff check ."
assert_file_lacks "uv - no unfrozen uv run" "$WORK/bin-py_r/calls.log" "uv run pytest"
d=$(newrepo py_m); mkdir -p "$WORK/bin-py_m"
printf '[tool.mypy]\nstrict = true\n' > "$d/pyproject.toml"
stub "$WORK/bin-py_m/uv" <<'EOF'
#!/bin/bash
echo "uv $*" >> "$STUB_LOG"
exit 0
EOF
run_gate py_m
assert_has "uv - mypy configured runs" "python TYPECHECK PASS"
assert_file_has "uv - mypy runs with --frozen" "$WORK/bin-py_m/calls.log" "uv run --frozen mypy ."
assert_file_lacks "uv - no unfrozen mypy" "$WORK/bin-py_m/calls.log" "uv run mypy"

# ---- gradle: unparseable result XML must FAIL (same class as H1) ----------------
gradle_repo g_badxml no '#!/bin/bash
mkdir -p build/test-results/test
echo "<testsuite name=\"x.Q\" tests=\"1\"" > build/test-results/test/TEST-x.Q.xml
exit 0'
run_gate g_badxml
assert_eq "gradle unparseable XML - exit 1" 1 "$RC"
assert_has "gradle unparseable XML - detail" "1 unparseable result file(s)"

# ---- 11. multi-type repo --------------------------------------------------------
node_repo multi jest
mkdir -p "$WORK/multi/node_modules" "$WORK/multi/terraform"
echo 'resource "null_resource" "x" {}' > "$WORK/multi/terraform/main.tf"
write_tf_stub "$WORK/bin-multi"
STUB_TEST_OUT="$JEST_PASS" run_gate multi --no-install
assert_has "multi - node gates present" "node TESTS PASS"
assert_has "multi - terraform gates present" "terraform LINT PASS"

# ---- 12. --json -----------------------------------------------------------------
node_repo j_fail jest
mkdir -p "$WORK/j_fail/node_modules"
STUB_TEST_OUT="$JEST_FAIL" STUB_TEST_RC=1 run_gate j_fail --no-install --json
assert_eq "json - exit 1 on failure" 1 "$RC"
if printf '%s' "$OUT" | python3 -m json.tool >/dev/null 2>&1; then ok "json - parses with json.tool"; else bad "json - parses with json.tool" "invalid JSON"; fi
J=$(printf '%s' "$OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
t = [g for g in d["gates"] if g["gate"] == "TESTS"][0]
print(d["status"], t["type"], t["status"], isinstance(t["seconds"], int), "adds numbers" in t["excerpt"], bool(d["logDir"]), bool(d["repo"]))
' 2>&1)
assert_eq "json - fields populated" "FAIL node FAIL True True True True" "$J"

# ---- 13. usage / non-project ----------------------------------------------------
newrepo empty >/dev/null; echo hi > "$WORK/empty/README.md"
run_gate empty
assert_eq "non-project - exit 2" 2 "$RC"
assert_has "non-project - message" "no recognizable project"

mkdir -p "$WORK/notgit"
OUT=$("$GATE" -C "$WORK/notgit" 2>&1); RC=$?
assert_eq "not a git repo - exit 2" 2 "$RC"

OUT=$("$GATE" --bogus 2>&1); RC=$?
assert_eq "unknown flag - exit 2" 2 "$RC"

OUT=$("$GATE" --help 2>&1); RC=$?
assert_eq "help - exit 0" 0 "$RC"
assert_has "help - prints header usage" "repo-gate [--changed] [--no-install] [--json] [-C dir]"
assert_lacks "help - stops at end of header" "set -uo pipefail"

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
