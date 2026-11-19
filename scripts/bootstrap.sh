#!/usr/bin/env bash
# Put app repos into ./apps/<name>/ (never committed). Idempotent: present checkouts are left alone.
# Default: fresh clone from repos.yaml. LOCAL_SRC=~/projects: add a git worktree from your existing clone
# (~/projects/<name>, or ~/projects/tf-regression for tfh-automation) on branch tfh-local/<default_branch>.
# Your own working tree in ~/projects/<name> is never touched (only `git fetch` + worktree metadata).
# REFRESH=1 (or `make refresh`): fetch each repo and fast-forward apps/<name> if it is clean and on
# tfh-local/<default_branch>; anything else (dirty, ticket branch, diverged) is skipped with a note.
. "$(dirname "$0")/lib.sh"
load_env
mkdir -p "$APPS" "$STATE"
src="${LOCAL_SRC:-}"; src="${src/#\~/$HOME}"

refresh_one() { # refresh_one <dest> <default_branch>
  local dest="$1" def="$2" br
  git -C "$dest" fetch --quiet origin "$def" || { ylw "  fetch failed; skipped"; return 0; }
  br="$(git -C "$dest" rev-parse --abbrev-ref HEAD)"
  if [ "$br" != "tfh-local/$def" ] && [ "$br" != "$def" ]; then ylw "  on '$br' (not tfh-local/$def); not fast-forwarded"; return 0; fi
  if is_dirty "$dest"; then ylw "  dirty; not fast-forwarded"; return 0; fi
  git -C "$dest" merge --ff-only --quiet "origin/$def" 2>/dev/null \
    && echo "  now at $(git -C "$dest" log --oneline -1)" || ylw "  cannot fast-forward (diverged); left as is"
}

while read -r name url def base role; do
  dest="$APPS/$name"
  if [ -e "$dest" ]; then
    if [ "${REFRESH:-}" = "1" ]; then echo "~ $name: refresh"; refresh_one "$dest" "$def"; else echo "= $name already present"; fi
    continue
  fi
  if [ -n "$src" ]; then
    cand="$src/$name"; [ "$name" = "tfh-automation" ] && [ ! -d "$cand" ] && cand="$src/tf-regression"
    if [ -d "$cand/.git" ]; then
      echo "+ $name: worktree from $cand ($def)"
      git -C "$cand" fetch origin "$def"
      git -C "$cand" worktree prune   # forget worktrees whose apps/ dir was deleted
      if git -C "$cand" show-ref --verify --quiet "refs/heads/tfh-local/$def"; then
        # Reuse the existing local branch (it may carry tfh-local commits); never reset it.
        git -C "$cand" worktree add "$dest" "tfh-local/$def"
      else
        git -C "$cand" worktree add -b "tfh-local/$def" "$dest" "origin/$def"
        git -C "$dest" branch --set-upstream-to "origin/$def" >/dev/null
      fi
      continue
    fi
    ylw "  $name: no clone at $cand; falling back to fresh clone"
  fi
  echo "+ $name: clone $url ($def)"
  git clone --branch "$def" "$url" "$dest"
done < <(repos)
[ -f "$ROOT/.env" ] || { cp "$ROOT/.env.example" "$ROOT/.env"; ylw "created .env from .env.example; fill in local values (EXTERNALS=offline by default)"; }
grn "bootstrap: done"
