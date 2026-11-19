#!/usr/bin/env bash
# SAFETY PREFLIGHT. Runs before `make up` and `make verify`. Exits 1 (loudly) on ANY violation.
# Do not bypass, weaken or skip this script. If it refuses, fix the config; do not edit the checks.
. "$(dirname "$0")/lib.sh"

FAIL=0
bad() { red "SAFETY REFUSAL: $*"; FAIL=1; }

[ -f "$ROOT/.env" ] || die "SAFETY REFUSAL: .env missing. cp .env.example .env and fill in NON-PROD values."
load_env

NONPROD="$ROOT/safety/nonprod-hosts.txt"
DENY="$ROOT/safety/prod-denylist.txt"
ALLOW="$ROOT/proxy/allowlist.txt"

matches() { # matches <host> <patternfile>
  local pats; pats="$(patterns "$2")"; [ -n "$pats" ] || return 1
  printf '%s\n' "$1" | grep -Eiq -f <(printf '%s\n' "$pats")
}

# 1. Sticky + TF hosts: set, on the non-prod allow-list, not on the prod deny-list.
[ -n "$(patterns "$NONPROD")" ] || bad "safety/nonprod-hosts.txt has no entries. A reviewer must add the non-prod Sticky/TF hosts."
for var in STICKY_DOMAIN TF_COMPOSITION_API_BASE_URL; do
  val="${!var:-}"
  if [ -z "$val" ]; then bad "$var is not set in .env"; continue; fi
  h="$(host_of "$val")"
  matches "$h" "$NONPROD" || bad "$var host '$h' is NOT in safety/nonprod-hosts.txt"
  matches "$h" "$DENY"    && bad "$var host '$h' matches safety/prod-denylist.txt (PRODUCTION?)"
done

# 2. Forbidden integrations: must be empty/absent in .env AND in the calling shell.
while IFS='=' read -r k v; do
  [ -n "$v" ] || continue
  case "$k" in
    SYTE_LINE*|SYTELINE*|INFOR*) bad "$k is set. Syteline/Infor must NEVER be configured." ;;
    TFH_CORE*|TFHCORE*)          bad "$k is set. tfhcore is OUT; never configure it." ;;
    AVALARA*)                    bad "$k is set. Avalara is OUT." ;;
  esac
done < <(env)

# 3. DB host must be the local container.
if [ -n "${DB_HOST:-}" ] && [ "$DB_HOST" != "postgres" ]; then
  bad "DB_HOST='$DB_HOST'. Only the local container 'postgres' is allowed."
fi

# 4. App env must not be production.
case "$(printf '%s' "${APP_ENV:-local}" | tr '[:upper:]' '[:lower:]')" in
  prod|production|live|main) bad "APP_ENV='${APP_ENV}' looks like production." ;;
esac

# 5. Proxy allow-list: every entry must be a non-prod host and must not hit the prod deny-list.
while IFS= read -r pat; do
  lit="$(printf '%s' "$pat" | sed -E 's/^\^//; s/\$$//; s/\\\././g')"
  matches "$lit" "$DENY"    && bad "proxy/allowlist.txt entry '$pat' matches the prod deny-list"
  matches "$lit" "$NONPROD" || bad "proxy/allowlist.txt entry '$pat' is not in safety/nonprod-hosts.txt"
done < <(patterns "$ALLOW")

# 6. Resolved compose config must not carry forbidden variables or point DB anywhere but local.
if command -v docker >/dev/null 2>&1; then
  cfg="$(dc config 2>/dev/null || true)"
  if [ -n "$cfg" ]; then
    printf '%s' "$cfg" | grep -Eq '(SYTE_?LINE|SYTELINE|INFOR_|TFH_?CORE|TFHCORE|AVALARA)[A-Z_]*:' \
      && bad "docker compose config contains a forbidden variable (Syteline/Infor/tfhcore/Avalara)"
    printf '%s' "$cfg" | grep -E '^\s+DB_HOST(_RO)?:' | grep -vEq 'DB_HOST(_RO)?: postgres$' \
      && bad "docker compose config has a DB_HOST that is not the local 'postgres' container"
  fi
fi

if [ "$FAIL" -ne 0 ]; then
  red "=================================================================="
  red " PREFLIGHT FAILED. Stack NOT started. See docs/safety.md."
  red " Do NOT edit safety checks to get past this. Ask Michael."
  red "=================================================================="
  exit 1
fi
grn "preflight: OK (non-prod Sticky/TF hosts, no Syteline/Infor/tfhcore/Avalara, local DB, APP_ENV=${APP_ENV:-local})"
