#!/usr/bin/env bash
# docker/next-app-start.sh: mode switch and build lock (no docker; fake npx/node on PATH).
. "$(dirname "$0")/lib.sh"
D="$(mktemp -d "${TMPDIR:-/tmp}/tfh-nas.XXXXXX")"; mkdir -p "$D/bin" "$D/app"
cat > "$D/bin/npx" <<'S'
#!/bin/sh
echo "npx $* NODE_ENV=${NODE_ENV:-} FONT=${NEXT_FONT_GOOGLE_MOCKED_RESPONSES:+set}" >> "$CALLS"
[ "$2" = build ] && mkdir -p .next && echo id > .next/BUILD_ID
exit 0
S
chmod +x "$D/bin/npx"
run() { (cd "$D/app" && CALLS="$D/calls" PATH="$D/bin:$PATH" LOCAL_APP_MODE="$1" sh "$T_ROOT/docker/next-app-start.sh" >/dev/null 2>&1); }
run bogus; expect_true "unknown mode exits 2" [ $? -eq 2 ]
: > "$D/calls"; run dev; expect_true "dev -> next dev" grep -q '^npx next dev' "$D/calls"
: > "$D/calls"; run prod
expect_true "prod builds with NODE_ENV=production" grep -q '^npx next build --no-lint NODE_ENV=production' "$D/calls"
expect_true "prod then next start" grep -q '^npx next start' "$D/calls"
: > "$D/calls"; run prod
expect_false "restart reuses .next (no rebuild)" grep -q 'next build' "$D/calls"
rm -rf "$D"; done_tests
