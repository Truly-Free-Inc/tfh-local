#!/usr/bin/env bash
# EXTERNALS=real (Michael 2026-11-20): preflight lets through EXACTLY the reviewed dev/stage Sticky host
# (limelightcrm.com + the single derived API host <STICKY_APP_KEY>.limelightcrm.com) and the TF dev host
# (api.dev.trulyfree.com); every other sticky.io / limelightcrm.com / trulyfree.com host (incl. the prod TF API) stays
# refused. The generated proxy filter is empty offline and on any refusal (fail closed). Sandbox copy, dummy values only.
. "$(dirname "$0")/lib.sh"; set +e

SB="$(sandbox_copy)"; dummy_env "$SB"
FILTER="$SB/.state/egress/allowlist.txt"
setv() { sed -i.bak -E "s|^$1=.*|$1=$2|" "$SB/.env"; rm -f "$SB/.env.bak"; }
real_env() {
  dummy_env "$SB"
  setv EXTERNALS real
  setv STICKY_DOMAIN limelightcrm.com; setv STICKY_API_EXT /api/v1/; setv STICKY_API_EXT_2 /api/v2/
  setv STICKY_APP_KEY dummyappkey; setv STICKY_USERNAME dummy-user; setv STICKY_PASSWORD dummy-pass
  setv TF_COMPOSITION_API_BASE_URL https://api.dev.trulyfree.com; setv TF_COMPOSITION_API_TOKEN dummy-token
}
pf() { out="$("$SB/scripts/preflight.sh" 2>&1)"; rc=$?; }
entries() { grep -vE '^[[:space:]]*(#|$)' "$FILTER" 2>/dev/null; }

echo "offline (default): passes with the reviewed lists committed; generated filter is EMPTY"
pf; expect_true "offline preflight passes (rc=$rc)" [ $rc -eq 0 ]; [ $rc -eq 0 ] || printf '%s\n' "$out" | tail -5 >&2
expect_true "offline filter has zero entries" [ -z "$(entries)" ]

echo "real: reviewed hosts pass; filter = allowlist + derived Sticky API host"
real_env; pf
expect_true "real preflight passes (rc=$rc)" [ $rc -eq 0 ]; [ $rc -eq 0 ] || printf '%s\n' "$out" | tail -5 >&2
expect_true "filter allows limelightcrm.com"          grep -qxF '^limelightcrm\.com$' <(entries)
expect_true "filter allows api.dev.trulyfree.com"     grep -qxF '^api\.dev\.trulyfree\.com$' <(entries)
expect_true "filter allows the derived Sticky API host" grep -qxF '^dummyappkey\.limelightcrm\.com$' <(entries)
expect_true "filter has exactly 3 entries" [ "$(entries | wc -l | tr -d ' ')" = 3 ]
expect_false "preflight never prints the app key" grep -q dummyappkey <<<"$out"
allowed() { printf '%s\n' "$1" | grep -Eiq -f <(entries); }
for h in www.limelightcrm.com api.limelightcrm.com other.limelightcrm.com sticky.io api.sticky.io api.trulyfree.com \
         trulyfree.com www.trulyfree.com x.api.dev.trulyfree.com a.klaviyo.com api.mailgun.net s3.amazonaws.com \
         rest.avatax.com www.trulyfreehome.com tfhcore.example; do
  expect_false "filter does not allow $h" allowed "$h"
done

echo "real: refusals (filter written EMPTY on any refusal)"
refuses() { # refuses <desc> <grep-message> : run preflight, expect exit 1 + message + empty filter
  pf; expect_true "$1 -> exit 1 (rc=$rc)" [ $rc -eq 1 ]
  expect_true "$1 -> message" grep -q -- "$2" <<<"$out"
  expect_true "$1 -> filter empty" [ -z "$(entries)" ]
  expect_false "$1 -> app key not printed" grep -q dummyappkey <<<"$out"
}
real_env; setv TF_COMPOSITION_API_BASE_URL https://api.trulyfree.com;   refuses "prod TF host" "TF_COMPOSITION_API_BASE_URL host 'api.trulyfree.com' matches"
real_env; setv STICKY_DOMAIN sticky.io;                                 refuses "STICKY_DOMAIN sticky.io" "STICKY_DOMAIN host 'sticky.io'"
real_env; setv STICKY_DOMAIN www.limelightcrm.com;                      refuses "STICKY_DOMAIN www.limelightcrm.com" "STICKY_DOMAIN host 'www.limelightcrm.com'"
real_env; setv STICKY_APP_KEY trulyfree-prod;                           refuses "app key with a prod label" "Sticky API host <STICKY_APP_KEY>"
real_env; setv STICKY_APP_KEY 'dummyappkey.evil';                       refuses "app key that is not one label" "not a single DNS label"
real_env; setv STICKY_APP_KEY '';                                       refuses "app key missing" "STICKY_APP_KEY is not set"
real_env; setv TF_COMPOSITION_API_TOKEN '';                             refuses "TF token missing" "TF_COMPOSITION_API_TOKEN is not set"
real_env; setv TF_COMPOSITION_API_BASE_URL http://api.dev.trulyfree.com; refuses "TF over http" "must be https"

echo "reviewed-exceptions.txt: literal hosts on the non-prod list only"
cp "$SB/safety/reviewed-exceptions.txt" "$SB/exc.bak"
real_env; echo '^(.*\.)?limelightcrm\.com$' >> "$SB/safety/reviewed-exceptions.txt"; refuses "wildcard exception" "is not ONE literal host"
cp "$SB/exc.bak" "$SB/safety/reviewed-exceptions.txt"
real_env; echo '^api\.trulyfree\.com$' >> "$SB/safety/reviewed-exceptions.txt"; refuses "exception not on the non-prod list" "is not on safety/nonprod-hosts.txt"
cp "$SB/exc.bak" "$SB/safety/reviewed-exceptions.txt"
real_env; echo '^www\.limelightcrm\.com$' >> "$SB/proxy/allowlist.txt"; refuses "allow-list entry not reviewed" "proxy/allowlist.txt entry '^www"
rm -rf "$SB"

echo "committed reviewed lists"
expect_true "exceptions file is committed (not ignored)" bash -c "! git -C '$T_ROOT' check-ignore -q safety/reviewed-exceptions.txt"
expect_true "generated filter lives under gitignored .state/" git -C "$T_ROOT" check-ignore -q .state/egress/allowlist.txt
done_tests
