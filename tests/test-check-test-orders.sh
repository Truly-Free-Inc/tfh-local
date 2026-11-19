#!/usr/bin/env bash
# Fix (g): check-test-orders covers sticky_orders (STICKY/TFH/TF) AND draft_orders, read-only.
# docker is a stub that answers the queries from canned data (no DB touched); the SQL it receives is checked.
. "$(dirname "$0")/lib.sh"; set +e
SB="$(sandbox_copy)"; dummy_env "$SB"; BIN="$SB/.stubbin"; LOG="$SB/.stublog"; mkdir -p "$BIN" "$LOG"
cat > "$BIN/docker" <<'STUB'
#!/usr/bin/env bash
sql="$(cat)"; printf '%s\n---\n' "$sql" >> "$STUBLOG/sql"
case "$sql" in
  *"to_regclass('public.draft_orders')"*) [ "${NO_DRAFTS:-0}" = 1 ] && echo f || echo t ;;
  *to_regclass*) echo t ;;
  *information_schema.columns*) echo 1 ;;
  *"GROUP BY"*) printf 'STICKY=2\nTF=1\n' ;;
  *"FROM public.sticky_orders"*) [ -n "${BAD_STICKY:-}" ] && echo "$BAD_STICKY" ;;
  *"count(*) FROM public.draft_orders"*) echo 3 ;;
  *"FROM public.draft_orders"*) [ -n "${BAD_DRAFT:-}" ] && echo "$BAD_DRAFT" ;;
esac
exit 0
STUB
chmod +x "$BIN/docker"
run() { env STUBLOG="$LOG" PATH="$BIN:$PATH" "$@" bash "$SB/scripts/check-test-orders.sh" 2026-11-19T17:00:00Z 2>&1; }
out="$(run env)"; rc=$?
expect_true "all-test data -> exit 0 (rc=$rc)" [ $rc -eq 0 ]
expect_true "reports sticky types + drafts" grep -q 'STICKY=2,TF=1.*draft_orders since 2026-11-19T17:00:00Z: 3' <<<"$out"
out="$(run env BAD_DRAFT='9 | DRAFT | TF | 42')"; rc=$?
expect_true "non-test draft order -> exit 1" [ $rc -eq 1 ]
expect_true "names draft_orders" grep -q 'draft_orders for non-test customers' <<<"$out"
out="$(run env BAD_STICKY='7 | TF | | MID-1 | 2 | f')"; rc=$?
expect_true "non-test TF order -> exit 1" [ $rc -eq 1 ]
out="$(run env NO_DRAFTS=1)"; rc=$?
expect_true "missing draft_orders table -> skipped, exit 0" bash -c "[ $rc -eq 0 ] && grep -q 'draft_orders: table absent' <<<\"\$1\"" _ "$out"
expect_true  "every query runs in a READ ONLY transaction" bash -c "[ \$(grep -c '^BEGIN READ ONLY;' '$LOG/sql') -eq \$(grep -c '^---' '$LOG/sql') ]"
expect_false "no writes in any query" grep -qiE '\b(insert|update|delete|alter|drop|truncate|create)\b' "$LOG/sql"
expect_true  "draft check joins customers test test" grep -q "lower(trim(coalesce(c.first_name,''))) = 'test'" "$LOG/sql"
rm -rf "$SB"
done_tests
