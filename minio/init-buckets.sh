#!/bin/sh
# Creates the S3 buckets tf-api expects, in local MinIO, using the SAME names as the non-prod config (.env).
# Empty names are skipped. Idempotent.
set -eu
mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
for b in $BUCKETS; do
  [ -n "$b" ] || continue
  mc mb --ignore-existing "local/$b"
  # TODO: public-read only on CDN prefixes (images, catalog JSON, search model, sitemap); confirm prefixes.
  echo "bucket ready: $b"
done
[ -n "$(echo "$BUCKETS" | tr -d ' ')" ] || echo "minio-init: no bucket names set in .env (AWS_BUCKET etc.); nothing created"
