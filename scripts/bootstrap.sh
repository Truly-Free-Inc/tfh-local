#!/usr/bin/env bash
# Clone missing app repos into ./apps/<name>/ (never committed).
# Default: fresh clone from repos.yaml. LOCAL_SRC=~/projects: add a git worktree from your existing clone
# (~/projects/<name>, or ~/projects/tf-regression for tfh-automation) on the repo's default branch.
. "$(dirname "$0")/lib.sh"
load_env
mkdir -p "$APPS" "$STATE"
src="${LOCAL_SRC:-}"; src="${src/#\~/$HOME}"
while read -r name url def base role; do
  dest="$APPS/$name"
  if [ -e "$dest" ]; then echo "= $name already present"; continue; fi
  if [ -n "$src" ]; then
    cand="$src/$name"; [ "$name" = "tfh-automation" ] && [ ! -d "$cand" ] && cand="$src/tf-regression"
    if [ -d "$cand/.git" ]; then
      echo "+ $name: worktree from $cand ($def)"
      git -C "$cand" fetch origin "$def"
      git -C "$cand" worktree add --detach "$dest" "origin/$def"
      git -C "$dest" checkout -B "tfh-local/$def" "origin/$def"
      continue
    fi
    ylw "  $name: no clone at $cand; falling back to fresh clone"
  fi
  echo "+ $name: clone $url ($def)"
  git clone --branch "$def" "$url" "$dest"
done < <(repos)
[ -f "$ROOT/.env" ] || { cp "$ROOT/.env.example" "$ROOT/.env"; ylw "created .env from .env.example; fill in NON-PROD values"; }
grn "bootstrap: done"
