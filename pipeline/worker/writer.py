"""Atomic, idempotent result persistence and batch completion tracking."""

from __future__ import annotations

from typing import Any
from uuid import UUID

import psycopg
from psycopg.types.json import Jsonb

from pipeline.worker.runner import RunResult, ScenarioRunner


def execute_batch(
    conn: psycopg.Connection,
    batch_id: UUID,
    runner: ScenarioRunner,
    fail_after: int | None = None,
) -> dict[str, int | str]:
    conn.execute(
        "UPDATE run_batches SET status = 'running', started_at = COALESCE(started_at, now()) WHERE batch_id = %s",
        (batch_id,),
    )
    rows = conn.execute(
        "SELECT bv.variation_id, v.scenario_id, v.seed, v.params_json, s.name, s.category, s.base_config, "
        "b.driver_version, b.suite_id FROM batch_variations bv JOIN variations v USING (variation_id) "
        "JOIN scenarios s USING (scenario_id) JOIN run_batches b USING (batch_id) "
        "WHERE bv.batch_id = %s AND bv.status <> 'complete' ORDER BY v.seed",
        (batch_id,),
    ).fetchall()
    completed = 0
    try:
        for row in rows:
            if isinstance(row, dict):
                variation_id = row["variation_id"]
                scenario_id = row["scenario_id"]
                seed = row["seed"]
                params = row["params_json"]
                name = row["name"]
                category = row["category"]
                base_config = row["base_config"]
                driver_version = row["driver_version"]
                suite_id = row["suite_id"]
            else:
                variation_id, scenario_id, seed, params, name, category, base_config, driver_version, suite_id = row
            scenario = {"scenario_id": scenario_id, "name": name, "category": category, **base_config}
            result = runner.run(scenario, params, seed, driver_version)
            persist_result(conn, batch_id, variation_id, driver_version, seed, result, suite_id)
            completed += 1
            if fail_after is not None and completed >= fail_after:
                raise RuntimeError("simulated worker termination")
    except Exception:
        conn.execute(
            "UPDATE run_batches SET status = 'incomplete', completed_at = now() WHERE batch_id = %s",
            (batch_id,),
        )
        raise

    pending_row = conn.execute(
        "SELECT count(*) AS pending_count FROM batch_variations WHERE batch_id = %s AND status <> 'complete'", (batch_id,)
    ).fetchone()
    pending = pending_row["pending_count"] if isinstance(pending_row, dict) else pending_row[0]
    status = "complete" if pending == 0 else "incomplete"
    conn.execute(
        "UPDATE run_batches SET status = %s, completed_at = CASE WHEN %s = 'complete' THEN now() ELSE NULL END "
        "WHERE batch_id = %s",
        (status, status, batch_id),
    )
    return {"status": status, "processed": completed, "pending": pending}


def persist_result(
    conn: psycopg.Connection,
    batch_id: UUID,
    variation_id: UUID,
    driver_version: str,
    seed: int,
    result: RunResult,
    suite_id: int | None = None,
) -> None:
    idempotency_key = f"{variation_id}:{driver_version}:repeat-0"
    with conn.transaction():
        inserted = conn.execute(
            "INSERT INTO runs (suite_id, idempotency_key, batch_id, variation_id, driver_version, repeat_index, "
            "started_at, duration_ms, status, completed_at) VALUES (%s, %s, %s, %s, %s, 0, now(), %s, %s, now()) "
            "ON CONFLICT (idempotency_key) DO NOTHING RETURNING run_id",
            (suite_id, idempotency_key, batch_id, variation_id, driver_version, result.duration_ms, result.status),
        ).fetchone()
        if inserted:
            run_id = inserted["run_id"] if isinstance(inserted, dict) else inserted[0]
            conn.execute(
                "INSERT INTO verdicts (run_id, passed, failure_category) VALUES (%s, %s, %s)",
                (run_id, result.passed, result.failure_category),
            )
            with conn.cursor() as cur:
                cur.executemany(
                    "INSERT INTO run_metrics (run_id, metric_name, metric_value) VALUES (%s, %s, %s)",
                    [(run_id, name, value) for name, value in result.metrics.items()],
                )
        conn.execute(
            "UPDATE batch_variations SET status = 'complete', completed_at = now() "
            "WHERE batch_id = %s AND variation_id = %s",
            (batch_id, variation_id),
        )