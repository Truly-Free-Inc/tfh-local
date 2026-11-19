#!/usr/bin/env bash
# SAFETY PREFLIGHT. Runs before `make up` and `make verify`. Exits 1 (loudly) on ANY violation.
# Do not bypass, weaken or skip this script. If it refuses, fix the config; do not edit the checks.
. "$(dirname "$0")/lib.sh"

FAIL=0
bad() { red "SAFETY REFUSAL: $*"; FAIL=1; }

[ -f "$ROOT/.env" ] || die "SAFETY REFUSAL: .env missing. cp .env.example .env and fill in NON-PROD values."
# Snapshot the CALLING shell's env before .env is loaded: docker compose gives shell values precedence over .env,
# so a value set in the shell must be checked even when .env overrides it inside this script.
CALLER_ENV="$(env)"
load_env

NONPROD="$ROOT/safety/nonprod-hosts.txt"
DENY="$ROOT/safety/prod-denylist.txt"
ALLOW="$ROOT/proxy/allowlist.txt"

matches() { # matches <host> <patternfile>
  local pats; pats="$(patterns "$2")"; [ -n "$pats" ] || return 1
  printf '%s\n' "$1" | grep -Eiq -f <(printf '%s\n' "$pats")
}

# 0. EXTERNALS mode. offline (default) = Sticky/TF must be impossible to reach; real = non-prod hosts via the proxy.
EXTERNALS="$(printf '%s' "${EXTERNALS:-offline}" | tr '[:upper:]' '[:lower:]')"
case "$EXTERNALS" in offline|real) ;; *) bad "EXTERNALS='$EXTERNALS'. Must be 'offline' or 'real'." ;; esac

# A value is "offline-safe" if it is empty or its host is under the reserved, never-resolvable .invalid TLD (RFC 2606).
offline_safe() { [ -z "$1" ] && return 0; case "$(host_of "$1")" in *.invalid) return 0 ;; esac; return 1; }

if [ "$EXTERNALS" = "offline" ]; then
  # 1-offline. Every STICKY_* / TF_COMPOSITION_* value (in .env AND the calling shell) must be empty or *.invalid.
  while IFS='=' read -r k v; do
    case "$k" in
      STICKY_*|TF_COMPOSITION_*) offline_safe "$v" || bad "$k is set to a real value (in .env or your shell). EXTERNALS=offline requires it empty or a *.invalid placeholder." ;;
    esac
  done < <(env; printf '%s\n' "$CALLER_ENV")
  # 5-offline. The egress allow-list must be EMPTY (the proxy then denies every host).
  n="$(patterns "$ALLOW" | wc -l | tr -d ' ')"
  [ "$n" = "0" ] || bad "proxy/allowlist.txt has $n entr(y/ies). EXTERNALS=offline requires zero entries."
  # safety/nonprod-hosts.txt must be unchanged from the committed version and carry no entries.
  [ -z "$(patterns "$NONPROD")" ] || bad "safety/nonprod-hosts.txt has entries. EXTERNALS=offline requires none."
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$ROOT" diff --quiet HEAD -- safety/nonprod-hosts.txt proxy/allowlist.txt \
      || bad "safety/nonprod-hosts.txt or proxy/allowlist.txt has uncommitted changes. EXTERNALS=offline requires them unchanged."
  fi
else
  # 1. Sticky + TF hosts: set, on the non-prod allow-list, not on the prod deny-list.
  [ -n "$(patterns "$NONPROD")" ] || bad "safety/nonprod-hosts.txt has no entries. A reviewer must add the non-prod Sticky/TF hosts."
  for var in STICKY_DOMAIN TF_COMPOSITION_API_BASE_URL; do
    val="${!var:-}"
    if [ -z "$val" ]; then bad "$var is not set in .env"; continue; fi
    h="$(host_of "$val")"
    matches "$h" "$NONPROD" || bad "$var host '$h' is NOT in safety/nonprod-hosts.txt"
    matches "$h" "$DENY"    && bad "$var host '$h' matches safety/prod-denylist.txt (PRODUCTION?)"
  done

  # 5. Proxy allow-list: every entry must be a non-prod host and must not hit the prod deny-list.
  while IFS= read -r pat; do
    lit="$(printf '%s' "$pat" | sed -E 's/^\^//; s/\$$//; s/\\\././g')"
    matches "$lit" "$DENY"    && bad "proxy/allowlist.txt entry '$pat' matches the prod deny-list"
    matches "$lit" "$NONPROD" || bad "proxy/allowlist.txt entry '$pat' is not in safety/nonprod-hosts.txt"
  done < <(patterns "$ALLOW")
fi

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

# 6. Resolved compose config must not carry forbidden variables or point DB anywhere but local.
if command -v docker >/dev/null 2>&1; then
  cfg="$(dc config 2>/dev/null || true)"
  if [ -n "$cfg" ]; then
    printf '%s' "$cfg" | grep -Eq '(SYTE_?LINE|SYTELINE|INFOR_|TFH_?CORE|TFHCORE|AVALARA)[A-Z_]*:' \
      && bad "docker compose config contains a forbidden variable (Syteline/Infor/tfhcore/Avalara)"
    if [ "$EXTERNALS" = "offline" ]; then
      # Compose resolves shell env over .env, so check what the containers would actually get.
      while IFS= read -r line; do
        k="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*([A-Z0-9_]+):.*/\1/')"
        v="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*[A-Z0-9_]+:[[:space:]]*//; s/^"//; s/"$//')"
        offline_safe "$v" || bad "docker compose config sets $k to a real value while EXTERNALS=offline"
      done < <(printf '%s\n' "$cfg" | grep -E '^[[:space:]]+(STICKY_|TF_COMPOSITION_)[A-Z0-9_]*:' || true)
    fi
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
if [ "$EXTERNALS" = "offline" ]; then
  grn "preflight: OK (EXTERNALS=offline: no Sticky/TF values, empty egress allow-list; no Syteline/Infor/tfhcore/Avalara, local DB, APP_ENV=${APP_ENV:-local})"
else
  grn "preflight: OK (EXTERNALS=real: non-prod Sticky/TF hosts, no Syteline/Infor/tfhcore/Avalara, local DB, APP_ENV=${APP_ENV:-local})"
fi
