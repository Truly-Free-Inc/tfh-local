#!/usr/bin/env bash
# Tiny test helpers for tests/*.sh. No network, no docker state changes (only `docker compose config`).
set -uo pipefail
T_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T_FAIL=0; T_N=0
ok()   { T_N=$((T_N+1)); printf '  ok   %s\n' "$*"; }
nok()  { T_N=$((T_N+1)); T_FAIL=1; printf '  FAIL %s\n' "$*" >&2; }
expect_true()  { local d="$1"; shift; if "$@"; then ok "$d"; else nok "$d"; fi; }
expect_false() { local d="$1"; shift; if "$@"; then nok "$d"; else ok "$d"; fi; }
# sandbox_copy: copy this repo's tracked + untracked-not-ignored files (working-tree versions) to a temp dir.
sandbox_copy() {
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/tfh-local-test.XXXXXX")"
  (cd "$T_ROOT" && git ls-files -z --cached --others --exclude-standard | rsync -a --from0 --files-from=- ./ "$d/")
  printf '%s' "$d"
}
# dummy_env <dir>: a throwaway .env with generated local-only dummy values (never real credentials).
dummy_env() {
  local d="$1" k
  cp "$d/.env.example" "$d/.env"
  for k in POSTGRES_USER POSTGRES_PASSWORD APP_DB_USER APP_DB_PASS MINIO_ROOT_USER MINIO_ROOT_PASSWORD \
           GATEWAY_DB_USER GATEWAY_DB_PASSWORD KRATOS_SECRETS_COOKIE KRATOS_SECRETS_CIPHER \
           KLAVIYO_PUBLIC_KEY KLAVIYO_PRIVATE_KEY; do
    sed -i.bak -E "s|^$k=.*|$k=dummy-$(printf '%s' "$k" | tr 'A-Z_' 'a-z-')-0123456789abcdef|" "$d/.env"
  done
  rm -f "$d/.env.bak"
}
done_tests() { printf '%s: %d checks, %s\n' "$(basename "$0")" "$T_N" "$([ $T_FAIL -eq 0 ] && echo PASS || echo FAIL)"; exit $T_FAIL; }
