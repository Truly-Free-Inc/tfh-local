#!/usr/bin/env bash
# make verify KEY=TFHFUNNEL-1234
# preflight -> stack health -> tfh-automation on the HOST against the local stack:
#   1) the ticket's tests:  --grep @KEY   (must exist; Playwright exits non-zero if none match)
#   2) the core gate:       --grep @gate --grep-invert @quarantine   (same as `npm run test:gate`)
# -> scripts/check-test-orders.sh -> .state/runs/<KEY>-<ts>/summary.md + reports. Exit non-zero if red.
# The suite's test-order guard (lib/test-order-guard.ts) is used as-is. Never edit or widen it.
. "$(dirname "$0")/lib.sh"
require_key
load_env
SUITE="$APPS/tfh-automation"
[ -d "$SUITE" ] || die "apps/tfh-automation missing. Run: make bootstrap"
[ -d "$SUITE/node_modules" ] || die "suite deps missing: (cd apps/tfh-automation && npm ci && npx playwright install webkit)"

"$ROOT/scripts/preflight.sh"
"$ROOT/scripts/health.sh"

# Env selection: tfh-automation picks the env from TARGET_ENV (config/envs.ts). It accepts dev|stage|prod
# today; `local` needs the small suite PR in docs/local-env.md. We REFUSE to fall back to dev + URL overrides,
# because the api-* project would still call the hard-coded develop tf-api (not local).
TENV="${TFH_AUTOMATION_TARGET_ENV:-local}"
[ "$TENV" = "local" ] || die "TFH_AUTOMATION_TARGET_ENV must be 'local' (got '$TENV'); remote envs are not allowed from tfh-local"
grep -qE "'local'" "$SUITE/config/envs.ts" || die "tfh-automation on branch $(git -C "$SUITE" rev-parse --abbrev-ref HEAD) has no 'local' env in config/envs.ts. See docs/local-env.md (suite PR needed; do not hand-edit to bypass)."

TS="$(date -u +%Y%m%dT%H%M%SZ)"; START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RUN="$STATE/runs/$KEY-$TS"; mkdir -p "$RUN"
SHAS="$(repo_shas_json)"

run_suite() { # label grep [grep-invert]
  local label="$1" grep="$2" inv="${3:-}" args
  args=(playwright test --grep "$grep" --retries 0 --reporter=list,html,json --output "$RUN/$label/test-results")
  [ -n "$inv" ] && args+=(--grep-invert "$inv")
  ( cd "$SUITE" && env TARGET_ENV=local TZ=UTC \
      PLAYWRIGHT_HTML_OUTPUT_DIR="$RUN/$label/html" PLAYWRIGHT_HTML_REPORT="$RUN/$label/html" PLAYWRIGHT_HTML_OPEN=never \
      PLAYWRIGHT_JSON_OUTPUT_NAME="$RUN/$label/results.json" \
      npx "${args[@]}" ) > "$RUN/$label.log" 2>&1
}

mkdir -p "$RUN/ticket" "$RUN/gate"
set +e
run_suite ticket "@$KEY";             T=$?
run_suite gate   "@gate" "@quarantine"; G=$?
"$ROOT/scripts/check-test-orders.sh" "$START" > "$RUN/test-orders.log" 2>&1; O=$?
set -e

status=green; [ $T -eq 0 ] && [ $G -eq 0 ] && [ $O -eq 0 ] || status=red
word() { [ "$1" -eq 0 ] && echo PASS || echo FAIL; }
cat > "$RUN/summary.md" <<MD
# verify $KEY ($TS): $(echo "$status" | tr a-z A-Z)

| step | result | log |
|---|---|---|
| ticket tests (@$KEY) | $(word $T) | ticket.log, ticket/html |
| core gate (@gate, not @quarantine) | $(word $G) | gate.log, gate/html |
| test orders only (local DB since $START) | $(word $O) | test-orders.log |

Repos (branch @ sha): \`$SHAS\`
MD
printf '{"key":"%s","ts":"%s","status":"%s","repos":%s}\n' "$KEY" "$TS" "$status" "$SHAS" > "$RUN/result.json"
cp "$RUN/result.json" "$STATE/runs/last-$KEY.json"
cat "$RUN/summary.md"
[ "$status" = green ] && grn "verify: GREEN ($RUN)" || { red "verify: RED ($RUN)"; tail -n 30 "$RUN"/*.log >&2 || true; exit 1; }
