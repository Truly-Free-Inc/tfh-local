#!/usr/bin/env bash
# Fix (b): scripts/pr.sh pushes only through safe_push, which refuses main/master/develop/stage/PR-base.
# Uses a throwaway local bare repo as "origin" (no network).
. "$(dirname "$0")/lib.sh"
. "$T_ROOT/scripts/lib.sh"; set +e
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tfh-local-prtest.XXXXXX")"
git init -q --bare "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$TMP/w" 2>/dev/null
g() { git -C "$TMP/w" -c user.email=t@tfh-local.test -c user.name=t "$@"; }
g checkout -q -b main; g commit -q --allow-empty -m init; g push -q origin main
remote_has() { git -C "$TMP/origin.git" show-ref --verify --quiet "refs/heads/$1"; }

for br in main master develop stage; do
  g checkout -q -B "$br"; g commit -q --allow-empty -m "on $br"
  before="$(git -C "$TMP/origin.git" rev-parse "refs/heads/$br" 2>/dev/null || echo none)"
  expect_false "refuses push of '$br'" safe_push "$TMP/w" "$br" develop
  after="$(git -C "$TMP/origin.git" rev-parse "refs/heads/$br" 2>/dev/null || echo none)"
  expect_true "origin/$br unchanged" [ "$before" = "$after" ]
done
g checkout -q -B release/2026-11 main; g commit -q --allow-empty -m rel
expect_false "refuses push when branch == PR base (release/2026-11)" safe_push "$TMP/w" release/2026-11 release/2026-11
expect_false "refuses push of a branch that is not checked out" safe_push "$TMP/w" main develop
g checkout -q -B TFHFUNNEL-12-fix main; g commit -q --allow-empty -m fix
expect_false "refuses odd ref syntax" safe_push "$TMP/w" "TFHFUNNEL-12-fix:main" develop
expect_true  "pushes a ticket branch" safe_push "$TMP/w" TFHFUNNEL-12-fix develop
expect_true  "ticket branch landed on origin" remote_has TFHFUNNEL-12-fix
expect_true  "origin/main still at init" [ "$(git -C "$TMP/origin.git" log --format=%s -1 main)" = init ]
expect_true  "pr.sh has no raw git push" bash -c "! grep -nE 'git .*push' '$T_ROOT/scripts/pr.sh'"
rm -rf "$TMP"
done_tests
