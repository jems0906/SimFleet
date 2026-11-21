from uuid import uuid4

import pytest

from pipeline.tests.conftest import add_run
from pipeline.generate_batches import VariationPolicy, create_batch, generate_variations
from pipeline.worker.runner import DemoRunner, RunResult
from pipeline.worker.writer import execute_batch, persist_result


def test_retry_does_not_duplicate_a_run(db):
    conn, scenarios = db
    scenario_id = scenarios["merge-a"]
    variation_id, _ = add_run(conn, scenario_id, "v1", 10, True)
    batch_id = conn.execute(
        "INSERT INTO run_batches (driver_version, expected_count) VALUES ('v1', 1) RETURNING batch_id"
    ).fetchone()["batch_id"]
    conn.execute("INSERT INTO batch_variations (batch_id, variation_id) VALUES (%s, %s)", (batch_id, variation_id))
    result = RunResult("completed", True, None, 100, {"comfort_jerk": 1.0})
    persist_result(conn, batch_id, variation_id, "v1", 10, result)
    assert conn.execute("SELECT count(*) AS run_count FROM runs WHERE variation_id = %s", (variation_id,)).fetchone()["run_count"] == 1


def test_same_seed_retries_have_a_stable_variation_id():
    first = generate_variations(7, VariationPolicy(), 80, 5)
    second = generate_variations(7, VariationPolicy(), 80, 5)
    assert first == second


def test_worker_death_preserves_progress_and_retry_runs_only_missing(db):
    conn, scenarios = db
    batch_id = create_batch(conn, scenarios["merge-a"], "v1", 80, 3, VariationPolicy())

    with pytest.raises(RuntimeError, match="simulated worker termination"):
        execute_batch(conn, batch_id, DemoRunner(), fail_after=1)

    incomplete = conn.execute(
        "SELECT status FROM run_batches WHERE batch_id = %s", (batch_id,)
    ).fetchone()["status"]
    assert incomplete == "incomplete"

    result = execute_batch(conn, batch_id, DemoRunner())
    assert result["status"] == "complete"
    assert result["processed"] == 2