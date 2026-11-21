#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."

docker compose -f infra/docker-compose.yml up -d db
for attempt in $(seq 1 30); do
  if docker exec infra-db-1 pg_isready -U simfleet -d simfleet >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

docker exec -i infra-db-1 psql -v ON_ERROR_STOP=1 -U simfleet -d simfleet < db/schema.sql
DATABASE_URL="postgresql://simfleet:simfleet@localhost:55432/simfleet" python -m pytest pipeline/tests
