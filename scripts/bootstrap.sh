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
[ -f "$ROOT/.env" ] || { cp "$ROOT/.env.example" "$ROOT/.env"; chmod 600 "$ROOT/.env"; ylw "created .env from .env.example; fill in local values (EXTERNALS=offline by default)"; }

# Credentials have NO defaults in docker-compose.yml (${VAR:?}). Fill any missing/empty one in .env with a freshly
# generated local value. Never prints values. Existing non-empty values are never changed.
# If this stack already has data volumes (initialized with whatever credentials were in effect then), DB/MinIO
# credentials are NOT generated: a new password would not match the initialized volume. Set those by hand (to the
# values the volume was created with) or `make reset CONFIRM=1` first.
env_get() { grep -E "^$1=" "$ROOT/.env" | tail -1 | cut -d= -f2- || true; }
env_set() { # env_set NAME VALUE: replace NAME= line(s) or append. The value reaches awk via its environment, not argv.
  local k="$1" tmp; tmp="$(mktemp "$ROOT/.env.XXXXXX")"
  ENV_SET_V="$2" awk -v k="$k" 'BEGIN{d=0; v=ENVIRON["ENV_SET_V"]} $0 ~ "^"k"=" { if(!d){print k"="v; d=1}; next } {print} END{ if(!d) print k"="v }' "$ROOT/.env" > "$tmp"
  chmod 600 "$tmp"; mv "$tmp" "$ROOT/.env"
}
rnd() { openssl rand -hex "$1"; }
proj="${COMPOSE_PROJECT_NAME:-$(basename "$ROOT" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')}"
has_volumes=0
if command -v docker >/dev/null 2>&1 && [ -n "$(docker volume ls -q --filter "label=com.docker.compose.project=$proj" 2>/dev/null)" ]; then
  has_volumes=1
fi
gen=(); skipped=()
fill() { # fill NAME VOLUME_BOUND(0|1) GENERATOR...
  local k="$1" bound="$2"; shift 2
  [ -n "$(env_get "$k")" ] && return 0
  if [ "$bound" = 1 ] && [ "$has_volumes" = 1 ]; then skipped+=("$k"); return 0; fi
  env_set "$k" "$("$@")"; gen+=("$k")
}
lit() { printf '%s' "$1"; }
fill POSTGRES_USER          1 lit tfh_local_admin
fill POSTGRES_PASSWORD      1 rnd 24
fill APP_DB_USER            1 lit tf_api_local
fill APP_DB_PASS            1 rnd 24
fill MINIO_ROOT_USER        1 lit tfh-local-minio
fill MINIO_ROOT_PASSWORD    1 rnd 24
fill GATEWAY_DB_USER        1 lit tfh_gateway_local
fill GATEWAY_DB_PASSWORD    1 rnd 24
fill KRATOS_SECRETS_COOKIE  0 rnd 32
fill KRATOS_SECRETS_CIPHER  0 rnd 16   # 32 hex chars (Kratos needs exactly 32)
fill TEST_CUSTOMER_PORTAL_EMAIL    0 lit test@tfh-local.test
fill TEST_CUSTOMER_PORTAL_PASSWORD 0 rnd 16
fill LOCAL_ADMIN_EMAIL             0 lit admin@tfh-local.test
fill LOCAL_ADMIN_PASSWORD          0 rnd 16
# tf-api HTTP Basic auth (BASIC_AUTH_ENABLED=true locally): server-to-server creds for memberportal/admin/funnels and
# the suite's local env. Local-only generated values, not any real environment's.
fill TF_API_BASIC_AUTH_USERNAME    0 lit tfh-local-api
fill TF_API_BASIC_AUTH_PASSWORD    0 rnd 24
[ ${#gen[@]} -eq 0 ] || ylw "generated local values in .env for: ${gen[*]} (values not shown)"
[ ${#skipped[@]} -eq 0 ] || ylw "NOT generated (data volumes for '$proj' exist; set them to the values the volumes were created with, or make reset CONFIRM=1): ${skipped[*]}"
grn "bootstrap: done"
