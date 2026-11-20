#!/usr/bin/env bash
# Fix (a): deny/allow lists must be ^...$ anchored with escaped dots; sticky.io, limelightcrm.com and trulyfree.com are
# denied (the reviewed dev/stage hosts pass only via exact safety/reviewed-exceptions.txt entries: test-externals-real.sh).
. "$(dirname "$0")/lib.sh"
. "$T_ROOT/scripts/lib.sh"; set +e

echo "pattern_anchored"
for p in '^cdn\.builder\.io$' '^(.*\.)?sticky\.io$' '^(.*[.-])?prod(uction)?([.-].*)?$' '^.*tfhcore.*$' '^(www\.)?example\.com$'; do
  expect_true  "accepts $p" pattern_anchored "$p"
done
for p in 'klaviyo\.com$' '^klaviyo\.com' 'syteline' '^cdn.builder\.io$' '^cdn\.builder.io$' '(^|\.)infor\.com$'; do
  expect_false "refuses $p" pattern_anchored "$p"
done

echo "committed pattern files are all anchored"
for f in safety/prod-denylist.txt safety/nonprod-hosts.txt safety/reviewed-exceptions.txt proxy/allowlist.txt proxy/readonly-allowlist.txt; do
  [ -f "$T_ROOT/$f" ] || continue
  while IFS= read -r p; do expect_true "$f: $p" pattern_anchored "$p"; done < <(patterns "$T_ROOT/$f")
done

echo "deny list covers Sticky and never-allowed services"
denied() { printf '%s\n' "$1" | grep -Eiq -f <(patterns "$T_ROOT/safety/prod-denylist.txt"); }
for h in api.sticky.io sticky.io mygreenfills.limelightcrm.com limelightcrm.com a.klaviyo.com api.mailgun.net \
         rest.avatax.avalara.com s3.amazonaws.com www.trulyfreehome.com mygreenfills.com tfhcore.example prod-api.example.com \
         api.trulyfree.com trulyfree.com api.dev.trulyfree.com; do
  expect_true "denies $h" denied "$h"
done
for h in cdn.builder.io notsticky.io sticky.io.example localhost; do
  expect_false "does not deny $h" denied "$h"
done

echo "preflight refuses an unanchored deny entry (sandbox copy, dummy .env)"
SB="$(sandbox_copy)"; dummy_env "$SB"
out="$("$SB/scripts/preflight.sh" 2>&1)"; rc=$?
expect_true "baseline preflight passes (rc=$rc)" [ $rc -eq 0 ]
[ $rc -eq 0 ] || printf '%s\n' "$out" | tail -5 >&2
echo 'klaviyo\.com$' >> "$SB/safety/prod-denylist.txt"
out="$("$SB/scripts/preflight.sh" 2>&1)"; rc=$?
expect_true "unanchored deny entry -> preflight exit 1" [ $rc -eq 1 ]
expect_true "message names the entry" grep -q "prod-denylist.txt entry 'klaviyo" <<<"$out"
echo "gitignored safety/prod-denylist.local.txt is enforced too"
sed -i.bak '$d' "$SB/safety/prod-denylist.txt"; rm -f "$SB/safety/prod-denylist.txt.bak"
echo 'internal-host.example$' > "$SB/safety/prod-denylist.local.txt"
out="$("$SB/scripts/preflight.sh" 2>&1)"; rc=$?
expect_true "unanchored local deny entry -> preflight exit 1" [ $rc -eq 1 ]
expect_true "message names the local file" grep -q "prod-denylist.local.txt entry" <<<"$out"
expect_true "local deny file is gitignored" git -C "$T_ROOT" check-ignore -q safety/prod-denylist.local.txt
rm -rf "$SB"

echo "no named TFH hosts in tracked files (suffix patterns only)"
named="$(git -C "$T_ROOT" grep -nE '[a-z0-9-]+\\?\.(trulyfreehome|mygreenfills)\\?\.com' -- ':!tests/' ':!scripts/egress-check.sh' || true)"
expect_true "no named hosts outside probes/tests" [ -z "$named" ]
[ -z "$named" ] || printf '%s\n' "$named" >&2
done_tests
