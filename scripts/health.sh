#!/usr/bin/env bash
# Stack health: core containers running/healthy, one-shot jobs exited 0, tf-api answering on the host port.
. "$(dirname "$0")/lib.sh"
load_env
fail=0
for s in postgres redis proxy ingress mailpit minio klaviyo-recorder tf-api \
         gateway-postgres kratos keto tf-apigateway memberportal admin-panel aff-landing-pages; do
  st="$(dc ps --format '{{.State}} {{.Health}}' "$s" 2>/dev/null | head -1)"
  case "$st" in running*unhealthy*|"") red "unhealthy: $s ($st)"; fail=1 ;; running*) echo "ok: $s ($st)" ;; *) red "down: $s ($st)"; fail=1 ;; esac
done
for j in flyway seed minio-init kratos-migrate keto-migrate; do
  code="$(docker inspect -f '{{.State.ExitCode}}' "$(dc ps -aq "$j" 2>/dev/null | head -1)" 2>/dev/null || echo missing)"
  [ "$code" = "0" ] && echo "ok: $j (exit 0)" || { red "job $j exit=$code"; fail=1; }
done
port="${TF_API_HOST_PORT:-13000}"
# tf-api health route is constants.HealthCheckRoute = /health (checks write DB, read DB and Redis).
if curl -fsS -m 5 "http://127.0.0.1:$port/health" | grep -q '"status":"ok"'; then
  echo "ok: tf-api /health on :$port"
else red "tf-api /health not ok on 127.0.0.1:$port"; fail=1; fi
probe() { # probe <name> <url>
  if curl -fsS -m 5 -o /dev/null "$2"; then echo "ok: $1 $2"; else red "not answering: $1 $2"; fail=1; fi
}
probe mailpit-ui      "http://127.0.0.1:${MAILPIT_UI_HOST_PORT:-18025}/"
probe minio-api       "http://127.0.0.1:${MINIO_API_HOST_PORT:-19000}/minio/health/live"
probe minio-console   "http://127.0.0.1:${MINIO_CONSOLE_HOST_PORT:-19001}/"
probe tf-apigateway   "http://127.0.0.1:${APIGATEWAY_HOST_PORT:-13004}/health"
probe kratos-public   "http://127.0.0.1:${KRATOS_PUBLIC_HOST_PORT:-14433}/health/ready"
# memberportal runs `next dev`: the first hit of a route compiles it (~20-30 s), hence the long timeout.
if curl -fsS -m 90 -o /dev/null "http://127.0.0.1:${MEMBERPORTAL_HOST_PORT:-13001}/login"; then
  echo "ok: memberportal http://127.0.0.1:${MEMBERPORTAL_HOST_PORT:-13001}/login"
else red "not answering: memberportal /login"; fail=1; fi
# Admin panel + funnels also run `next dev` (first compile is slow).
probe_slow() { if curl -sS -m 120 -o /dev/null -w '%{http_code}' "$2" | grep -qE '^(200|30[0-9])$'; then echo "ok: $1 $2"; else red "not answering: $1 $2"; fail=1; fi; }
probe_slow admin-panel "http://127.0.0.1:${ADMIN_PANEL_HOST_PORT:-13002}/login"
probe_slow storefront "http://127.0.0.1:${STOREFRONT_HOST_PORT:-13005}/api/healthz"
probe_slow funnels     "http://127.0.0.1:${FUNNELS_HOST_PORT:-13003}/internal_admin/login"
if [ -n "$(dc ps -q vector-search 2>/dev/null)" ]; then probe vector-search "http://127.0.0.1:${VECTOR_SEARCH_HOST_PORT:-18077}/"; fi
# Egress must stay locked: DENY for prod/Sticky/Klaviyo/Mailgun/Avalara/tfhcore/builder.io root, ALLOW only the
# approved read-only hosts (see scripts/egress-check.sh).
"$ROOT/scripts/egress-check.sh" || fail=1
# Node egress guard (docker/node-egress-preload.cjs) must be ACTIVE in every container that loads it, i.e. it found the
# app's undici. A node process started with the container's NODE_OPTIONS reports the state the dev server got.
for s in memberportal aff-landing-pages; do
  gs="$(dc exec -T "$s" node -e 'process.stdout.write(String(globalThis.__TFH_EGRESS_GUARD||"NOT LOADED"))' 2>/dev/null | tail -1 || true)"
  if [ "$gs" = ACTIVE ]; then echo "ok: egress guard ACTIVE in $s"; else red "egress guard not active in $s (got '${gs:-no response}')"; fail=1; fi
done
# Builder.io read-only (proxy/readonly-allowlist.txt): egress-check.sh probes the proxy (builder.io/api.builder.io
# 403, cdn.builder.io 200). End to end from a Node app: GET to cdn.builder.io works via the guard + proxy; POST is
# refused locally by the guard.
if [ -s "$ROOT/proxy/readonly-allowlist.txt" ] && grep -q 'cdn' "$ROOT/proxy/readonly-allowlist.txt"; then
  r="$(dc exec -T memberportal node -e '
    const u="https://cdn.builder.io/";
    (async () => {
      let get, post;
      try { get = "status " + (await fetch(u, { method: "GET", redirect: "manual" })).status; } catch (e) { get = "ERR " + (e.cause && e.cause.message || e.message); }
      try { post = "status " + (await fetch(u, { method: "POST", body: "x" })).status; } catch (e) { post = "ERR " + (e.cause && e.cause.message || e.message); }
      console.log("GET=" + get + "|POST=" + post);
    })();' 2>/dev/null | tail -1 || true)"
  case "$r" in "GET=status "*"|POST=ERR "*refused*) echo "ok: memberportal fetch cdn.builder.io GET allowed, POST refused ($r)" ;;
    *) red "memberportal Builder read-only check failed ($r)"; fail=1 ;; esac
fi
[ $fail -eq 0 ] && grn "health: OK" || { red "health: FAILED"; exit 1; }
