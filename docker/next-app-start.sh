#!/bin/sh
# tfh-local Next.js app start (bind-mounted read-only; see docker-compose.yml `command`).
# LOCAL_APP_MODE=prod (default): `next build` once per container (NEXT_PUBLIC_* come from the compose environment, so
#   the build must happen at start, not in the image), then `next start`. A production server holds only the built
#   routes: no per-route webpack compile, no dev-server memory growth / "approaching the used memory threshold" restarts.
#   A restart of the same container reuses .next (BUILD_ID present); `docker compose up --force-recreate` rebuilds.
# LOCAL_APP_MODE=dev: `next dev` as before (hot reload; slow cold compiles, memory grows per compiled route).
set -eu
MODE="${LOCAL_APP_MODE:-prod}"
case "$MODE" in
  dev)
    exec npx next dev -H 0.0.0.0 -p 3000 ;;
  prod)
    export NODE_ENV=production
    if [ ! -f .next/BUILD_ID ]; then
      # One build at a time across the apps (shared /build-lock volume): three parallel `next build`s are the
      # memory peak of the whole stack. mkdir is atomic; a lock older than 20 min is treated as stale.
      LOCK=/build-lock/next-build.lock
      if [ -d /build-lock ]; then
        while ! mkdir "$LOCK" 2>/dev/null; do
          if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +20 2>/dev/null)" ]; then rmdir "$LOCK" 2>/dev/null || true; continue; fi
          echo "tfh-local: waiting for another app's next build to finish"; sleep 10
        done
        trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT INT TERM
      fi
      # next/font/google: no network at build time (the proxy blocks Google Fonts); answer from a local-font stub.
      [ -f /opt/tfh-local/next-font-offline.cjs ] && export NEXT_FONT_GOOGLE_MOCKED_RESPONSES=/opt/tfh-local/next-font-offline.cjs
      echo "tfh-local: LOCAL_APP_MODE=prod -> next build (first start of this container; takes a few minutes)"
      # The build may use more heap than the running server; NEXT_BUILD_NODE_OPTIONS overrides NODE_OPTIONS for it.
      NODE_OPTIONS="${NEXT_BUILD_NODE_OPTIONS:-${NODE_OPTIONS:-}}" npx next build --no-lint   # lint is CI's job; saves minutes
      echo "tfh-local: next build done"
      [ -d /build-lock ] && { rmdir "$LOCK" 2>/dev/null || true; trap - EXIT INT TERM; }
    fi
    if [ -f .next/standalone/server.js ]; then
      # `output: "standalone"` apps (funnels): `next start` is unsupported; run the standalone server like the
      # deployed image does, with its static assets and public/ copied next to it.
      # Merge (not copy-if-missing): the build may pre-create standalone/.next/static with only some assets.
      mkdir -p .next/standalone/.next/static
      cp -R .next/static/. .next/standalone/.next/static/
      if [ -d public ]; then mkdir -p .next/standalone/public && cp -R public/. .next/standalone/public/; fi
      cd .next/standalone
      HOSTNAME=0.0.0.0 PORT=3000 exec node server.js
    fi
    exec npx next start -H 0.0.0.0 -p 3000 ;;
  *)
    echo "tfh-local: LOCAL_APP_MODE must be prod or dev (got '$MODE')" >&2; exit 2 ;;
esac
