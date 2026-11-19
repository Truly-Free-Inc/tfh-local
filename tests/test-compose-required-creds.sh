#!/usr/bin/env bash
# Fix (e): compose has no default credentials (${VAR:?}); make bootstrap generates missing ones, never prints them,
# never changes existing values. Only `docker compose config` is run (no containers); bootstrap clones nothing
# because every apps/<name> is pre-created in the sandbox.
. "$(dirname "$0")/lib.sh"
. "$T_ROOT/scripts/lib.sh"; set +e
CREDS="POSTGRES_USER POSTGRES_PASSWORD APP_DB_USER APP_DB_PASS MINIO_ROOT_USER MINIO_ROOT_PASSWORD GATEWAY_DB_USER GATEWAY_DB_PASSWORD KRATOS_SECRETS_COOKIE KRATOS_SECRETS_CIPHER"
for v in $CREDS; do
  expect_false "compose has no default for $v" grep -qE "\\\$\\{$v:-" "$T_ROOT/docker-compose.yml"
  expect_true  "compose requires $v" grep -qE "\\\$\\{$v:\\?" "$T_ROOT/docker-compose.yml"
done
SB="$(sandbox_copy)"; cp "$SB/.env.example" "$SB/.env"
cfg() { docker compose --project-directory "$SB" -f "$SB/docker-compose.yml" config -q 2>&1; }
if command -v docker >/dev/null; then
  out="$(cfg)"; rc=$?
  expect_true "compose config refuses empty credentials (rc=$rc)" [ $rc -ne 0 ]
  expect_true "error says 'set in .env'" grep -q 'set in .env' <<<"$out"
fi
while read -r name _; do mkdir -p "$SB/apps/$name"; done < <(ROOT="$SB" repos)
out="$(bash "$SB/scripts/bootstrap.sh" 2>&1 </dev/null)"; rc=$?
expect_true "bootstrap exits 0 (rc=$rc)" [ $rc -eq 0 ]
for v in $CREDS TEST_CUSTOMER_PORTAL_PASSWORD LOCAL_ADMIN_PASSWORD TF_API_BASIC_AUTH_PASSWORD; do
  val="$(grep -E "^$v=" "$SB/.env" | cut -d= -f2-)"
  expect_true "bootstrap filled $v" [ -n "$val" ]
  case "$v" in *USER) ;; *) expect_false "$v value not printed" grep -qF -- "$val" <<<"$out" ;; esac
done
c="$(grep -E '^KRATOS_SECRETS_CIPHER=' "$SB/.env" | cut -d= -f2-)"
expect_true "KRATOS_SECRETS_CIPHER is 32 chars" [ ${#c} -eq 32 ]
expect_true ".env is mode 600" [ "$(stat -f %Lp "$SB/.env" 2>/dev/null || stat -c %a "$SB/.env")" = 600 ]
before="$(shasum "$SB/.env")"; bash "$SB/scripts/bootstrap.sh" >/dev/null 2>&1 </dev/null
expect_true "re-running bootstrap changes nothing" [ "$before" = "$(shasum "$SB/.env")" ]
if command -v docker >/dev/null; then
  out="$(cfg)"; rc=$?
  expect_true "compose config OK after bootstrap (rc=$rc)" [ $rc -eq 0 ]
fi
rm -rf "$SB"
done_tests
