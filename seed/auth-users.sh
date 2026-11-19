#!/usr/bin/env bash
# Seed LOCAL auth users (idempotent; re-run any time). Local containers only.
#   1. Portal test customer ("test test") in the local tf-api DB: customers + customer_auth (bcrypt cost 12).
#      external_customer_id is a local placeholder so login never needs Sticky to look the customer up.
#   2. Same customer + a local admin as Kratos identities (local Kratos admin API on the 127.0.0.1 ingress port,
#      same payload as tf-apigateway's auth:create-user job); admin gets role `admin` in Keto (after
#      tf-apigateway auth:seed-permissions).
# Emails/passwords come from .env (gitignored): TEST_CUSTOMER_PORTAL_EMAIL/_PASSWORD, LOCAL_ADMIN_EMAIL/_PASSWORD.
# Never prints passwords and never puts them on a command line (argv is visible in `ps`): passwords only travel
# through stdin pipes fed by shell builtins. Never touches feature flags. Runs preflight first.
. "$(dirname "$0")/../scripts/lib.sh"
cd "$ROOT"
"$ROOT/scripts/preflight.sh"
load_env

: "${TEST_CUSTOMER_PORTAL_EMAIL:?set in .env}" "${TEST_CUSTOMER_PORTAL_PASSWORD:?set in .env}"
: "${LOCAL_ADMIN_EMAIL:?set in .env}" "${LOCAL_ADMIN_PASSWORD:?set in .env}"
case "$TEST_CUSTOMER_PORTAL_EMAIL$LOCAL_ADMIN_EMAIL" in
  *@trulyfreehome.com*|*@gmail.com*) die "REFUSED: seed emails must be local-only (e.g. *@tfh-local.test)";;
esac
command -v python3 >/dev/null || die "python3 is required (builds the Kratos JSON from stdin)"

DB_USER="${APP_DB_USER:-tf_api_local}"; DB_NAME="${APP_DB_NAME:-tf_api_local}"
EMAIL_LC="$(printf '%s' "$TEST_CUSTOMER_PORTAL_EMAIL" | tr '[:upper:]' '[:lower:]')"
# Local Kratos admin API, loopback only (ingress publishes kratos:4434 on 127.0.0.1).
KRATOS_ADMIN="http://127.0.0.1:${KRATOS_ADMIN_HOST_PORT:-14434}"

# bcrypt cost 12 ($2y$ -> $2a$: same algorithm; Go's x/crypto/bcrypt emits $2a$). Password via stdin, not argv.
HASH="$(printf '%s' "$TEST_CUSTOMER_PORTAL_PASSWORD" | htpasswd -niBC 12 x | cut -d: -f2 | sed 's/^\$2y\$/$2a$/')"
case "$HASH" in \$2a\$12\$*) ;; *) die "bcrypt hash generation failed";; esac

echo "seed: portal test customer in tf-api DB"
# email + hash are fed on stdin (\set), not as psql -v arguments.
{ printf "\\set email '%s'\n\\set hash '%s'\n" "$EMAIL_LC" "$HASH"; cat <<'SQL'
INSERT INTO customers (first_name, last_name, email, phone, external_customer_id)
SELECT 'test', 'test', :'email', '5555550100', 'tfh-local-offline-1'
WHERE NOT EXISTS (SELECT 1 FROM customers WHERE lower(email) = :'email');
INSERT INTO customer_auth (customer_id, password_hash, is_first_login)
SELECT id, :'hash', false FROM customers WHERE lower(email) = :'email'
ON CONFLICT (customer_id) DO UPDATE
  SET password_hash = EXCLUDED.password_hash, is_first_login = false,
      failed_login_attempts = 0, locked_until = NULL, updated_at = now();
SQL
} | dc exec -T postgres psql -v ON_ERROR_STOP=1 -q -U "$DB_USER" -d "$DB_NAME"
{ printf "\\set email '%s'\n" "$EMAIL_LC"; cat <<'SQL'
SELECT 'customer id=' || c.id || ' name=' || c.first_name || ' ' || c.last_name || ' auth_row=' || (a.id IS NOT NULL)
FROM customers c LEFT JOIN customer_auth a ON a.customer_id = c.id WHERE lower(c.email) = :'email';
SQL
} | dc exec -T postgres psql -At -U "$DB_USER" -d "$DB_NAME"

gw() { dc exec -T tf-apigateway ./main "$@" 2>&1; }
uuid_of() { grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -n1; }

# kratos_identity <email> <first> <last> <PASSWORD_VAR_NAME>: create (or find) the identity; prints its UUID.
# The password is read from the named variable by a builtin and piped to python3 on stdin.
kratos_identity() {
  local email="$1" first="$2" last="$3" pwvar="$4" body code id
  body="$(mktemp)"; trap 'rm -f "$body"' RETURN
  code="$(printf '%s' "${!pwvar}" | python3 -c '
import json, sys
email, first, last = sys.argv[1:4]
print(json.dumps({"schema_id": "default",
  "traits": {"email": email, "name": {"first": first, "last": last}},
  "credentials": {"password": {"config": {"password": sys.stdin.read()}}}}))' "$email" "$first" "$last" \
    | curl -sS -m 15 -o "$body" -w '%{http_code}' -H 'Content-Type: application/json' \
        --data-binary @- "$KRATOS_ADMIN/admin/identities")" || true
  case "$code" in
    200|201) id="$(uuid_of < "$body")" ;;
    409) id="$(curl -sS -m 15 -G --data-urlencode "credentials_identifier=$email" "$KRATOS_ADMIN/admin/identities" | uuid_of)" ;;
    *) red "Kratos admin returned HTTP ${code:-none} for $email"; return 1 ;;
  esac
  [ -n "$id" ] || { red "no identity id for $email"; return 1; }
  printf '%s' "$id"
}

echo "seed: Keto roles/permissions (tf-apigateway auth:seed-permissions)"
gw -job=auth:seed-permissions | grep -v OpenTelemetry | tail -n 1

echo "seed: Kratos identity for the portal test customer"
CUST_ID="$(kratos_identity "$EMAIL_LC" test test TEST_CUSTOMER_PORTAL_PASSWORD)" || die "failed to create/find customer identity"
echo "  kratos identity $CUST_ID"

echo "seed: Kratos identity + admin role for the local admin"
ADMIN_ID="$(kratos_identity "$LOCAL_ADMIN_EMAIL" Local Admin LOCAL_ADMIN_PASSWORD)" || die "failed to create/find admin identity"
gw -job=auth:assign-role -user-id="$ADMIN_ID" -role=admin | grep -v OpenTelemetry | tail -n 1
echo "  kratos identity $ADMIN_ID (role admin)"
echo "seed: auth users OK"
