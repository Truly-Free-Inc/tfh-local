#!/usr/bin/env bash
# Fix (c): verify's ticket --grep matches the WHOLE key. Evaluated with node exactly as Playwright does
# (new RegExp(grep, 'gi') against "<title> <tags>").
. "$(dirname "$0")/lib.sh"
. "$T_ROOT/scripts/lib.sh"; set +e
command -v node >/dev/null || { echo "node missing; skip"; exit 0; }
pw_match() { node -e 'const r=new RegExp(process.argv[1],"gi"); process.exit(r.test(process.argv[2])?0:1)' "$1" "$2"; }
G="$(key_grep TFHFUNNEL-12)"
expect_true  "grep is $G" [ "$G" = '@TFHFUNNEL-12(?![0-9])' ]
expect_true  "matches '@TFHFUNNEL-12'"               pw_match "$G" 'checkout works @TFHFUNNEL-12'
expect_true  "matches '@TFHFUNNEL-12 @gate'"         pw_match "$G" 'checkout works @TFHFUNNEL-12 @gate'
expect_true  "matches tag list '@gate @TFHFUNNEL-12'" pw_match "$G" 'title @gate @TFHFUNNEL-12'
expect_true  "matches '@TFHFUNNEL-12-retry' (hyphen suffix is not a different key)" pw_match "$G" 'x @TFHFUNNEL-12-retry'
expect_false "no match '@TFHFUNNEL-123'"            pw_match "$G" 'checkout works @TFHFUNNEL-123'
expect_false "no match '@TFHFUNNEL-1234 @gate'"     pw_match "$G" 'x @TFHFUNNEL-1234 @gate'
expect_false "no match '@XTFHFUNNEL-1'"             pw_match "$(key_grep TFHFUNNEL-1)" 'x @TFHFUNNEL-10'
expect_false "no match untagged title"              pw_match "$G" 'TFHFUNNEL-12 in title only'
expect_false "key_grep refuses non-key"             key_grep 'TFHFUNNEL-12|.*'
expect_true  "verify.sh uses key_grep"              grep -q 'run_suite ticket "$(key_grep "$KEY")"' "$T_ROOT/scripts/verify.sh"
done_tests
