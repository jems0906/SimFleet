from __future__ import annotations

import argparse
import os
import time
from pathlib import Path
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


def initialize_database(database_url: str) -> None:
    database_dir = Path(__file__).resolve().parents[2] / "db"
    with psycopg.connect(database_url) as conn:
        conn.execute((database_dir / "schema.sql").read_text(encoding="utf-8"), prepare=False)
        conn.execute((database_dir / "seed" / "demo.sql").read_text(encoding="utf-8"), prepare=False)


def main() -> None:
    parser = argparse.ArgumentParser(description="Execute one SimFleet scenario batch")
    parser.add_argument("--batch-id", type=UUID, help="specific batch; omitted to claim oldest incomplete batch")
    parser.add_argument("--fail-after", type=int, help="simulate worker termination after N completed variations")
    parser.add_argument("--poll-interval-seconds", type=int, default=0, help="poll for pending batches until stopped")
    parser.add_argument("--initialize-db", action="store_true", help="apply packaged schema and demo seed before polling")
    args = parser.parse_args()
    if args.poll_interval_seconds < 0:
        parser.error("--poll-interval-seconds cannot be negative")
    database_url = os.getenv("DATABASE_URL", "postgresql://simfleet:simfleet@localhost:55432/simfleet")
    runner = create_runner(os.getenv("SIMFLEET_ENGINE", "demo"), os.getenv("SIMFLEET_DRIVEBENCH_MODULE"))
    if args.initialize_db:
        initialize_database(database_url)
    while True:
        with psycopg.connect(database_url) as conn:
            batch_id = args.batch_id or select_pending_batch(conn)
            if batch_id is None:
                result = {"status": "idle", "processed": 0, "pending": 0}
            else:
                result = execute_batch(conn, batch_id, runner, args.fail_after)
        print(result, flush=True)
        if args.poll_interval_seconds == 0:
            return
        time.sleep(args.poll_interval_seconds)


if __name__ == "__main__":
    main()