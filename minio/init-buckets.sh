#!/bin/sh
# Creates the S3 buckets tf-api expects, in local MinIO, using the SAME names as the non-prod config (.env).
# Empty names are skipped. Idempotent. Then seeds what exists in local repo files (never overwrites).
set -eu
mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
for b in $BUCKETS; do
  [ -n "$b" ] || continue
  mc mb --ignore-existing "local/$b"
  # TODO: public-read only on CDN prefixes (images, catalog JSON, search model, sitemap); confirm prefixes.
  echo "bucket ready: $b"
done
[ -n "$(echo "$BUCKETS" | tr -d ' ')" ] || echo "minio-init: no bucket names set in .env (AWS_BUCKET etc.); nothing created"

# Seed: search model exported by the vector-search repo -> SEARCH_MODEL_S3_BUCKET/<key> (tf-api default key).
seed() { # bucket key file
  [ -n "$1" ] && [ -f "$3" ] || { echo "seed skipped: $1/$2 (no bucket or no local file)"; return 0; }
  if mc stat "local/$1/$2" >/dev/null 2>&1; then echo "seed exists: $1/$2"; return 0; fi
  mc cp --quiet "$3" "local/$1/$2" >/dev/null && echo "seeded: $1/$2"
}
seed "${SEARCH_MODEL_S3_BUCKET:-}" "${SEARCH_MODEL_S3_KEY:-search_model.json}" /seed/search/search_model.json
# No catalog JSON (nextgen-catalog.json), sitemap or Yotpo export exists in local repo files: those buckets stay empty.
