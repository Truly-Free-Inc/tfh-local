#!/bin/bash
# One-time seed for a FRESH local DB. Runs after Flyway. If the marker table exists, does nothing.
# Feature flags are seeded HERE ONLY. No script in tfh-local ever updates feature flags afterwards.
set -euo pipefail
until pg_isready -q; do sleep 1; done
if [ "$(psql -tAc "select to_regclass('public.tfh_local_seed_state') is not null")" = "t" ]; then
  echo "seed: already applied ($(psql -tAc 'select applied_at from public.tfh_local_seed_state limit 1')); skipping"
  exit 0
fi
shopt -s nullglob
files=(/seed/sql/*.sql)
{
  echo "BEGIN;"
  for f in "${files[@]}"; do echo "\\echo seed: applying $(basename "$f")"; echo "\\i $f"; done
  echo "CREATE TABLE public.tfh_local_seed_state (applied_at timestamptz NOT NULL DEFAULT now());"
  echo "INSERT INTO public.tfh_local_seed_state DEFAULT VALUES;"
  echo "COMMIT;"
} | psql -v ON_ERROR_STOP=1
echo "seed: done (${#files[@]} file(s))"
