#!/usr/bin/env bash
# make map-flag-env: copy the approved PRODUCTION flag snapshot rows to environment 'development', the APP_ENV
# local tf-api runs with (TF_API_APP_ENV), so its environment-scoped flag lookups see prod values (TFHFUNNEL-8090).
# Local compose postgres only; idempotent; also run by `make seed-catalog`. Prints only a row count.
. "$(dirname "$0")/lib.sh"
load_env
case "$(printf '%s' "${TF_API_APP_ENV:-development}" | tr '[:upper:]' '[:lower:]')" in
  development) ;;
  *) ylw "map-flag-env: TF_API_APP_ENV='${TF_API_APP_ENV}' (not development); tf-api does not read the mapped rows, skipped"; exit 0 ;;
esac
PG="$(dc ps -q postgres)"
[ -n "$PG" ] || die "map-flag-env: local postgres container not running (make up)"
docker cp "$ROOT/seed/flag-env/map.sql" "$PG:/tmp/tfh-flag-env.sql" >/dev/null
set +e
docker exec "$PG" sh -c 'psql -U "$POSTGRES_USER" -d "$1" -X -q -At -f /tmp/tfh-flag-env.sql' _ "${APP_DB_NAME:-tf_api_local}"
rc=$?
set -e
docker exec "$PG" rm -f /tmp/tfh-flag-env.sql
[ $rc -eq 0 ] || die "map-flag-env failed (rc=$rc); rolled back"
grn "map-flag-env: OK (tf-api APP_ENV=development reads the production snapshot values)"
