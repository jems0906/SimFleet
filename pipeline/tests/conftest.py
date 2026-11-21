from __future__ import annotations

import os
from pathlib import Path
from uuid import uuid4

import psycopg
import pytest
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

ROOT = Path(__file__).resolve().parents[2]
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://simfleet:simfleet@localhost:55432/simfleet")


@pytest.fixture
def db():
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        conn.execute("TRUNCATE verdicts, run_metrics, runs, batch_variations, run_batches, variations, suite_scenarios, scenarios, suites, drivers RESTART IDENTITY CASCADE")
        conn.execute((ROOT / "db" / "schema.sql").read_text(encoding="utf-8"))
        conn.execute("INSERT INTO drivers (driver_version, git_sha) VALUES ('v1', 'aaa'), ('v2', 'bbb')")
        scenario_ids = {}
        for name, category in (("merge-a", "merge"), ("crossing-b", "crossing"), ("flaky-c", "merge")):
            scenario_ids[name] = conn.execute(
                "INSERT INTO scenarios (name, category) VALUES (%s, %s) RETURNING scenario_id", (name, category)
            ).fetchone()["scenario_id"]
        yield conn, scenario_ids


def add_run(conn, scenario_id, version, seed, passed, metric=1.0, batch_id=None, repeat_index=0, failure="collision"):
    variation_id = uuid4()
    conn.execute(
        "INSERT INTO variations (variation_id, scenario_id, seed, params_json) VALUES (%s, %s, %s, %s)",
        (variation_id, scenario_id, seed, Jsonb({})),
    )
    if batch_id is None:
        conn.execute(
            "INSERT INTO run_batches (driver_version, expected_count, status) VALUES (%s, 1, 'complete') RETURNING batch_id",
            (version,),
        )
        batch_id = conn.execute("SELECT batch_id FROM run_batches WHERE driver_version=%s ORDER BY created_at DESC LIMIT 1", (version,)).fetchone()["batch_id"]
    run_id = conn.execute(
        "INSERT INTO runs (idempotency_key, batch_id, variation_id, driver_version, repeat_index, started_at, duration_ms, status) "
        "VALUES (%s, %s, %s, %s, %s, now(), 100, 'completed') RETURNING run_id",
        (f"{variation_id}:{version}:repeat-{repeat_index}", batch_id, variation_id, version, repeat_index),
    ).fetchone()["run_id"]
    conn.execute("INSERT INTO verdicts VALUES (%s, %s, %s)", (run_id, passed, None if passed else failure))
    conn.execute("INSERT INTO run_metrics VALUES (%s, 'comfort_jerk', %s)", (run_id, metric))
    return variation_id, run_id