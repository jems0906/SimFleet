from pipeline.api.queries import load_query
from pipeline.tests.conftest import add_run


def test_disagreement_for_repeated_seed_is_reported(db):
    conn, scenarios = db
    scenario_id = scenarios["flaky-c"]
    variation_id, _ = add_run(conn, scenario_id, "v1", 22, True, repeat_index=0)
    run_id = conn.execute(
        "INSERT INTO runs (idempotency_key, batch_id, variation_id, driver_version, repeat_index, started_at, duration_ms, status) "
        "SELECT %s, batch_id, %s, 'v1', 1, now(), 100, 'completed' FROM runs WHERE variation_id = %s LIMIT 1 RETURNING run_id",
        (f"{variation_id}:v1:repeat-1", variation_id, variation_id),
    ).fetchone()["run_id"]
    conn.execute("INSERT INTO verdicts VALUES (%s, false, 'race')", (run_id,))
    rows = conn.execute(load_query("flaky_scenarios"), ("v1", "1970-01-01", "2999-01-01")).fetchall()
    assert [(row["name"], row["repeated_seed_count"], row["disagreeing_seed_count"]) for row in rows] == [("flaky-c", 1, 1)]