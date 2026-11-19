#!/usr/bin/env bash
# After a run: every order created in the LOCAL DB since <since> must be a test order. Read-only (SELECT only,
# inside a READ ONLY transaction).
# Mirrors tf-api src/utils/is_test_order.go IsTestOrder: first AND last name both "test" (trimmed,
# case-insensitive) OR a Sticky test gateway id (1, 3, 7, 8, 11, 12, 14); also accepts is_test_order=true
# (stored by tf-api from the same rule).
# Covered tables:
#   public.sticky_orders  every order row, whatever its processor: `type` STICKY, TFH or TF (TF Composition orders
#                         are sticky_orders rows with type 'TF' and external_tf_order_id). Name/gateway/flag rule above.
#   public.draft_orders   checkout drafts (no name columns): the owning customer (customers.first_name/last_name)
#                         must be "test test". Skipped with a note if the table does not exist.
# Usage: scripts/check-test-orders.sh <since: ISO-8601 timestamp, e.g. 2026-11-19T17:00:00Z>
. "$(dirname "$0")/lib.sh"
since="${1:?usage: check-test-orders.sh <since-iso-timestamp>}"
[[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]] || die "since must look like 2026-11-19T17:00:00Z"
load_env
U="${APP_DB_USER:-tf_api_local}"; D="${APP_DB_NAME:-tf_api_local}"

q() { # q <sql>: one read-only query against the LOCAL postgres container; unaligned, ' | ' separated.
  printf 'BEGIN READ ONLY;\n%s\nCOMMIT;\n' "$1" \
    | dc exec -T postgres psql -X -q -v ON_ERROR_STOP=1 -U "$U" -d "$D" -tA -F' | ' \
    || die "could not query local Postgres"
}
has_table() { [ "$(q "SELECT to_regclass('public.$1') IS NOT NULL;")" = "t" ]; }
has_col()   { [ "$(q "SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='$1' AND column_name='$2';")" = "1" ]; }
is_test_name() { # SQL predicate: both names "test" (trimmed, case-insensitive)
  printf "(lower(trim(coalesce(%s,''))) = 'test' AND lower(trim(coalesce(%s,''))) = 'test')" "$1" "$2"
}

fail=0; report=()

# 1. sticky_orders (STICKY / TFH / TF rows)
has_table sticky_orders || die "public.sticky_orders missing in the local DB (flyway not run?)"
TYPE_COL="'?'"; has_col sticky_orders type && TYPE_COL="coalesce(type::text,'?')"
TFID_COL="NULL"; has_col sticky_orders external_tf_order_id && TFID_COL="external_tf_order_id"
bad="$(q "SELECT id, $TYPE_COL, external_sticky_order_id, $TFID_COL, external_gateway_id, is_test_order
FROM public.sticky_orders
WHERE created_at >= '$since'::timestamptz
  AND NOT (
    coalesce(is_test_order, false)
    OR $(is_test_name billing_first_name billing_last_name)
    OR trim(coalesce(external_gateway_id,'')) IN ('1','3','7','8','11','12','14')
  );")"
by_type="$(q "SELECT $TYPE_COL || '=' || count(*) FROM public.sticky_orders WHERE created_at >= '$since'::timestamptz GROUP BY 1 ORDER BY 1;" | paste -sd, -)"
report+=("sticky_orders since $since: ${by_type:-0}")
if [ -n "$bad" ]; then
  red "TEST-ORDER CHECK FAILED: non-test sticky_orders rows (id | type | sticky id | tf order id | gateway | is_test_order):"
  printf '%s\n' "$bad" >&2; fail=1
fi

# 2. draft_orders (customer must be "test test")
if has_table draft_orders; then
  OT_COL="'?'"; has_col draft_orders order_type && OT_COL="coalesce(d.order_type::text,'?')"
  dbad="$(q "SELECT d.id, d.status, $OT_COL, d.customer_id
FROM public.draft_orders d LEFT JOIN public.customers c ON c.id = d.customer_id
WHERE d.created_at >= '$since'::timestamptz
  AND NOT $(is_test_name c.first_name c.last_name);")"
  dtotal="$(q "SELECT count(*) FROM public.draft_orders WHERE created_at >= '$since'::timestamptz;")"
  report+=("draft_orders since $since: $dtotal")
  if [ -n "$dbad" ]; then
    red "TEST-ORDER CHECK FAILED: draft_orders for non-test customers (id | status | order_type | customer_id):"
    printf '%s\n' "$dbad" >&2; fail=1
  fi
else
  report+=("draft_orders: table absent; skipped")
fi

if [ $fail -ne 0 ]; then
  red "STOP. Do not retry. Report to Michael immediately."
  exit 1
fi
grn "test-order check: OK (all test orders) - $(IFS='; '; echo "${report[*]}")"
