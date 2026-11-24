#!/bin/sh
set -eu

export PGUSER="${PGUSER:-${POSTGRES_USER:-simfleet}}"
export PGDATABASE="${PGDATABASE:-${POSTGRES_DB:-simfleet}}"
scratch="simfleet_restore_$$"
archive="/tmp/${scratch}.dump"
created=0

cleanup() {
    if [ "$created" -eq 1 ]; then
        dropdb --if-exists "$scratch"
    fi
    rm -f "$archive"
}
trap cleanup EXIT

counts='SELECT json_build_array((SELECT count(*) FROM drivers), (SELECT count(*) FROM scenarios), (SELECT count(*) FROM run_batches), (SELECT count(*) FROM runs), (SELECT count(*) FROM run_metrics), (SELECT count(*) FROM verdicts))'
before=$(psql -X -At -v ON_ERROR_STOP=1 -c "$counts")
pg_dump --format=custom --file="$archive"
createdb "$scratch"
created=1
pg_restore --no-owner --no-acl --exit-on-error --dbname="$scratch" "$archive"
after=$(psql -X -At -v ON_ERROR_STOP=1 --dbname="$scratch" -c "$counts")

if [ "$before" != "$after" ]; then
    echo "Restore verification failed: source and restored row counts differ." >&2
    exit 1
fi
printf 'Restore verified: drivers, scenarios, batches, runs, metrics, verdicts = %s\n' "$after"