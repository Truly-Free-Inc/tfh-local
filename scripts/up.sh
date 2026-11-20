#!/usr/bin/env bash
# make up: SAFETY preflight, then build + start the core stack from apps/ checkouts.
# Re-running on a running stack is safe: images are rebuilt from cache with identical IDs (no provenance
# attestations), so long-running services are NOT recreated; only the idempotent one-shot jobs (flyway: no
# pending migrations, seed: marker skip, minio-init: --ignore-existing) run again.
. "$(dirname "$0")/lib.sh"
[ -d "$APPS/tf-api/src" ] || die "apps/tf-api missing. Run: make bootstrap"
"$ROOT/scripts/preflight.sh"
export BUILDX_NO_DEFAULT_ATTESTATIONS=1
# Keychain locked -> Desktop credential helper hangs every base-image pull; fall back to anonymous public pulls.
docker_creds_guard
# VECTOR=1 also starts the vector-search POC (profile `vector`).
[ "${VECTOR:-}" = "1" ] && export COMPOSE_PROFILES=vector
dc up -d --build
# The proxy builds its filter once at start from .state/egress/allowlist.txt (written by preflight above). Recreate it
# when that file changed since the proxy last started, so an EXTERNALS switch takes effect (and never lingers).
EG="$STATE/egress/allowlist.txt"; APPLIED="$STATE/egress/.applied.sha"
if [ -f "$EG" ] && [ "$(shasum "$EG" | cut -d' ' -f1)" != "$(cat "$APPLIED" 2>/dev/null)" ]; then
  dc up -d --no-deps --force-recreate proxy && shasum "$EG" | cut -d' ' -f1 > "$APPLIED"
fi
# LOCAL_APP_MODE=prod: the Next.js apps build on first start (serialized; several minutes). Wait for them first.
"$ROOT/scripts/warmup.sh" --wait-only
# `compose up --wait` treats the one-shot jobs' exit 0 as failure (compose 2.31), so poll our own health check.
for i in $(seq 1 60); do
  "$ROOT/scripts/health.sh" >/dev/null 2>&1 && break
  sleep 3
done
dc ps
"$ROOT/scripts/health.sh"
# Local auth users (portal test customer + local admin); idempotent, never touches feature flags.
"$ROOT/seed/auth-users.sh"
# Compile the gate's next dev routes serially (memory: avoids parallel compile storms). WARMUP=0 skips.
[ "${WARMUP:-1}" = "0" ] || "$ROOT/scripts/warmup.sh"
