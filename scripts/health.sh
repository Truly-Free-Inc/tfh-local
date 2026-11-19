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
# TODO: confirm tf-api health path (healthz vs health); tfh-automation probes /healthz on stage.
if curl -fsS -m 5 "http://127.0.0.1:$port/healthz" >/dev/null 2>&1 || curl -fsS -m 5 "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
  echo "ok: tf-api http on :$port"
else red "tf-api not answering on 127.0.0.1:$port"; fail=1; fi
[ $fail -eq 0 ] && grn "health: OK" || { red "health: FAILED"; exit 1; }
