#!/usr/bin/env bash
# make reset: stop the stack and delete LOCAL docker volumes of this project only (DB, Redis, MinIO, recorder).
# Never touches any remote system. Next `make up` re-runs Flyway and the one-time seed.
. "$(dirname "$0")/lib.sh"
if [ "${CONFIRM:-0}" != "1" ]; then ylw "This deletes local volumes for project ${COMPOSE_PROJECT_NAME:-tfh-local}. Re-run with CONFIRM=1."; exit 1; fi
dc --profile stub --profile vector --profile cron down -v --remove-orphans
grn "reset: local volumes removed"
