#!/usr/bin/env bash
# Shared helpers for tfh-local scripts. Source it: `. "$(dirname "$0")/lib.sh"`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS="$ROOT/apps"
STATE="$ROOT/.state"
KEY_RE='^[A-Z][A-Z0-9]+-[0-9]+$'

red()  { printf '\033[1;31m%s\033[0m\n' "$*" >&2; }
grn()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
ylw()  { printf '\033[1;33m%s\033[0m\n' "$*" >&2; }
die()  { red "ERROR: $*"; exit 1; }

# Read .env as data (no eval / no command execution). Exports KEY=VALUE lines; strips matching quotes.
load_env() {
  local f="$ROOT/.env" line k v
  [ -f "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    k="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    export "$k=$v"
  done < "$f"
}

# Print "name url default_branch pr_base role" per repo from repos.yaml.
repos() {
  awk '
    /^[[:space:]]*- name:/ { if (n) print n, u, d, p, r; n=$3; u=d=p=r="" }
    /^[[:space:]]*url:/            { u=$2 }
    /^[[:space:]]*default_branch:/ { d=$2 }
    /^[[:space:]]*pr_base:/        { p=$2 }
    /^[[:space:]]*role:/           { r=$2 }
    END { if (n) print n, u, d, p, r }
  ' "$ROOT/repos.yaml"
}

require_key() {
  [ -n "${KEY:-}" ] || die "KEY is required (e.g. KEY=TFHFUNNEL-1234)"
  [[ "$KEY" =~ $KEY_RE ]] || die "KEY '$KEY' is not a Jira key like TFHFUNNEL-1234"
}

# safe_push <repo_dir> <branch> <pr_base>: push <branch> to origin/<branch> (explicit refspec, no force), but
# REFUSE when the current branch or the target ref is main, master, develop, stage or the PR base branch.
# Protected-branch pushes are how an AI "lands" work without review; this makes that impossible from tfh-local.
PROTECTED_BRANCHES="main master develop stage"
safe_push() {
  local d="$1" b="$2" base="$3" cur p
  cur="$(git -C "$d" rev-parse --abbrev-ref HEAD)"
  [ -n "$b" ] && [ -n "$base" ] || { red "safe_push: branch and base are required"; return 1; }
  [ "$cur" = "$b" ] || { red "REFUSED: $d is on '$cur', not '$b'"; return 1; }
  for p in $PROTECTED_BRANCHES "$base" HEAD; do
    if [ "$b" = "$p" ] || [ "$cur" = "$p" ]; then
      red "REFUSED: will not push protected branch '$b' (current '$cur', PR base '$base') in $d"; return 1
    fi
  done
  case "$b" in refs/*|*:*|+*|-*) red "REFUSED: unexpected ref syntax '$b'"; return 1 ;; esac
  git -C "$d" push -u origin "refs/heads/$b:refs/heads/$b"
}

# key_grep <KEY>: Playwright --grep (JS RegExp) matching the tag @KEY as a whole ticket key, so @TFHFUNNEL-12
# does not also select @TFHFUNNEL-123. Left side is fixed by the '@'; right side must not continue with a digit.
key_grep() { [[ "$1" =~ $KEY_RE ]] || return 1; printf '@%s(?![0-9])' "$1"; }

is_dirty() { [ -n "$(git -C "$1" status --porcelain)" ]; }

# Host part of a URL or bare host: strip scheme, path, port, userinfo; lowercase.
host_of() {
  local h="$1"; h="${h#*://}"; h="${h%%/*}"; h="${h##*@}"; h="${h%%:*}"
  printf '%s' "$h" | tr '[:upper:]' '[:lower:]'
}

# Non-comment, non-empty lines of a pattern file.
patterns() { grep -vE '^[[:space:]]*(#|$)' "$1" || true; }

# pattern_anchored <ERE>: true if the host pattern is ^...$ anchored and every literal dot is escaped.
# Allowed unescaped dots: inside a bracket expression ([.-]) or as a wildcard (.* / .+). Anything else
# (e.g. "klaviyo.com$", "^cdn.builder.io$") is refused: an unanchored/unescaped pattern can match far more
# (or far less) than the author meant, which is exactly how deny lists leak.
pattern_anchored() {
  local p="$1" s
  [[ "$p" == ^* && "$p" == *\$ ]] || return 1
  s="$(printf '%s' "$p" | sed -E 's/\[[^]]*\]//g; s/\\\.//g; s/\.[*+]//g')"
  case "$s" in *.*) return 1 ;; esac
  return 0
}

dc() { docker compose --project-directory "$ROOT" -f "$ROOT/docker-compose.yml" "$@"; }

# Docker Desktop's credential helper (credsStore "desktop") blocks forever when the macOS login keychain is locked
# (screen lock), which hangs every build/pull of a base image (all public Docker Hub images here). If the helper
# does not answer within 10 s, use an anonymous DOCKER_CONFIG for this run: same daemon (DOCKER_HOST from the current
# context), same CLI plugins, no credential store. Public images only; nothing is written to ~/.docker.
docker_creds_guard() {
  local cfg helper host
  cfg="$(sed -n 's/.*"credsStore"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${DOCKER_CONFIG:-$HOME/.docker}/config.json" 2>/dev/null || true)"
  [ -n "$cfg" ] || return 0
  helper="docker-credential-$cfg"
  command -v "$helper" >/dev/null 2>&1 || return 0
  # A helper stuck on the keychain ignores SIGALRM/SIGTERM, so time-box it with SIGKILL.
  local pid i
  "$helper" list >/dev/null 2>&1 & pid=$!
  for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  if ! kill -0 "$pid" 2>/dev/null; then wait "$pid" && return 0; fi
  kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  host="$(docker context inspect -f '{{.Endpoints.docker.Host}}' 2>/dev/null)" || return 0
  [ -n "$host" ] || return 0
  mkdir -p "$STATE/docker-anon"
  printf '{\n  "auths": {}\n}\n' > "$STATE/docker-anon/config.json"
  [ -e "$STATE/docker-anon/cli-plugins" ] || ln -s "${DOCKER_CONFIG:-$HOME/.docker}/cli-plugins" "$STATE/docker-anon/cli-plugins"
  export DOCKER_CONFIG="$STATE/docker-anon" DOCKER_HOST="$host"
  ylw "docker: credential helper '$helper' did not answer in 10 s (keychain locked?); using anonymous Docker Hub pulls for this run (DOCKER_CONFIG=.state/docker-anon)"
}

# Current branch -> sha map of all checked-out repos, as JSON object lines.
repo_shas_json() {
  local first=1 name url def base role dir
  printf '{'
  while read -r name url def base role; do
    dir="$APPS/$name"; [ -d "$dir/.git" ] || [ -f "$dir/.git" ] || continue
    [ $first -eq 1 ] || printf ','; first=0
    printf '"%s":{"branch":"%s","sha":"%s"}' "$name" \
      "$(git -C "$dir" rev-parse --abbrev-ref HEAD)" "$(git -C "$dir" rev-parse HEAD)"
  done < <(repos)
  printf '}'
}
