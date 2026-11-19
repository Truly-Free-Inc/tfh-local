#!/usr/bin/env bash
# make status: current ticket, branch map + dirty flags, last verify result, containers.
. "$(dirname "$0")/lib.sh"
echo "== ticket"; [ -f "$STATE/ticket.json" ] && cat "$STATE/ticket.json" || echo "(none; run make ticket KEY=...)"
echo "== repos"
while read -r name url def base role; do
  d="$APPS/$name"
  if [ -e "$d/.git" ]; then
    printf '  %-30s %-40s %s %s\n' "$name" "$(git -C "$d" rev-parse --abbrev-ref HEAD)" "$(git -C "$d" rev-parse --short HEAD)" "$(is_dirty "$d" && echo DIRTY || echo clean)"
  else printf '  %-30s (missing; make bootstrap)\n' "$name"; fi
done < <(repos)
echo "== last verify"
key="$(sed -nE 's/.*"key":"([^"]+)".*/\1/p' "$STATE/ticket.json" 2>/dev/null || true)"
if [ -n "$key" ] && [ -f "$STATE/runs/last-$key.json" ]; then cat "$STATE/runs/last-$key.json"; else echo "(none)"; fi
echo "== containers"; dc ps 2>/dev/null || echo "(docker not reachable)"
