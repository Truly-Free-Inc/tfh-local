#!/usr/bin/env bash
# make up: SAFETY preflight, then build + start the core stack from apps/ checkouts.
. "$(dirname "$0")/lib.sh"
[ -d "$APPS/tf-api/src" ] || die "apps/tf-api missing. Run: make bootstrap"
"$ROOT/scripts/preflight.sh"
dc up -d --build
dc ps
