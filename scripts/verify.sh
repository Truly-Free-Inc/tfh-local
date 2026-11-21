#!/usr/bin/env bash
# make verify KEY=TFHFUNNEL-1234   (or plain `make verify`: core gate only)
# preflight -> stack health -> tfh-automation on the HOST against the local stack:
#   1) the ticket's tests:  --grep '@KEY(?![0-9])'  (whole key: @X-12 never selects @X-123; must exist; Playwright exits non-zero if none match; skipped without KEY)
#   2) the core gate:       --grep @gate --grep-invert @quarantine   (same as `npm run test:gate`)
# -> scripts/check-test-orders.sh -> .state/runs/<KEY>-<ts>/summary.md + reports. Exit non-zero if red.
# The suite's test-order guard (lib/test-order-guard.ts) is used as-is. Never edit or widen it.
. "$(dirname "$0")/lib.sh"
if [ -n "${KEY:-}" ]; then require_key; LABEL="$KEY"; else LABEL=gate; fi
load_env
SUITE="$APPS/tfh-automation"
[ -d "$SUITE" ] || die "apps/tfh-automation missing. Run: make bootstrap"
[ -d "$SUITE/node_modules" ] || die "suite deps missing: (cd apps/tfh-automation && npm ci && npx playwright install webkit)"

"$ROOT/scripts/preflight.sh"
# Wait for the apps (prod-mode builds) and warm routes before health probes them.
"$ROOT/scripts/warmup.sh" >/dev/null 2>&1 || true
"$ROOT/scripts/health.sh"

# Env selection: tfh-automation picks the env from TARGET_ENV (config/envs.ts). It accepts dev|stage|prod
# today; `local` needs the small suite PR in docs/local-env.md. We REFUSE to fall back to dev + URL overrides,
# because the api-* project would still call the hard-coded develop tf-api (not local).
TENV="${TFH_AUTOMATION_TARGET_ENV:-local}"
[ "$TENV" = "local" ] || die "TFH_AUTOMATION_TARGET_ENV must be 'local' (got '$TENV'); remote envs are not allowed from tfh-local"
grep -qE "'local'" "$SUITE/config/envs.ts" || die "tfh-automation on branch $(git -C "$SUITE" rev-parse --abbrev-ref HEAD) has no 'local' env in config/envs.ts. See docs/local-env.md (suite PR needed; do not hand-edit to bypass)."

TS="$(date -u +%Y%m%dT%H%M%SZ)"; START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RUN="$STATE/runs/$LABEL-$TS"; mkdir -p "$RUN"
SHAS="$(repo_shas_json)"

# Local suite credentials: the only portal user locally is the seeded "test test" customer (.env); staff (admin) logins
# use the seeded local admin (LOCAL_ADMIN_EMAIL/_PASSWORD -> the suite's ADMIN_USER/ADMIN_PASSWORD). Workers and the
# wall-clock cap are tunable: VERIFY_WORKERS (default 2), VERIFY_MAX_SECONDS (default 1500 = 25 min).
# 2 workers (was 4): with LOCAL_APP_MODE=dev the portal/funnels run `next dev` (parallel route compiles = OOM
# restarts). Routes are warmed serially first (scripts/warmup.sh; in prod mode it also waits for the builds).
WORKERS="${VERIFY_WORKERS:-2}"; MAXS="${VERIFY_MAX_SECONDS:-1500}"
# Spreedly (M9): TFH_SPREEDLY=real tells the suite the TF payment form (Spreedly iframes) can render, i.e.
# EXTERNALS=real AND the sandbox key NEXT_PUBLIC_SPREEDLY_ENVIRONMENT_KEY_TF is configured. Otherwise offline.
TFH_SPREEDLY_MODE=offline
if [ "$(printf '%s' "${EXTERNALS:-offline}" | tr '[:upper:]' '[:lower:]')" = real ] && [ -n "${NEXT_PUBLIC_SPREEDLY_ENVIRONMENT_KEY_TF:-}" ]; then
  TFH_SPREEDLY_MODE=real
fi
run_suite() { # label grep [grep-invert]
  local label="$1" grep="$2" inv="${3:-}" args
  args=(playwright test --grep "$grep" --retries 0 --workers "$WORKERS" --reporter=list,html,json --output "$RUN/$label/test-results")
  [ -n "$inv" ] && args+=(--grep-invert "$inv")
  # Credentials are exported (shell builtin), not passed as `env NAME=value` argv (visible in `ps`).
  ( cd "$SUITE" && export MEMBER_PORTAL_USER="${TEST_CUSTOMER_PORTAL_EMAIL:-}" \
      MEMBER_PORTAL_PASSWORD="${TEST_CUSTOMER_PORTAL_PASSWORD:-}" \
      ADMIN_USER="${LOCAL_ADMIN_EMAIL:-}" ADMIN_PASSWORD="${LOCAL_ADMIN_PASSWORD:-}" \
      TF_API_BASIC_AUTH="${TF_API_BASIC_AUTH_USERNAME:-}:${TF_API_BASIC_AUTH_PASSWORD:-}" \
      TFH_EXTERNALS="$(printf '%s' "${EXTERNALS:-offline}" | tr '[:upper:]' '[:lower:]')" \
      TFH_SPREEDLY="$TFH_SPREEDLY_MODE" \
      BUILDER_PUBLIC_API_KEY="${LOCAL_BUILDER_PUBLIC_KEY_FUNNEL:-}" && \
    for v in TEST_CUSTOMER_FIRST_NAME TEST_CUSTOMER_LAST_NAME TEST_CUSTOMER_EMAIL TEST_CUSTOMER_PHONE TEST_CUSTOMER_STREET \
             TEST_CUSTOMER_CITY TEST_CUSTOMER_STATE TEST_CUSTOMER_ZIP TEST_CUSTOMER_COUNTRY \
             TFH_STICKY_CARD_NUMBER TFH_STICKY_CARD_EXP TFH_STICKY_CARD_CVV TFH_STICKY_CARD_NAME \
             TF_SPREEDLY_CARD_NUMBER TF_SPREEDLY_CARD_EXP TF_SPREEDLY_CARD_CVV TF_SPREEDLY_CARD_NAME; do
      # Order tests (EXTERNALS=real): "test test" customer + Sticky TEST card from .env, exported only when set.
      # The suite refuses any other name (fixtures/test-customer.ts) and every order goes through lib/test-order-guard.ts.
      if [ -n "${!v:-}" ]; then export "$v=${!v}"; fi
    done; \
    env TARGET_ENV=local TZ=UTC TFR_RETRIES=0 \
      PLAYWRIGHT_HTML_OUTPUT_DIR="$RUN/$label/html" PLAYWRIGHT_HTML_REPORT="$RUN/$label/html" PLAYWRIGHT_HTML_OPEN=never \
      PLAYWRIGHT_JSON_OUTPUT_NAME="$RUN/$label/results.json" \
      perl -e 'alarm shift; exec @ARGV' "$MAXS" npx "${args[@]}" ) > "$RUN/$label.log" 2>&1
}

mkdir -p "$RUN/ticket" "$RUN/gate"
set +e
if [ -n "${KEY:-}" ]; then run_suite ticket "$(key_grep "$KEY")"; T=$?; else T=0; fi
run_suite gate   "@gate" "@quarantine"; G=$?
"$ROOT/scripts/check-test-orders.sh" "$START" > "$RUN/test-orders.log" 2>&1; O=$?
set -e

status=green; [ $T -eq 0 ] && [ $G -eq 0 ] && [ $O -eq 0 ] || status=red
word() { [ "$1" -eq 0 ] && echo PASS || echo FAIL; }
cat > "$RUN/summary.md" <<MD
# verify $LABEL ($TS): $(echo "$status" | tr a-z A-Z)

| step | result | log |
|---|---|---|
| ticket tests (@${KEY:-none}) | $( [ -n "${KEY:-}" ] && word $T || echo SKIPPED) | ticket.log, ticket/html |
| core gate (@gate, not @quarantine) | $(word $G) | gate.log, gate/html |
| test orders only (local DB since $START) | $(word $O) | test-orders.log |

Repos (branch @ sha): \`$SHAS\`
MD
printf '{"key":"%s","ts":"%s","status":"%s","repos":%s}\n' "$LABEL" "$TS" "$status" "$SHAS" > "$RUN/result.json"
cp "$RUN/result.json" "$STATE/runs/last-$LABEL.json"
cat "$RUN/summary.md"
[ "$status" = green ] && grn "verify: GREEN ($RUN)" || { red "verify: RED ($RUN)"; tail -n 30 "$RUN"/*.log >&2 || true; exit 1; }
