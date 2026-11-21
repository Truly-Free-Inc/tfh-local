#!/usr/bin/env bash
# make map-tf-products: point the LOCAL catalog's tf_products rows at TF DEV product ids (EXTERNALS=real only).
#
# The catalog export (gitignored) carries PROD TF product ids; tfh-local talks to the TF DEV Composition API
# (api.dev.trulyfree.com, what develop/stage use), so TF dev answered POST /v1/tax/estimate with 400 "Product not
# found for tfProductId ..." and checkout totals fell back. develop/stage get TF dev ids from their own product sync
# (tf-api cron sync-products-to-tf, which CREATES products on TF dev); tfh-local never runs crons or writes to TF.
# Instead this READS TF dev's product list (GET only, through the egress proxy) and matches by SKU
# (seed/tf-products/match.py), then updates only the local Postgres. Idempotent; also run by `make seed-catalog`.
# Products with no TF dev SKU match are left NOT_SYNCED (tf-api then reports TF_PRODUCT_NOT_SYNCED and falls back).
# No ids, SKUs or names are printed or committed: the fetched list and the mapping stay under the gitignored .state/.
. "$(dirname "$0")/lib.sh"
load_env
EXTERNALS="$(printf '%s' "${EXTERNALS:-offline}" | tr '[:upper:]' '[:lower:]')"
if [ "$EXTERNALS" != "real" ]; then
  ylw "map-tf-products: EXTERNALS=$EXTERNALS, TF is offline; nothing to map (skipped)"; exit 0
fi
[ "$(host_of "${TF_COMPOSITION_API_BASE_URL:-}")" = "api.dev.trulyfree.com" ] \
  || die "map-tf-products: TF_COMPOSITION_API_BASE_URL must be the TF dev host api.dev.trulyfree.com"
[ -n "${TF_COMPOSITION_API_TOKEN:-}" ] || die "map-tf-products: TF_COMPOSITION_API_TOKEN is not set in .env"
OUT="$STATE/tf-products"
mkdir -p "$OUT"
git -C "$ROOT" check-ignore -q "$OUT/x" || die "$OUT is not gitignored; refusing"
# A running Node container on the internal network (its fetch goes through the egress proxy).
NODE_SVC=""
for s in memberportal aff-landing-pages; do
  if [ -n "$(dc ps -q --status running "$s" 2>/dev/null)" ]; then NODE_SVC="$s"; break; fi
done
[ -n "$NODE_SVC" ] || die "map-tf-products: no running Node app container (memberportal/aff-landing-pages); make up first"
PG="$(dc ps -q postgres)"
[ -n "$PG" ] || die "map-tf-products: local postgres container not running (make up)"
DB="${APP_DB_NAME:-tf_api_local}"

dc cp "$ROOT/seed/tf-products/fetch-tf-dev-products.cjs" "$NODE_SVC:/tmp/tfh-fetch-tf-dev-products.cjs" >/dev/null 2>&1
dc exec -T -e TF_COMPOSITION_API_BASE_URL -e TF_COMPOSITION_API_TOKEN -e __TFH_EGRESS_GUARD_LOGGED=1 "$NODE_SVC" \
  node /tmp/tfh-fetch-tf-dev-products.cjs > "$OUT/tf-dev-products.json" \
  || die "map-tf-products: could not read the TF dev product list (local tf_products left unchanged)"

docker exec "$PG" sh -c 'psql -U "$POSTGRES_USER" -d "$1" -v ON_ERROR_STOP=1 -AtF "	" -c "SELECT id, uuid, coalesce(sku, '\'''\''), coalesce(replace(replace(name, E'\''\t'\'', '\'' '\''), E'\''\n'\'', '\'' '\''), '\'''\'') FROM public.sticky_products ORDER BY id"' _ "$DB" \
  > "$OUT/local-products.tsv"
summary="$(python3 -I "$ROOT/seed/tf-products/match.py" "$OUT/local-products.tsv" "$OUT/tf-dev-products.json" "$OUT/map.tsv")" \
  || die "map-tf-products: matching failed (local tf_products left unchanged)"
echo "map-tf-products: $summary"

TMP=/tmp/tfh-tf-products
docker exec "$PG" rm -rf "$TMP"; docker exec "$PG" mkdir -p "$TMP"
docker cp "$OUT/map.tsv" "$PG:$TMP/map.tsv" >/dev/null
docker cp "$ROOT/seed/tf-products/apply.sql" "$PG:$TMP/apply.sql" >/dev/null
set +e
docker exec -w "$TMP" "$PG" sh -c 'psql -U "$POSTGRES_USER" -d "$1" -v ON_ERROR_STOP=1 -Atq -f apply.sql' _ "$DB"
rc=$?
set -e
docker exec "$PG" rm -rf "$TMP"
[ $rc -eq 0 ] || die "map-tf-products: apply failed (rc=$rc); rolled back"
grn "map-tf-products: local tf_products now point at TF dev product ids (local Postgres only)"
