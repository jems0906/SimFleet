from __future__ import annotations

import os
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from pipeline.api.db import fetch_all, fetch_window
from pipeline.api.queries import load_query

app = FastAPI(title="SimFleet API", version="1.0.0")
cors_origins = [origin.strip() for origin in os.getenv("CORS_ORIGINS", "http://localhost:5173").split(",") if origin.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_methods=["GET"],
    allow_headers=["*"],
)


def parse_window(start: str | None, end: str | None) -> tuple[str, str]:
    now = datetime.now(timezone.utc)
    end_dt = datetime.fromisoformat(end) if end else now
    start_dt = datetime.fromisoformat(start) if start else datetime.fromtimestamp(0, timezone.utc)
    if start_dt >= end_dt:
        raise HTTPException(status_code=400, detail="start must be earlier than end")
    return start_dt.isoformat(), end_dt.isoformat()


@app.get("/health")
def health() -> dict:
    try:
        fetch_all("SELECT 1 AS ok")
        return {"status": "ok", "database": "connected"}
    except Exception as exc:
        raise HTTPException(status_code=503, detail="database unavailable") from exc


@app.get("/api/versions")
def versions() -> list[dict]:
    return fetch_all("SELECT driver_version, git_sha, created_at FROM drivers ORDER BY created_at DESC")


@app.get("/api/analytics/pass-rates")
def pass_rates(start: str | None = None, end: str | None = None) -> dict:
    start, end = parse_window(start, end)
    return fetch_window(load_query("pass_rates"), (start, end), start, end)


@app.get("/api/analytics/distributions")
def distributions(version: str, metric: str, start: str | None = None, end: str | None = None) -> dict:
    start, end = parse_window(start, end)
    rows = fetch_all(load_query("metric_distributions"), (version, metric, start, end))
    return {"run_count": sum(row["run_count"] for row in rows), "window": {"start": start, "end": end}, "results": rows}


@app.get("/api/analytics/regressions")
def regressions(baseline: str, candidate: str, start: str | None = None, end: str | None = None) -> dict:
    start, end = parse_window(start, end)
    params = (baseline, candidate, start, end, baseline, candidate)
    rows = fetch_all(load_query("regressions"), params)
    return {"run_count": sum(row["baseline_run_count"] + row["candidate_run_count"] for row in rows), "window": {"start": start, "end": end}, "results": rows}


@app.get("/api/analytics/flaky")
def flaky(version: str, start: str | None = None, end: str | None = None) -> dict:
    start, end = parse_window(start, end)
    rows = fetch_all(load_query("flaky_scenarios"), (version, start, end))
    return {"run_count": sum(row["repeated_seed_count"] for row in rows), "window": {"start": start, "end": end}, "results": rows}


@app.get("/api/analytics/failures")
def failures(start: str | None = None, end: str | None = None) -> dict:
    start, end = parse_window(start, end)
    return fetch_window(load_query("failure_breakdown"), (start, end), start, end)


@app.get("/api/batches")
def batches() -> list[dict]:
    return fetch_all(load_query("batch_health"))


@app.get("/api/analytics/worst-trajectories")
def worst_trajectories(version: str, metric: str = "comfort_jerk", limit: int = 10, start: str | None = None, end: str | None = None) -> dict:
    if limit < 1 or limit > 100:
        raise HTTPException(status_code=400, detail="limit must be between 1 and 100")
    start, end = parse_window(start, end)
    rows = fetch_all(load_query("worst_trajectories"), (version, metric, start, end, limit))
    return {"run_count": sum(row["run_count"] for row in rows), "window": {"start": start, "end": end}, "results": rows}


@app.get("/api/suites")
def suites() -> list[dict]:
    return fetch_all("SELECT suite_id, name, suite_type, created_at FROM suites ORDER BY suite_type, name")