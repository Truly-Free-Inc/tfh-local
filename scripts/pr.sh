#!/usr/bin/env bash
# make pr KEY=TFHFUNNEL-1234 [CONFIRM=1]
# Default: DRY RUN (prints the plan). CONFIRM=1: push ticket branches and open PRs.
# Requires the last `make verify KEY=...` to be GREEN on exactly the current SHAs.
# PR base = repos.yaml pr_base (develop; main where no develop). GitHub: gh pr create. Bitbucket: prints the
# create-PR URL + body file (no Bitbucket CLI assumed).
# This script opens PRs ONLY. It never lands, approves or closes them; humans/review automation do that.
. "$(dirname "$0")/lib.sh"
require_key
CONFIRM="${CONFIRM:-0}"
last="$STATE/runs/last-$KEY.json"
[ -f "$last" ] || die "no verify result for $KEY. Run: make verify KEY=$KEY"
grep -q '"status":"green"' "$last" || die "last verify for $KEY is RED. Fix and re-run make verify."
now="$(repo_shas_json)"
verified="$(sed -E 's/.*"repos":(\{.*\})\}$/\1/' "$last")"
[ "$now" = "$verified" ] || die "repos changed since the last green verify (SHAs differ). Re-run: make verify KEY=$KEY"
run_dir="$( (ls -1d "$STATE/runs/$KEY"-* 2>/dev/null || true) | (grep -v -- '-pr$' || true) | tail -1)"
PRDIR="$STATE/runs/$KEY-pr"; mkdir -p "$PRDIR"

[ "$CONFIRM" = "1" ] && ylw "CONFIRM=1: pushing branches and opening PRs" || ylw "DRY RUN (add CONFIRM=1 to execute)"
planned=0
while read -r name url def base role; do
  d="$APPS/$name"; [ -e "$d/.git" ] || continue
  b="$(git -C "$d" rev-parse --abbrev-ref HEAD)"
  case "$b" in "$def"|"tfh-local/$def"|HEAD) continue ;; esac
  case " $PROTECTED_BRANCHES $base " in *" $b "*) ylw "  $name: on protected branch '$b'; never pushed; skip"; continue ;; esac
  git -C "$d" fetch -q origin "$base"
  ahead="$(git -C "$d" rev-list --count "origin/$base..HEAD")"
  [ "$ahead" -gt 0 ] || { echo "  $name: $b has no commits ahead of $base; skip"; continue; }
  is_dirty "$d" && die "$name is dirty; commit first"
  body="$PRDIR/$name.md"
  {
    echo "## $KEY"
    echo
    echo "Branch \`$b\` -> \`$base\` ($ahead commit(s))."
    echo
    echo "### Local verification (tfh-local)"
    [ -n "$run_dir" ] && [ -f "$run_dir/summary.md" ] && cat "$run_dir/summary.md" || echo "(summary not found)"
    echo
    echo "Opened by an AI via tfh-local \`make pr\`. Needs human review. * posted by AI bot"
  } > "$body"
  planned=1
  echo "  $name: push $b; PR $b -> $base (body: $body)"
  [ "$CONFIRM" = "1" ] || continue
  safe_push "$d" "$b" "$base" || die "$name: push refused (see above)"
  case "$url" in
    *github.com*)
      if (cd "$d" && gh pr view "$b" --json url -q .url >/dev/null 2>&1); then
        echo "    PR already open: $(cd "$d" && gh pr view "$b" --json url -q .url)"
      else
        (cd "$d" && gh pr create --base "$base" --head "$b" --title "$KEY: $(git log -1 --format=%s)" --body-file "$body")
      fi ;;
    *bitbucket.org*)
      slug="$(printf '%s' "$url" | sed -E 's#^.*bitbucket.org[:/]##; s#\.git$##')"
      echo "    Bitbucket: open https://bitbucket.org/$slug/pull-requests/new?source=$b&dest=$base"
      echo "    PR body: $body" ;;
    *) ylw "    unknown host for $url; push done, open the PR by hand" ;;
  esac
done < <(repos)
[ $planned -eq 1 ] || ylw "nothing to PR (no repo on a ticket branch with commits ahead)"
