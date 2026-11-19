#!/usr/bin/env bash
# make ticket KEY=TFHFUNNEL-1234 [BRANCH=...]
# Per repo: fetch; check out the remote branch for the ticket if one exists (exact KEY, or a branch name that
# contains KEY, e.g. feature/TFHFUNNEL-1234-x), else stay on the default branch (fast-forward pulled).
# tfh-automation: create branch BRANCH (default: KEY) from origin/main if missing.
# Refuses if any repo is dirty. Writes .state/ticket.json.
. "$(dirname "$0")/lib.sh"
require_key
BRANCH="${BRANCH:-}"
mkdir -p "$STATE"

# Refuse on any dirty repo BEFORE touching anything.
dirty=0
while read -r name url def base role; do
  d="$APPS/$name"; [ -e "$d/.git" ] || die "$name missing in apps/. Run: make bootstrap"
  if is_dirty "$d"; then red "dirty: apps/$name"; dirty=1; fi
done < <(repos)
[ $dirty -eq 0 ] || die "commit or stash changes first (refusing to switch branches on a dirty repo)"

checkout_default() { # dir def
  local d="$1" def="$2"
  if git -C "$d" checkout -q "$def" 2>/dev/null || git -C "$d" checkout -q -b "$def" --track "origin/$def" 2>/dev/null; then
    git -C "$d" merge -q --ff-only "origin/$def" || die "$d: local $def has diverged from origin/$def"
  else # worktree mode (default branch checked out in the source clone)
    git -C "$d" checkout -q -B "tfh-local/$def" "origin/$def"
  fi
}

checkout_remote() { # dir branch
  local d="$1" b="$2"
  if git -C "$d" show-ref -q --verify "refs/heads/$b"; then
    git -C "$d" checkout -q "$b" && git -C "$d" merge -q --ff-only "origin/$b" || die "$d: local $b diverged from origin/$b"
  else
    git -C "$d" checkout -q -b "$b" --track "origin/$b"
  fi
}

while read -r name url def base role; do
  d="$APPS/$name"
  git -C "$d" fetch -q --prune origin
  remote_heads="$(git -C "$d" for-each-ref --format='%(refname:strip=3)' "refs/remotes/origin/" | grep -v '^HEAD$' || true)"
  if [ "$role" = "tests" ]; then
    b="${BRANCH:-$KEY}"
    if printf '%s\n' "$remote_heads" | grep -qxF "$b"; then checkout_remote "$d" "$b"
    elif git -C "$d" show-ref -q --verify "refs/heads/$b"; then git -C "$d" checkout -q "$b"
    else git -C "$d" checkout -q -b "$b" "origin/$def"; echo "  $name: created $b from origin/$def"; fi
  else
    match=""
    if [ -n "$BRANCH" ] && printf '%s\n' "$remote_heads" | grep -qxF "$BRANCH"; then match="$BRANCH"
    elif printf '%s\n' "$remote_heads" | grep -qxF "$KEY"; then match="$KEY"
    else
      cands="$(printf '%s\n' "$remote_heads" | grep -F "$KEY" || true)"
      n="$(printf '%s' "$cands" | grep -c . || true)"
      [ "$n" -gt 1 ] && die "$name: several remote branches contain $KEY; pass BRANCH=...:"$'\n'"$cands"
      match="$cands"
    fi
    if [ -n "$match" ]; then checkout_remote "$d" "$match"; else checkout_default "$d" "$def"; fi
  fi
  printf '  %-30s %s @ %s\n' "$name" "$(git -C "$d" rev-parse --abbrev-ref HEAD)" "$(git -C "$d" rev-parse --short HEAD)"
done < <(repos)

printf '{"key":"%s","timestamp":"%s","repos":%s}\n' "$KEY" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(repo_shas_json)" > "$STATE/ticket.json"
grn "ticket $KEY ready. State: .state/ticket.json"
