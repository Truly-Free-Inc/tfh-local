#!/usr/bin/env bash
# make seed-sitemap: build sitemap.xml from the LOCAL sitemap_entries (make seed-catalog) with tf-api's own generator
# (POST /api/v1/sitemaps/generate on the local tf-api, Basic auth from .env) -> local MinIO SITEMAP_S3_BUCKET, then
# make only that object anonymously readable so the funnels app's /sitemap.xml rewrite (SITEMAP_S3_URL -> MinIO)
# can serve it. Local containers only; no cron, no remote host. Credentials go to curl on stdin, never argv/logs.
. "$(dirname "$0")/lib.sh"
load_env
"$ROOT/scripts/preflight.sh"
B="${SITEMAP_S3_BUCKET:?SITEMAP_S3_BUCKET unset in .env}"; K="${SITEMAP_S3_KEY:-sitemap.xml}"
[ -n "${TF_API_BASIC_AUTH_USERNAME:-}" ] && [ -n "${TF_API_BASIC_AUTH_PASSWORD:-}" ] || die "TF_API_BASIC_AUTH_* unset (make bootstrap)"
url="http://127.0.0.1:${TF_API_HOST_PORT:-13000}/api/v1/sitemaps/generate"
code="$(printf 'user = "%s:%s"\n' "$TF_API_BASIC_AUTH_USERNAME" "$TF_API_BASIC_AUTH_PASSWORD" |
  curl -s -K - -o "$STATE/sitemap-generate.json" -w '%{http_code}' -X POST -m 120 "$url" || true)"
[ "$code" = 200 ] || die "sitemap generate -> HTTP $code (see $STATE/sitemap-generate.json)"
cd "$ROOT"
docker compose run --rm --no-deps --entrypoint /bin/sh minio-init -c \
  'mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && mc anonymous set download "local/$1/$2" >/dev/null' \
  _ "$B" "$K" || die "could not set read access on local/$B/$K"
grn "sitemap: $(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("urlCount", json.load(open(sys.argv[1])).get("url_count","?")))' "$STATE/sitemap-generate.json") URLs -> local MinIO $B/$K (served by funnels /sitemap.xml)"
