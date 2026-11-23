from __future__ import annotations

import argparse
import os
from uuid import UUID

import psycopg

from pipeline.worker.runner import create_runner
from pipeline.worker.writer import execute_batch


def select_pending_batch(conn: psycopg.Connection) -> UUID | None:
    row = conn.execute(
        "SELECT b.batch_id FROM run_batches b "
        "WHERE b.status IN ('queued', 'running', 'incomplete') "
        "AND EXISTS (SELECT 1 FROM batch_variations bv WHERE bv.batch_id = b.batch_id AND bv.status <> 'complete') "
        "ORDER BY b.created_at, b.batch_id LIMIT 1"
    ).fetchone()
    if row is None:
        return None
    value = row["batch_id"] if isinstance(row, dict) else row[0]
    return value if isinstance(value, UUID) else UUID(str(value))


def main() -> None:
    parser = argparse.ArgumentParser(description="Execute one SimFleet scenario batch")
    parser.add_argument("--batch-id", type=UUID, help="specific batch; omitted to claim oldest incomplete batch")
    parser.add_argument("--fail-after", type=int, help="simulate worker termination after N completed variations")
    args = parser.parse_args()
    database_url = os.getenv("DATABASE_URL", "postgresql://simfleet:simfleet@localhost:55432/simfleet")
    runner = create_runner(os.getenv("SIMFLEET_ENGINE", "demo"), os.getenv("SIMFLEET_DRIVEBENCH_MODULE"))
    with psycopg.connect(database_url) as conn:
        batch_id = args.batch_id
        if batch_id is None:
            batch_id = select_pending_batch(conn)
            if batch_id is None:
                print({"status": "idle", "processed": 0, "pending": 0})
                return
        result = execute_batch(conn, batch_id, runner, args.fail_after)
    print(result)


if __name__ == "__main__":
    main()