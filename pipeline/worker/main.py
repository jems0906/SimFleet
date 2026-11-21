from __future__ import annotations

import argparse
import os
from uuid import UUID

import psycopg

from pipeline.worker.runner import create_runner
from pipeline.worker.writer import execute_batch


def main() -> None:
    parser = argparse.ArgumentParser(description="Execute one SimFleet scenario batch")
    parser.add_argument("--batch-id", required=True, type=UUID)
    parser.add_argument("--fail-after", type=int, help="simulate worker termination after N completed variations")
    args = parser.parse_args()
    database_url = os.getenv("DATABASE_URL", "postgresql://simfleet:simfleet@localhost:55432/simfleet")
    runner = create_runner(os.getenv("SIMFLEET_ENGINE", "demo"), os.getenv("SIMFLEET_DRIVEBENCH_MODULE"))
    with psycopg.connect(database_url) as conn:
        result = execute_batch(conn, args.batch_id, runner, args.fail_after)
    print(result)


if __name__ == "__main__":
    main()