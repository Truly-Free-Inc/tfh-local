#!/usr/bin/env bash
# Stack health: core containers running/healthy, one-shot jobs exited 0, tf-api answering on the host port.
. "$(dirname "$0")/lib.sh"
load_env
fail=0
for s in postgres redis proxy ingress mailpit minio klaviyo-recorder tf-api; do
  st="$(dc ps --format '{{.State}} {{.Health}}' "$s" 2>/dev/null | head -1)"
  case "$st" in running*unhealthy*|"") red "unhealthy: $s ($st)"; fail=1 ;; running*) echo "ok: $s ($st)" ;; *) red "down: $s ($st)"; fail=1 ;; esac
done
for j in flyway seed minio-init; do
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
# Egress must stay locked: the proxy must refuse a host that is not on the allow-list.
code="$(dc exec -T tf-api bash -c 'exec 3<>/dev/tcp/proxy/8888 && printf "GET http://a.klaviyo.com/ HTTP/1.0\r\nHost: a.klaviyo.com\r\n\r\n" >&3 && head -1 <&3' 2>/dev/null | awk '{print $2}' || true)"
case "$code" in 403) echo "ok: proxy denies non-allow-listed host (a.klaviyo.com -> $code)" ;; *) red "proxy did NOT deny a.klaviyo.com (got '${code:-no response}')"; fail=1 ;; esac
[ $fail -eq 0 ] && grn "health: OK" || { red "health: FAILED"; exit 1; }
