#!/usr/bin/env bash
# Seed LOCAL auth users (idempotent; re-run any time). Local containers only.
#   1. Portal test customer ("test test") in the local tf-api DB: customers + customer_auth (bcrypt cost 12).
#      external_customer_id is a local placeholder so login never needs Sticky to look the customer up.
#   2. Same customer + a local admin as Kratos identities, via tf-apigateway's own jobs; admin gets role `admin`
#      in Keto (after auth:seed-permissions).
# Emails/passwords come from .env (gitignored): TEST_CUSTOMER_PORTAL_EMAIL/_PASSWORD, LOCAL_ADMIN_EMAIL/_PASSWORD.
# Never prints passwords. Never touches feature flags.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

: "${TEST_CUSTOMER_PORTAL_EMAIL:?set in .env}" "${TEST_CUSTOMER_PORTAL_PASSWORD:?set in .env}"
: "${LOCAL_ADMIN_EMAIL:?set in .env}" "${LOCAL_ADMIN_PASSWORD:?set in .env}"
case "$TEST_CUSTOMER_PORTAL_EMAIL$LOCAL_ADMIN_EMAIL" in
  *@trulyfreehome.com*|*@gmail.com*) echo "REFUSED: seed emails must be local-only (e.g. *@tfh-local.test)" >&2; exit 1;;
esac

DB_USER="${APP_DB_USER:-tf_api_local}"; DB_NAME="${APP_DB_NAME:-tf_api_local}"
EMAIL_LC="$(printf '%s' "$TEST_CUSTOMER_PORTAL_EMAIL" | tr '[:upper:]' '[:lower:]')"

# bcrypt cost 12 ($2y$ -> $2a$: same algorithm; Go's x/crypto/bcrypt emits $2a$). Password via stdin, not argv.
HASH="$(printf '%s' "$TEST_CUSTOMER_PORTAL_PASSWORD" | htpasswd -niBC 12 x | cut -d: -f2 | sed 's/^\$2y\$/$2a$/')"
case "$HASH" in \$2a\$12\$*) ;; *) echo "bcrypt hash generation failed" >&2; exit 1;; esac

echo "seed: portal test customer in tf-api DB"
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -q -U "$DB_USER" -d "$DB_NAME" \
  -v email="$EMAIL_LC" -v hash="$HASH" <<'SQL'
INSERT INTO customers (first_name, last_name, email, phone, external_customer_id)
SELECT 'test', 'test', :'email', '5555550100', 'tfh-local-offline-1'
WHERE NOT EXISTS (SELECT 1 FROM customers WHERE lower(email) = :'email');
INSERT INTO customer_auth (customer_id, password_hash, is_first_login)
SELECT id, :'hash', false FROM customers WHERE lower(email) = :'email'
ON CONFLICT (customer_id) DO UPDATE
  SET password_hash = EXCLUDED.password_hash, is_first_login = false,
      failed_login_attempts = 0, locked_until = NULL, updated_at = now();
SQL
docker compose exec -T postgres psql -At -U "$DB_USER" -d "$DB_NAME" -v email="$EMAIL_LC" <<'SQL'
SELECT 'customer id=' || c.id || ' name=' || c.first_name || ' ' || c.last_name || ' auth_row=' || (a.id IS NOT NULL)
FROM customers c LEFT JOIN customer_auth a ON a.customer_id = c.id WHERE lower(c.email) = :'email';
SQL

gw() { docker compose exec -T tf-apigateway ./main "$@" 2>&1; }
uuid_of() { grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -n1; }

echo "seed: Keto roles/permissions (tf-apigateway auth:seed-permissions)"
gw -job=auth:seed-permissions | grep -v OpenTelemetry | tail -n 1

echo "seed: Kratos identity for the portal test customer"
CUST_ID="$(gw -job=auth:create-user -email="$EMAIL_LC" -password="$TEST_CUSTOMER_PORTAL_PASSWORD" \
  -first-name=test -last-name=test | uuid_of)"
[ -n "$CUST_ID" ] || { echo "failed to create/find customer identity" >&2; exit 1; }
echo "  kratos identity $CUST_ID"

echo "seed: Kratos identity + admin role for the local admin"
ADMIN_ID="$(gw -job=auth:create-user -email="$LOCAL_ADMIN_EMAIL" -password="$LOCAL_ADMIN_PASSWORD" \
  -first-name=Local -last-name=Admin | uuid_of)"
[ -n "$ADMIN_ID" ] || { echo "failed to create/find admin identity" >&2; exit 1; }
gw -job=auth:assign-role -user-id="$ADMIN_ID" -role=admin | grep -v OpenTelemetry | tail -n 1
echo "  kratos identity $ADMIN_ID (role admin)"
echo "seed: auth users OK"
