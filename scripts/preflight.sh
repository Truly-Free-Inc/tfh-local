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
# Optional gitignored extra deny list (named internal hosts kept out of the public repo). Enforced the same way.
DENY_LOCAL="$ROOT/safety/prod-denylist.local.txt"
if [ -f "$DENY_LOCAL" ]; then
  DENY_ALL="$(mktemp)"; trap 'rm -f "$DENY_ALL"' EXIT
  cat "$DENY" "$DENY_LOCAL" > "$DENY_ALL"; DENY_FILES=("$DENY" "$DENY_LOCAL"); DENY="$DENY_ALL"
else
  DENY_FILES=("$DENY")
fi
ALLOW="$ROOT/proxy/allowlist.txt"
# Read-only third-party content hosts (Builder.io). Separate from the Sticky/TF allow-list; fixed approved set.
READONLY="$ROOT/proxy/readonly-allowlist.txt"
READONLY_APPROVED='^cdn\.builder\.io$'
# Reviewed exceptions to the deny list (exact literal hosts only; Michael 2026-11-20 for the dev/stage Sticky + TF hosts).
EXC="$ROOT/safety/reviewed-exceptions.txt"
# Effective proxy filter, GENERATED below (gitignored). The proxy reads only this + the read-only list.
EGRESS_DIR="$STATE/egress"; EGRESS_FILTER="$EGRESS_DIR/allowlist.txt"

matches() { # matches <host> <patternfile>
  local pats; pats="$(patterns "$2")"; [ -n "$pats" ] || return 1
  printf '%s\n' "$1" | grep -Eiq -f <(printf '%s\n' "$pats")
}
lit_of() { printf '%s' "$1" | sed -E 's/^\^//; s/\$$//; s/\\\././g'; }
# An exception entry is ONE literal host: ^label(\.label)+$ (lowercase, escaped dots, no wildcards/groups).
literal_host_pattern() { [[ "$1" =~ ^\^[a-z0-9-]+(\\\.[a-z0-9-]+)+\$$ ]]; }
# is_exception <host>: the host equals (exactly) one entry of safety/reviewed-exceptions.txt.
is_exception() {
  [ -f "$EXC" ] || return 1
  local p; while IFS= read -r p; do [ "$(lit_of "$p")" = "$1" ] && return 0; done < <(patterns "$EXC"); return 1
}
# denied <host>: on the prod deny list and NOT an exact reviewed exception.
denied() { matches "$1" "$DENY" && ! is_exception "$1"; }

# 0a. Pattern hygiene: every regex in the deny list, the egress allow-lists and the non-prod list must be
#     ^...$ anchored with escaped dots (see lib.sh pattern_anchored). Applies in both EXTERNALS modes.
for pf in "${DENY_FILES[@]}" "$ALLOW" "$NONPROD" "$EXC" "$ROOT/proxy/readonly-allowlist.txt"; do
  [ -f "$pf" ] || continue
  while IFS= read -r pat; do
    pattern_anchored "$pat" || bad "${pf#$ROOT/} entry '$pat' is not anchored (^...\$) with escaped dots"
  done < <(patterns "$pf")
done

# 0b. Reviewed exceptions (both modes): each entry is one literal host that is also on safety/nonprod-hosts.txt.
if [ -f "$EXC" ]; then
  while IFS= read -r pat; do
    literal_host_pattern "$pat" || bad "safety/reviewed-exceptions.txt entry '$pat' is not ONE literal host (^host\.example$; no wildcards)"
    matches "$(lit_of "$pat")" "$NONPROD" || bad "safety/reviewed-exceptions.txt entry '$pat' is not on safety/nonprod-hosts.txt"
  done < <(patterns "$EXC")
fi
# 0c. The reviewed lists must be committed (reviewed = merged), in both modes.
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ROOT" diff --quiet HEAD -- safety/nonprod-hosts.txt safety/reviewed-exceptions.txt safety/prod-denylist.txt \
      proxy/allowlist.txt proxy/readonly-allowlist.txt \
    || bad "safety/nonprod-hosts.txt, safety/reviewed-exceptions.txt, safety/prod-denylist.txt, proxy/allowlist.txt or proxy/readonly-allowlist.txt has uncommitted changes. Commit (and get them reviewed) first."
fi

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
  # 5-offline. The GENERATED proxy filter (below) is written EMPTY: the proxy denies every Sticky/TF host.
else
  # 1. Sticky + TF hosts: set, on the non-prod allow-list, not on the prod deny-list.
  [ -n "$(patterns "$NONPROD")" ] || bad "safety/nonprod-hosts.txt has no entries. A reviewer must add the non-prod Sticky/TF hosts."
  for var in STICKY_DOMAIN TF_COMPOSITION_API_BASE_URL; do
    val="${!var:-}"
    if [ -z "$val" ]; then bad "$var is not set in .env"; continue; fi
    h="$(host_of "$val")"
    matches "$h" "$NONPROD" || bad "$var host '$h' is NOT in safety/nonprod-hosts.txt"
    denied "$h" && bad "$var host '$h' matches safety/prod-denylist.txt (PRODUCTION?) and is not an exact safety/reviewed-exceptions.txt entry"
  done
  case "${TF_COMPOSITION_API_BASE_URL:-}" in https://*|"") ;; *) bad "TF_COMPOSITION_API_BASE_URL must be https://" ;; esac
  case "${STICKY_DOMAIN:-}" in */*|*:*|*@*) bad "STICKY_DOMAIN must be a bare host (tf-api builds https://<STICKY_APP_KEY>.<STICKY_DOMAIN>)" ;; esac
  [ -n "${STICKY_USERNAME:-}" ] && [ -n "${STICKY_PASSWORD:-}" ] || bad "STICKY_USERNAME / STICKY_PASSWORD are not set in .env"
  [ -n "${TF_COMPOSITION_API_TOKEN:-}" ] || bad "TF_COMPOSITION_API_TOKEN is not set in .env"

  # 1b. The Sticky API host tf-api really calls: <STICKY_APP_KEY>.<STICKY_DOMAIN>. The app key must be one DNS label;
  #     the host is checked against every deny pattern EXCEPT those that deny the reviewed STICKY_DOMAIN itself (that
  #     is the reviewed exception), so e.g. a "prod" label is still refused. Values are never printed.
  STICKY_API_HOST=""
  sd="$(host_of "${STICKY_DOMAIN:-}")"; ak="$(printf '%s' "${STICKY_APP_KEY:-}" | tr '[:upper:]' '[:lower:]')"
  if [ -z "$ak" ]; then bad "STICKY_APP_KEY is not set in .env"
  elif ! [[ "$ak" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then bad "STICKY_APP_KEY is not a single DNS label (value not shown)"
  elif [ -n "$sd" ]; then
    other_deny="$(patterns "$DENY" | while IFS= read -r p; do printf '%s\n' "$sd" | grep -Eiq -- "$p" || printf '%s\n' "$p"; done)"
    if [ -n "$other_deny" ] && printf '%s\n' "$ak.$sd" | grep -Eiq -f <(printf '%s\n' "$other_deny"); then
      bad "the Sticky API host <STICKY_APP_KEY>.<STICKY_DOMAIN> matches safety/prod-denylist.txt (value not shown)"
    else STICKY_API_HOST="$ak.$sd"; fi
  fi

  # 5. Proxy allow-list: every entry must be a non-prod host and must not hit the prod deny-list.
  while IFS= read -r pat; do
    literal_host_pattern "$pat" || bad "proxy/allowlist.txt entry '$pat' is not ONE literal host (^host\.example$)"
    lit="$(lit_of "$pat")"
    denied "$lit"             && bad "proxy/allowlist.txt entry '$pat' matches the prod deny-list (and is not a reviewed exception)"
    matches "$lit" "$NONPROD" || bad "proxy/allowlist.txt entry '$pat' is not in safety/nonprod-hosts.txt"
  done < <(patterns "$ALLOW")
fi

# 5b. Read-only list (both modes): every entry must be EXACTLY one of READONLY_APPROVED and miss the prod deny-list.
#     Sticky/TF/Klaviyo/AWS/prod hosts can never be routed through it.
if [ -f "$READONLY" ]; then
  while IFS= read -r pat; do
    printf '%s\n' "$READONLY_APPROVED" | grep -qxF -- "$pat" || bad "proxy/readonly-allowlist.txt entry '$pat' is not an approved read-only host (scripts/preflight.sh READONLY_APPROVED)"
    lit="$(printf '%s' "$pat" | sed -E 's/^\^//; s/\$$//; s/\\\././g')"
    matches "$lit" "$DENY" && bad "proxy/readonly-allowlist.txt entry '$pat' matches the prod deny-list"
  done < <(patterns "$READONLY")
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

# 2b. Builder.io stays read-only: only PUBLIC API keys. Refuse any Builder private/write key (by name, in .env and the
#     calling shell) and any value with the Builder private-key prefix 'bpk-' (whatever the variable is called).
while IFS='=' read -r k v; do
  [ -n "$v" ] || continue
  case "$k" in
    *BUILDER*PRIVATE*|*BUILDER*SECRET*|*BUILDER*WRITE*|*BUILDER*ADMIN*) bad "$k is set. Only public Builder.io keys are allowed (read-only)." ;;
  esac
  case "$v" in bpk-*|\"bpk-*|\'bpk-*) bad "$k holds a Builder.io private key (bpk-...). Only public keys are allowed." ;; esac
done < <(env; printf '%s\n' "$CALLER_ENV")

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
    printf '%s' "$cfg" | grep -Eq '(BUILDER[A-Z_]*(PRIVATE|SECRET|WRITE|ADMIN)[A-Z_]*: *[^ ]|: *"?bpk-)' \
      && bad "docker compose config carries a Builder.io private key (variable name or bpk- value)"
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

# 7. Effective proxy filter (the proxy mounts .state/egress read-only and reads ONLY this file + the read-only list).
#    offline: empty. real: proxy/allowlist.txt + the single derived Sticky API host. Any refusal: empty (fail closed).
#    Restart the proxy after it changes (make up does: scripts/up.sh).
mkdir -p "$EGRESS_DIR"
{
  echo "# GENERATED by scripts/preflight.sh (EXTERNALS=$EXTERNALS, ok=$([ "$FAIL" -eq 0 ] && echo yes || echo no)). Do not edit; gitignored."
  if [ "$FAIL" -eq 0 ] && [ "$EXTERNALS" = "real" ]; then
    patterns "$ALLOW"
    if [ -n "${STICKY_API_HOST:-}" ]; then printf '^%s$\n' "$(printf '%s' "$STICKY_API_HOST" | sed 's/\./\\./g')"; fi
  fi
} > "$EGRESS_FILTER.tmp" && mv "$EGRESS_FILTER.tmp" "$EGRESS_FILTER"

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
  grn "preflight: OK (EXTERNALS=real: reviewed dev/stage Sticky + TF dev hosts, $(patterns "$EGRESS_FILTER" | wc -l | tr -d ' ') generated proxy filter entries, no Syteline/Infor/tfhcore/Avalara, local DB, APP_ENV=${APP_ENV:-local})"
fi
