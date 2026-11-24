import os
import json
from types import SimpleNamespace

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import FastAPI
from fastapi.testclient import TestClient

os.environ.setdefault("SIMFLEET_API_KEY", "local-demo-key")
from pipeline.api.main import app
import pipeline.api.main as api_module
from pipeline.api.queries import load_query
from pipeline.generate_batches import VariationPolicy, create_batch
from pipeline.tests.conftest import ROOT, add_run


def test_pass_rates_and_failure_breakdown_hand_computed(db):
    conn, scenarios = db
    add_run(conn, scenarios["merge-a"], "v1", 1, True)
    add_run(conn, scenarios["merge-a"], "v1", 2, False)
    rows = conn.execute(load_query("pass_rates"), ("1970-01-01", "2999-01-01")).fetchall()
    assert [(row["driver_version"], row["category"], row["run_count"], row["pass_rate"]) for row in rows] == [("v1", "merge", 2, 0.5)]
    failures = conn.execute(load_query("failure_breakdown"), ("1970-01-01", "2999-01-01")).fetchall()
    assert [(row["driver_version"], row["failure_category"], row["failure_count"]) for row in failures] == [("v1", "collision", 1)]


def test_metric_percentiles_hand_computed(db):
    conn, scenarios = db
    for seed, value in enumerate((1.0, 2.0, 3.0, 4.0, 100.0)):
        add_run(conn, scenarios["merge-a"], "v1", seed, True, metric=value)
    row = conn.execute(
        load_query("metric_distributions"), ("v1", "comfort_jerk", "1970-01-01", "2999-01-01")
    ).fetchone()
    assert row["run_count"] == 5
    assert row["median"] == 3.0
    assert abs(row["p95"] - 80.8) < 1e-6


def test_batch_health_reports_missing_variations(db):
    conn, _ = db
    batch_id = conn.execute(
        "INSERT INTO run_batches (driver_version, expected_count, status) VALUES ('v1', 2, 'incomplete') RETURNING batch_id"
    ).fetchone()["batch_id"]
    rows = conn.execute(load_query("batch_health")).fetchall()
    row = next(item for item in rows if item["batch_id"] == batch_id)
    assert (row["status"], row["expected_count"], row["completed_count"], row["missing_count"]) == ("incomplete", 2, 0, 0)


def test_worst_trajectories_and_suites(db):
    conn, scenarios = db
    for seed, value in enumerate((1.0, 4.0, 2.0)):
        add_run(conn, scenarios["merge-a"], "v1", seed, True, metric=value)

    rows = conn.execute(
        load_query("worst_trajectories"), ("v1", "comfort_jerk", "1970-01-01", "2999-01-01", 2)
    ).fetchall()
    assert [row["metric_value"] for row in rows] == [4.0, 2.0]

    suite_id = conn.execute(
        "INSERT INTO suites (name, suite_type) VALUES ('smoke-test', 'smoke') RETURNING suite_id"
    ).fetchone()["suite_id"]
    conn.execute("INSERT INTO suite_scenarios VALUES (%s, %s)", (suite_id, scenarios["merge-a"]))
    assert conn.execute(
        "SELECT count(*) AS suite_count FROM suite_scenarios WHERE suite_id = %s", (suite_id,)
    ).fetchone()["suite_count"] == 1

    batch_id = create_batch(
        conn, scenarios["merge-a"], "v1", 300, 2, VariationPolicy(), suite_name="smoke-test"
    )
    batch_suite_id = conn.execute(
        "SELECT suite_id FROM run_batches WHERE batch_id = %s", (batch_id,)
    ).fetchone()["suite_id"]
    assert batch_suite_id == suite_id


def test_1000_runs_are_order_independent_across_replica_batches(db):
    conn, scenarios = db
    scenario_id = scenarios["merge-a"]

    for batch_index in range(20):
        batch_id = conn.execute(
            "INSERT INTO run_batches (driver_version, expected_count, status) VALUES ('v1', 50, 'complete') RETURNING batch_id"
        ).fetchone()["batch_id"]
        for seed in range(batch_index * 50, (batch_index + 1) * 50):
            add_run(conn, scenario_id, "v1", seed, seed % 2 == 0, batch_id=batch_id)

    replica = conn.execute(
        "SELECT count(*) AS run_count, count(*) FILTER (WHERE passed)::float / count(*) AS pass_rate "
        "FROM runs r JOIN verdicts v USING (run_id) JOIN variations va USING (variation_id) "
        "WHERE va.scenario_id = %s", (scenario_id,)
    ).fetchone()

    single_batch_id = conn.execute(
        "INSERT INTO run_batches (driver_version, expected_count, status) VALUES ('v2', 1000, 'complete') RETURNING batch_id"
    ).fetchone()["batch_id"]
    for seed in range(2000, 3000):
        add_run(conn, scenario_id, "v2", seed, seed % 2 == 0, batch_id=single_batch_id)

    single = conn.execute(
        "SELECT count(*) AS run_count, count(*) FILTER (WHERE passed)::float / count(*) AS pass_rate "
        "FROM runs r JOIN verdicts v USING (run_id) JOIN variations va USING (variation_id) "
        "WHERE va.scenario_id = %s AND r.driver_version = 'v2'", (scenario_id,)
    ).fetchone()

    assert replica["run_count"] == 1000
    assert single["run_count"] == 1000
    assert abs(replica["pass_rate"] - single["pass_rate"]) < 1e-9


def test_late_result_changes_only_the_matching_time_window(db):
    conn, scenarios = db

    before = conn.execute(
        load_query("pass_rates"), ("1970-01-01", "2000-01-01")
    ).fetchall()
    assert before == []

    _, run_id = add_run(conn, scenarios["merge-a"], "v1", 42, True)
    conn.execute(
        "UPDATE runs SET completed_at = '1999-06-01 00:00:00+00' WHERE run_id = %s",
        (run_id,),
    )

    after = conn.execute(
        load_query("pass_rates"), ("1970-01-01", "2000-01-01")
    ).fetchall()
    assert len(after) == 1
    assert after[0]["run_count"] == 1
    assert after[0]["pass_rate"] == 1.0


def test_api_rejects_missing_key(db):
    client = TestClient(app)
    assert client.get("/health").status_code == 200
    assert client.get("/api/versions").status_code == 401
    assert client.get("/api/versions", headers={"X-API-Key": "wrong"}).status_code == 401


@pytest.mark.parametrize("roles,expected", [(["SimFleet.Reader"], 200), ([], 403), (["Other.Role"], 403), ("SimFleet.Reader", 403)])
def test_api_requires_reader_role(monkeypatch, roles, expected):
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    now = int(api_module.time.time())
    token = jwt.encode(
        {"sub": "test-user", "iss": "https://issuer.example", "aud": "simfleet", "iat": now, "exp": now + 60, "roles": roles},
        private_key,
        algorithm="RS256",
    )
    key_client = SimpleNamespace(get_signing_key_from_jwt=lambda token: SimpleNamespace(key=private_key.public_key()))
    monkeypatch.setattr(api_module, "signing_key_client", key_client)
    monkeypatch.setattr(api_module, "JWT_ISSUER", "https://issuer.example")
    monkeypatch.setattr(api_module, "JWT_AUDIENCE", "simfleet")
    monkeypatch.setattr(api_module, "fetch_all", lambda *args: [])
    client = TestClient(app)
    assert client.get("/api/versions", headers={"Authorization": f"Bearer {token}"}).status_code == expected


def test_rate_limit_returns_429():
    limited_app = FastAPI()
    limited_app.add_middleware(api_module.RateLimitMiddleware)

    @limited_app.get("/api/test")
    def endpoint():
        return {"ok": True}

    client = TestClient(limited_app)
    for _ in range(60):
        assert client.get("/api/test").status_code == 200
    response = client.get("/api/test")
    assert response.status_code == 429
    assert response.headers["Retry-After"] == "60"


def test_audit_record_does_not_log_credentials_or_query(monkeypatch, capsys):
    monkeypatch.setattr(api_module, "fetch_all", lambda *args: [])
    client = TestClient(app)
    response = client.get("/api/versions?private=do-not-log", headers={"X-API-Key": api_module.API_KEY, "X-Forwarded-For": "spoofed"})
    assert response.status_code == 200
    output = capsys.readouterr().out
    record = json.loads(output.strip())
    assert record["request_id"] == response.headers["X-Request-ID"]
    assert record["status_code"] == 200
    assert record["duration_ms"] >= 0
    assert record["client_ip"] != "spoofed"
    assert api_module.API_KEY not in output
    assert "do-not-log" not in output


def test_demo_seed_is_idempotent(db):
    conn, _ = db
    seed_sql = (ROOT / "db" / "seed" / "demo.sql").read_text(encoding="utf-8")

    conn.execute(seed_sql, prepare=False)
    first = conn.execute(
        "SELECT (SELECT count(*) FROM scenarios) AS scenarios, "
        "(SELECT count(*) FROM run_batches) AS batches, "
        "(SELECT count(*) FROM runs) AS runs, "
        "(SELECT count(*) FROM run_metrics) AS metrics"
    ).fetchone()

    conn.execute(seed_sql, prepare=False)
    second = conn.execute(
        "SELECT (SELECT count(*) FROM scenarios) AS scenarios, "
        "(SELECT count(*) FROM run_batches) AS batches, "
        "(SELECT count(*) FROM runs) AS runs, "
        "(SELECT count(*) FROM run_metrics) AS metrics"
    ).fetchone()

    assert first == second
