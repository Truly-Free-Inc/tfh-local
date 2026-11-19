#!/usr/bin/env bash
# After a run: every order created in the LOCAL DB since <since> must be a test order. Read-only.
# Mirrors tf-api src/utils/is_test_order.go IsTestOrder: first AND last name both "test" (trimmed,
# case-insensitive) OR a Sticky test gateway id (1, 3, 7, 8, 11, 12, 14); also accepts is_test_order=true
# (stored by tf-api from the same rule). Table: public.sticky_orders (billing_first_name, billing_last_name,
# external_gateway_id, is_test_order, created_at).
# Usage: scripts/check-test-orders.sh <since: ISO-8601 timestamp, e.g. 2026-11-19T17:00:00Z>
# TODO: also cover public.draft_orders / TF-type orders once their name/test columns are confirmed.
. "$(dirname "$0")/lib.sh"
since="${1:?usage: check-test-orders.sh <since-iso-timestamp>}"
[[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]] || die "since must look like 2026-11-19T17:00:00Z"
load_env
U="${APP_DB_USER:-tf_api_local}"; D="${APP_DB_NAME:-tf_api_local}"

SQL="SELECT id, external_sticky_order_id, external_gateway_id, is_test_order
FROM public.sticky_orders
WHERE created_at >= '$since'::timestamptz
  AND NOT (
    coalesce(is_test_order, false)
    OR (lower(trim(coalesce(billing_first_name,''))) = 'test' AND lower(trim(coalesce(billing_last_name,''))) = 'test')
    OR trim(coalesce(external_gateway_id,'')) IN ('1','3','7','8','11','12','14')
  );"
TOTAL_SQL="SELECT count(*) FROM public.sticky_orders WHERE created_at >= '$since'::timestamptz;"

total="$(dc exec -T postgres psql -U "$U" -d "$D" -tAc "$TOTAL_SQL")" || die "could not query local Postgres"
bad="$(dc exec -T postgres psql -U "$U" -d "$D" -tA -F' | ' -c "$SQL")" || die "could not query local Postgres"
if [ -n "$bad" ]; then
  red "TEST-ORDER CHECK FAILED: non-test orders created since $since (id | sticky id | gateway | is_test_order):"
  printf '%s\n' "$bad" >&2
  red "STOP. Do not retry. Report to Michael immediately."
  exit 1
fi
grn "test-order check: OK ($total order(s) since $since, all test orders)"
