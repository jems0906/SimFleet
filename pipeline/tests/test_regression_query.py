from pipeline.api.queries import load_query
from pipeline.tests.conftest import add_run


def test_significant_planted_regression_is_detected(db):
    conn, scenarios = db
    scenario_id = scenarios["merge-a"]
    for seed in range(100):
        add_run(conn, scenario_id, "v1", seed, True)
        add_run(conn, scenario_id, "v2", seed + 1000, seed < 50)
    rows = conn.execute(
        load_query("regressions"), ("v1", "v2", "1970-01-01", "2999-01-01", "v1", "v2")
    ).fetchall()
    assert [(row["name"], row["baseline_pass_rate"], row["candidate_pass_rate"]) for row in rows] == [("merge-a", 1.0, 0.5)]