#!/usr/bin/env bash
# make warmup: wait for the Next.js apps (prod mode builds on first start), then hit the routes the gate uses ONE AT
# A TIME before Playwright workers arrive (dev mode: compiles them; prod mode: warms server caches).
# Why (M5a memory root cause): next dev compiles a route on first request. 4 gate workers hitting many cold routes
# at once = parallel webpack compiles in one Node process = RSS spikes past the container limit -> OOM kill ->
# `next dev` restarts (exit 0) -> ECONNRESET/timeouts in the suite. Serial warmup keeps peak memory to one compile.
# Only GETs to local apps (localhost host ports). Non-2xx is fine (redirects/404s still compile the route).
. "$(dirname "$0")/lib.sh"
load_env
MP="http://127.0.0.1:${MEMBERPORTAL_HOST_PORT:-13001}"
AD="http://127.0.0.1:${ADMIN_PANEL_HOST_PORT:-13002}"
FN="http://127.0.0.1:${FUNNELS_HOST_PORT:-13003}"
ROUTES=(
  "$MP/login" "$MP/dashboard" "$MP/forgot-password" "$MP/orders" "$MP/subscriptions" "$MP/account"
  "$FN/api/healthz" "$FN/" "$FN/products" "$FN/checkout" "$FN/checkout2" "$FN/cart" "$FN/robots.txt" "$FN/sitemap.xml"
  "$FN/api/v1/categories" "$FN/internal_admin/login"
  "$AD/login" "$AD/dashboard"
)
# LOCAL_APP_MODE=prod: each app runs `next build` on first start (serialized, minutes each) and refuses connections
# until `next start` is up. Wait for every app to answer at all before warming routes.
wait_ready() { # wait_ready URL
  local u="$1" end=$(( $(date +%s) + ${WARMUP_READY_SECONDS:-1500} )) code
  while :; do
    code="$(curl -s -o /dev/null -m 30 -w '%{http_code}' "$u" 2>/dev/null || true)"
    case "$code" in ""|000|502|503|504) ;; *) echo "warmup: ready $code $u"; return 0;; esac
    [ "$(date +%s)" -lt "$end" ] || { echo "warmup: NOT ready after ${WARMUP_READY_SECONDS:-1500}s: $u"; return 1; }
    sleep 10
  done
}
for u in "$MP/login" "$FN/api/healthz" "$AD/login"; do wait_ready "$u" || true; done
[ "${1:-}" = "--wait-only" ] && exit 0
for u in "${ROUTES[@]}"; do
  out="$(curl -s -o /dev/null -m "${WARMUP_ROUTE_SECONDS:-240}" -w '%{http_code} %{time_total}s' "$u" 2>/dev/null || echo "ERR")"
  echo "warmup: $out $u"
done
