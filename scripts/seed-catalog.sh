#!/usr/bin/env bash
# make seed-catalog [CATALOG_MODE=replace|upsert] [CATALOG_DIR=.state/catalog-export]
# Loads an allow-listed CATALOG export (definition tables only: products, offers, placements, coupons, flows,
# sitemap entries...; never customers/orders/subscriptions/feature_flags) into the LOCAL tf-api Postgres container.
# The data (CATALOG_DIR/data/<table>.json) is NOT in git: it lives under the gitignored .state/ and is produced
# out-of-band (see seed/catalog/README.md). This script only ever talks to the local compose postgres container.
. "$(dirname "$0")/lib.sh"
load_env
"$ROOT/scripts/preflight.sh"
DIR="${CATALOG_DIR:-$STATE/catalog-export}"
MODE="${CATALOG_MODE:-replace}"
case "$MODE" in replace|upsert) ;; *) die "CATALOG_MODE must be replace|upsert";; esac
[ -d "$DIR/data" ] || die "no catalog export at $DIR/data (gitignored; see seed/catalog/README.md)"
git -C "$ROOT" check-ignore -q "$DIR/data" || die "$DIR/data is not gitignored; refusing (catalog data must never be committed)"
# Customer/order DATA scan (every column, every value, nested JSON): writes a cleaned copy; only that copy is loaded.
CLEAN="$STATE/catalog-clean"
rm -rf "$CLEAN"
python3 -I "$ROOT/seed/catalog/pii_scan.py" "$DIR/data" "$CLEAN" || die "customer/order data scan failed; nothing loaded"
git -C "$ROOT" check-ignore -q "$CLEAN/data" || die "$CLEAN/data is not gitignored; refusing"
CID="$(cd "$ROOT" && docker compose ps -q postgres)"
[ -n "$CID" ] || die "local postgres container not running (make up)"
DB="${APP_DB_NAME:-tf_api_local}"
TMP=/tmp/tfh-catalog-load
docker exec "$CID" rm -rf "$TMP"
docker exec "$CID" mkdir -p "$TMP"
docker cp "$CLEAN/data" "$CID:$TMP/data" >/dev/null
docker cp "$ROOT/seed/catalog/load.sql" "$CID:$TMP/load.sql" >/dev/null
set +e
docker exec -w "$TMP" "$CID" sh -c 'psql -U "$POSTGRES_USER" -d "$1" -v ON_ERROR_STOP=1 -v mode="$2" -q -f load.sql' _ "$DB" "$MODE"
rc=$?
set -e
docker exec "$CID" rm -rf "$TMP"
[ $rc -eq 0 ] || die "catalog load failed (rc=$rc); the whole load was rolled back"
grn "catalog loaded into local $DB (mode=$MODE). feature_flags untouched."
