#!/usr/bin/env bash
# TFHFUNNEL-8090: local tf-api runs with APP_ENV=development (TF_API_APP_ENV) so its environment-scoped flag lookups
# can match rows (the DB trigger rejects 'local'); seed/flag-env/map.sql copies the production snapshot rows to
# 'development'. Preflight refuses any other tf-api env than development|local. Sandbox copy, dummy values only.
. "$(dirname "$0")/lib.sh"; set +e
SB="$(sandbox_copy)"; dummy_env "$SB"
setv() { sed -i.bak -E "s|^$1=.*|$1=$2|" "$SB/.env"; rm -f "$SB/.env.bak"; }
pf() { out="$("$SB/scripts/preflight.sh" 2>&1)"; rc=$?; }
# dummy values for every ${VAR:?...} the compose file requires (no containers are created; config only)
REQ="$(grep -oE '\$\{[A-Z0-9_]+:\?' "$T_ROOT/docker-compose.yml" | sed -E 's/^\$\{//; s/:\?$//' | sort -u)"
tfenv() { (cd "$SB" && env $(for k in $REQ; do printf '%s=dummy-%s ' "$k" "$k"; done) docker compose config 2>/dev/null) | awk '/^  tf-api:/{f=1} f&&/^  [a-z]/&&!/^  tf-api:/{f=0} f&&/APP_ENV:/{print $2; exit}'; }

echo "compose: tf-api APP_ENV defaults to development"
if command -v docker >/dev/null 2>&1; then
  expect_true "tf-api APP_ENV resolves to development (got '$(tfenv)')" [ "$(tfenv)" = development ]
  setv TF_API_APP_ENV local
  expect_true "TF_API_APP_ENV=local is honored (got '$(tfenv)')" [ "$(tfenv)" = local ]
fi
echo "preflight: only development|local"
for v in development local ""; do
  dummy_env "$SB"; setv TF_API_APP_ENV "$v"; pf
  expect_true "TF_API_APP_ENV='$v' passes (rc=$rc)" [ $rc -eq 0 ]; [ $rc -eq 0 ] || printf '%s\n' "$out" | tail -3 >&2
done
for v in production prod stage staging Production; do
  dummy_env "$SB"; setv TF_API_APP_ENV "$v"; pf
  expect_true "TF_API_APP_ENV='$v' refused" [ $rc -ne 0 ]
  expect_true "  ...with a TF_API_APP_ENV message" grep -q TF_API_APP_ENV <<<"$out"
done
echo "map.sql: derived from production only, trigger-safe target, self-check"
M="$T_ROOT/seed/flag-env/map.sql"
expect_true "only 'development' rows are deleted" [ "$(grep -c '^DELETE' "$M")" = 1 ]
expect_true "the delete targets development" grep -q "^DELETE FROM public.feature_flags WHERE environment = 'development';" "$M"
expect_false "never writes environment 'local' (trigger)" bash -c "grep -v '^--' '$M' | grep -qE \"'local'\""
expect_false "never UPDATEs flags" grep -qiE '^[[:space:]]*UPDATE' "$M"
expect_true "copies FROM the production rows" grep -q "FROM public.feature_flags WHERE environment = 'production' ORDER BY id" "$M"
expect_true "refuses a non-local server" grep -q "refusing a non-local database server" "$M"
expect_true "runs in one transaction" bash -c "grep -q '^BEGIN;' '$M' && grep -q '^COMMIT;' '$M'"
rm -rf "$SB"
done_tests
