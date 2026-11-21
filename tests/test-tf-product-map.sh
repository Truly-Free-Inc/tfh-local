#!/usr/bin/env bash
# seed/tf-products/match.py (local catalog -> TF DEV product ids). Offline: synthetic fixtures only, fake ids.
. "$(dirname "$0")/lib.sh"
D="$(mktemp -d "${TMPDIR:-/tmp}/tfh-tfmap.XXXXXX")"
M="$T_ROOT/seed/tf-products/match.py"
printf '%s\t%s\t%s\t%s\n' \
  1 aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa WJ "Wash Jug" \
  2 bbbbbbbb-bbbb-4bbb-abbb-bbbbbbbbbbbb rj "Rinse Jug" \
  3 cccccccc-cccc-4ccc-accc-cccccccccccc DEG "Degreaser" \
  4 dddddddd-dddd-4ddd-addd-dddddddddddd "" "No Sku" \
  5 eeeeeeee-eeee-4eee-aeee-eeeeeeeeeeee NOPE "Missing On TF" \
  6 ffffffff-ffff-4fff-afff-ffffffffffff ONLYREJ "Rejected Only" \
  7 abababab-abab-4aaa-abbb-abababababab NEW "Newest Wins" \
  8 acacacac-acac-4aaa-accc-acacacacacac NAMED "Exact Name" \
  > "$D/local.tsv"
cat > "$D/tf.json" <<'J'
{"total": 12, "products": [
 {"id":"aaaaaaaaaaaaaaaaaaaaaa01","uuid":"x","sku":"WJ","name":"TST Wash Jug TEST","status":"PENDING_APPROVAL"},
 {"id":"aaaaaaaaaaaaaaaaaaaaaa02","uuid":"y","sku":"WJ","name":"Wash Jug TEST","status":"APPROVED"},
 {"id":"aaaaaaaaaaaaaaaaaaaaaa03","uuid":"z","sku":"WJ-301112","name":"Wash Jug","status":"APPROVED"},
 {"id":"bbbbbbbbbbbbbbbbbbbbbb01","uuid":"bbbbbbbb-bbbb-4bbb-abbb-bbbbbbbbbbbb","sku":"RJ ","name":"r","status":"PENDING_APPROVAL"},
 {"id":"bbbbbbbbbbbbbbbbbbbbbb02","uuid":"q","sku":"RJ","name":"r","status":"APPROVED"},
 {"id":"cccccccccccccccccccccc01","uuid":"q","sku":"DEG","name":"d","status":"INACTIVE"},
 {"id":"dddddddddddddddddddddd01","uuid":"q","sku":"ONLYREJ","name":"o","status":"REJECTED"},
 {"id":"6a0000000000000000000001","uuid":"q","sku":"NEW","name":"n","status":"APPROVED"},
 {"id":"6b0000000000000000000001","uuid":"q","sku":"NEW","name":"n","status":"APPROVED"},
 {"id":"eeeeeeeeeeeeeeeeeeeeee01","uuid":"q","sku":"NAMED","name":"Other","status":"APPROVED"},
 {"id":"eeeeeeeeeeeeeeeeeeeeee00","uuid":"q","sku":"NAMED","name":"exact name","status":"APPROVED"},
 {"id":"not-an-object-id","uuid":"q","sku":"NOPE","name":"bad id","status":"APPROVED"}
]}
J
out="$(python3 -I "$M" "$D/local.tsv" "$D/tf.json" "$D/map.tsv")"; rc=$?
got() { awk -F'\t' -v p="$1" '$1==p {print $2}' "$D/map.tsv"; }
expect_true "match exits 0" [ $rc -eq 0 ]
expect_true "exact SKU only (WJ-301112 not matched), APPROVED preferred" [ "$(got 1)" = aaaaaaaaaaaaaaaaaaaaaa02 ]
expect_true "SKU match is trimmed + case-insensitive; same uuid beats APPROVED" [ "$(got 2)" = bbbbbbbbbbbbbbbbbbbbbb01 ]
expect_true "INACTIVE used when it is the only candidate" [ "$(got 3)" = cccccccccccccccccccccc01 ]
expect_true "no SKU -> unmapped" [ -z "$(got 4)" ]
expect_true "malformed TF id ignored -> unmapped" [ -z "$(got 5)" ]
expect_true "REJECTED never used" [ -z "$(got 6)" ]
expect_true "tie -> newest ObjectId" [ "$(got 7)" = 6b0000000000000000000001 ]
expect_true "tie -> exact name beats newer id" [ "$(got 8)" = eeeeeeeeeeeeeeeeeeeeee00 ]
expect_true "summary counts" python3 -I -c 'import json,sys; s=json.loads(sys.argv[1]); sys.exit(0 if (s["local"],s["matched"],s["no_sku"],s["no_match"],s["uuid_equal"])==(8,5,1,2,1) else 1)' "$out"
expect_false "summary prints no ids/SKUs/names" grep -qE 'aaaa|WJ|Wash' <<<"$out"
echo '{"total":0,"products":[]}' > "$D/empty.json"
python3 -I "$M" "$D/local.tsv" "$D/empty.json" "$D/map2.tsv" >/dev/null 2>&1; rc=$?
expect_true "empty TF list refused (never unmaps everything)" [ $rc -ne 0 ]
S="$T_ROOT/scripts/map-tf-product-ids.sh"
expect_true "script is a no-op unless EXTERNALS=real" grep -q 'EXTERNALS" != "real"' "$S"
expect_true "script refuses any TF host but api.dev.trulyfree.com" grep -q '= "api.dev.trulyfree.com" ]' "$S"
expect_true "token passed by env name, never argv" grep -q -- '-e TF_COMPOSITION_API_TOKEN ' "$S"
expect_true "fetch helper is GET only" bash -c '! grep -qE "method: .(POST|PUT|PATCH|DELETE)" "$1"' _ "$T_ROOT/seed/tf-products/fetch-tf-dev-products.cjs"
expect_true "fetch helper refuses non-dev TF host" grep -q "!== 'api.dev.trulyfree.com'" "$T_ROOT/seed/tf-products/fetch-tf-dev-products.cjs"
expect_true "seed-catalog runs the mapping" grep -q 'map-tf-product-ids.sh' "$T_ROOT/scripts/seed-catalog.sh"
rm -rf "$D"
done_tests
