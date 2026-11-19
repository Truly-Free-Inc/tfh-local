#!/usr/bin/env bash
# Egress lock proof, run by scripts/health.sh. From INSIDE the app network (exec in the tf-api container, which can
# only reach the internet through `proxy`), ask the proxy for each host and check its answer:
#   DENY (403) for prod TFH hosts, Sticky (sticky.io, limelightcrm.com), Klaviyo, Mailgun, Avalara, tfhcore and the
#   builder.io root;  ALLOW (200) only for the approved read-only hosts in proxy/readonly-allowlist.txt
#   (cdn.builder.io), probed only when that file exists and lists them (PR #6 may or may not be merged).
# HTTPS clients use CONNECT host:443, so that is what is probed (plus one plain-HTTP GET).
# No host is ever ADDED anywhere by this script; it only asks the proxy. Exit 1 on any unexpected answer.
. "$(dirname "$0")/lib.sh"
EGRESS_SVC="${EGRESS_SVC:-tf-api}"
DENY_PROBES=(
  "GET a.klaviyo.com"
  "CONNECT a.klaviyo.com" "CONNECT klaviyo.com"
  "CONNECT trulyfreehome.com" "CONNECT www.trulyfreehome.com" "CONNECT api.trulyfreehome.com" "CONNECT mygreenfills.com"
  "CONNECT sticky.io" "CONNECT api.sticky.io" "CONNECT limelightcrm.com" "CONNECT www.limelightcrm.com"
  "CONNECT api.mailgun.net"
  "CONNECT avalara.com" "CONNECT rest.avatax.com"
  "CONNECT tfhcore.trulyfreehome.com"
  "CONNECT builder.io" "CONNECT www.builder.io" "CONNECT api.builder.io"
)
ALLOW_PROBES=()
RO="$ROOT/proxy/readonly-allowlist.txt"
if [ -f "$RO" ] && patterns "$RO" | grep -qxF '^cdn\.builder\.io$'; then ALLOW_PROBES+=("CONNECT cdn.builder.io"); fi

# Runs inside the container (bash /dev/tcp; no curl needed). Reads "METHOD host" lines, prints "METHOD host code".
PROBE='while read -r m h; do
  if ! exec 3<>/dev/tcp/proxy/8888; then echo "$m $h noproxy"; continue; fi
  if [ "$m" = CONNECT ]; then printf "CONNECT %s:443 HTTP/1.1\r\nHost: %s:443\r\n\r\n" "$h" "$h" >&3
  else printf "GET http://%s/ HTTP/1.0\r\nHost: %s\r\n\r\n" "$h" "$h" >&3; fi
  line=""; read -r -t 20 line <&3 || true; exec 3>&- 3<&-
  set -- $line; echo "$m $h ${2:-none}"
done'
answers="$( { for p in "${DENY_PROBES[@]}" "${ALLOW_PROBES[@]}"; do echo "$p"; done; } \
  | dc exec -T "$EGRESS_SVC" bash -c "$PROBE" 2>/dev/null || true)"
fail=0
check() { # check <expected-code> <method host>
  local got; got="$(printf '%s\n' "$answers" | awk -v p="$2" '$1" "$2==p {print $3; exit}')"
  if [ "$got" = "$1" ]; then echo "ok: egress $2 -> $got"; else red "egress $2: expected $1, got '${got:-no answer}'"; fail=1; fi
}
for p in "${DENY_PROBES[@]}"; do check 403 "$p"; done
if [ ${#ALLOW_PROBES[@]} -eq 0 ]; then
  ylw "egress: no read-only allow-list (proxy/readonly-allowlist.txt absent/empty); allow probe skipped"
else
  for p in "${ALLOW_PROBES[@]}"; do check 200 "$p"; done
fi
[ $fail -eq 0 ] && grn "egress: OK (${#DENY_PROBES[@]} denied, ${#ALLOW_PROBES[@]} read-only allowed)" || { red "egress: FAILED"; exit 1; }
