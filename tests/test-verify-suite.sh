#!/usr/bin/env bash
# M11: `make suite` = verify.sh with SCOPE=full: the whole suite (not only @gate), quarantine still excluded, only
# local projects, bulk runs without trace/video by default, same credentials path and test-order check as the gate.
. "$(dirname "$0")/lib.sh"
set +e
V="$T_ROOT/scripts/verify.sh"
expect_true  "SCOPE allows only gate|full"                    grep -q 'gate|full) ;; \*) die "SCOPE must be gate or full' "$V"
expect_true  "full scope still excludes @quarantine"          grep -q 'run_suite gate "${GREP:-.}" "@quarantine"' "$V"
expect_true  "PROJECTS limited to *-local and unit"           grep -q '\*-local|unit) args+=(--project "$p");; \*) die "PROJECTS' "$V"
expect_true  "full scope defaults trace/video off"            grep -q 'TRACE_MODE="${TFR_TRACE:-off}"' "$V"
expect_true  "retries stay 0"                                 grep -q 'TFR_RETRIES=0' "$V"
expect_true  "test-order check still runs after the suite"    grep -q 'check-test-orders.sh' "$V"
expect_true  "make suite sets SCOPE=full"                     grep -q 'SCOPE=full scripts/verify.sh' "$T_ROOT/Makefile"
expect_false "bad SCOPE refused"                              env SCOPE=nope bash -c ". '$T_ROOT/scripts/lib.sh'; SCOPE=nope; case \"\$SCOPE\" in gate|full) exit 0;; *) exit 1;; esac"
done_tests
