from __future__ import annotations

import os
from datetime import datetime, timezone

import hashlib
import json
import time

import jwt
from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware

from pipeline.api.db import fetch_all, fetch_window
from pipeline.api.queries import load_query

app = FastAPI(title="SimFleet API", version="1.0.0")
cors_origins = [origin.strip() for origin in os.getenv("CORS_ORIGINS", "http://localhost:5173").split(",") if origin.strip()]
API_KEY = os.getenv("SIMFLEET_API_KEY")
JWT_ISSUER = os.getenv("SIMFLEET_JWT_ISSUER")
JWT_AUDIENCE = os.getenv("SIMFLEET_JWT_AUDIENCE")
JWT_JWKS_URL = os.getenv("SIMFLEET_JWT_JWKS_URL")
if not API_KEY:
    raise RuntimeError("SIMFLEET_API_KEY is required")


def require_api_key(
    x_api_key: str = Header(default=""),
    authorization: str = Header(default=""),
) -> None:
    if x_api_key == API_KEY:
        return

    if JWT_JWKS_URL and authorization.startswith("Bearer "):
        token = authorization.removeprefix("Bearer ").strip()
        try:
            signing_keys = jwt.PyJWKClient(JWT_JWKS_URL, timeout=5.0).get_signing_key_from_jwt(token)
            jwt.decode(
                token,
                signing_keys.key,
                algorithms=["RS256"],
                issuer=JWT_ISSUER,
                audience=JWT_AUDIENCE,
            )
            return
        except jwt.PyJWTError:
            raise HTTPException(status_code=401, detail="invalid bearer token")

    raise HTTPException(status_code=401, detail="invalid API key")


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self.requests: dict[str, list[float]] = {}

    async def dispatch(self, request, call_next):
        if request.url.path.startswith("/api/"):
            principal = request.headers.get("x-api-key") or request.headers.get("authorization") or "anonymous"
            principal = hashlib.sha256(principal.encode("utf-8")).hexdigest()
            now = time.monotonic()
            window = self.requests.setdefault(principal, [])
            window[:] = [timestamp for timestamp in window if now - timestamp < 60]
            if len(window) >= 60:
                raise HTTPException(status_code=429, detail="rate limit exceeded")
            window.append(now)
        return await call_next(request)


class AuditMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)
        if request.url.path.startswith("/api/"):
            principal = request.headers.get("x-api-key", "bearer")
            forwarded = request.headers.get("x-forwarded-for")
            ip = forwarded.split(",", 1)[0].strip() if forwarded else (request.client.host if request.client else "unknown")
            audit_record = {
                "event": "api_request",
                "principal_type": "api-key" if principal != "bearer" else "bearer",
                "method": request.method,
                "path": request.url.path,
                "status_code": response.status_code,
                "client_ip": ip,
            }
            print(json.dumps(audit_record, separators=(",", ":")), flush=True)
        return response


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)
        response.headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'"
        response.headers["Cross-Origin-Opener-Policy"] = "same-origin"
        response.headers["Cache-Control"] = "no-store"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        response.headers["X-Frame-Options"] = "DENY"
        return response


app.add_middleware(RateLimitMiddleware)
app.add_middleware(AuditMiddleware)
app.add_middleware(SecurityHeadersMiddleware)
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


@app.get("/api/versions", dependencies=[Depends(require_api_key)])
def versions() -> list[dict]:
    return fetch_all("SELECT driver_version, git_sha, created_at FROM drivers ORDER BY created_at DESC")


@app.get("/api/analytics/pass-rates", dependencies=[Depends(require_api_key)])
def pass_rates(start: str | None = None, end: str | None = None) -> dict:
    start, end = parse_window(start, end)
    return fetch_window(load_query("pass_rates"), (start, end), start, end)


@app.get("/api/analytics/distributions", dependencies=[Depends(require_api_key)])
def distributions(version: str, metric: str, start: str | None = None, end: str | None = None) -> dict:
    start, end = parse_window(start, end)
    rows = fetch_all(load_query("metric_distributions"), (version, metric, start, end))
    return {"run_count": sum(row["run_count"] for row in rows), "window": {"start": start, "end": end}, "results": rows}


@app.get("/api/analytics/regressions", dependencies=[Depends(require_api_key)])
def regressions(baseline: str, candidate: str, start: str | None = None, end: str | None = None) -> dict:
    start, end = parse_window(start, end)
    params = (baseline, candidate, start, end, baseline, candidate)
    rows = fetch_all(load_query("regressions"), params)
    return {"run_count": sum(row["baseline_run_count"] + row["candidate_run_count"] for row in rows), "window": {"start": start, "end": end}, "results": rows}


@app.get("/api/analytics/flaky", dependencies=[Depends(require_api_key)])
def flaky(version: str, start: str | None = None, end: str | None = None) -> dict:
    start, end = parse_window(start, end)
    rows = fetch_all(load_query("flaky_scenarios"), (version, start, end))
    return {"run_count": sum(row["repeated_seed_count"] for row in rows), "window": {"start": start, "end": end}, "results": rows}


@app.get("/api/analytics/failures", dependencies=[Depends(require_api_key)])
def failures(start: str | None = None, end: str | None = None) -> dict:
    start, end = parse_window(start, end)
    return fetch_window(load_query("failure_breakdown"), (start, end), start, end)


@app.get("/api/batches", dependencies=[Depends(require_api_key)])
def batches() -> list[dict]:
    return fetch_all(load_query("batch_health"))


@app.get("/api/analytics/worst-trajectories", dependencies=[Depends(require_api_key)])
def worst_trajectories(version: str, metric: str = "comfort_jerk", limit: int = 10, start: str | None = None, end: str | None = None) -> dict:
    if limit < 1 or limit > 100:
        raise HTTPException(status_code=400, detail="limit must be between 1 and 100")
    start, end = parse_window(start, end)
    rows = fetch_all(load_query("worst_trajectories"), (version, metric, start, end, limit))
    return {"run_count": sum(row["run_count"] for row in rows), "window": {"start": start, "end": end}, "results": rows}


@app.get("/api/suites", dependencies=[Depends(require_api_key)])
def suites() -> list[dict]:
    return fetch_all("SELECT suite_id, name, suite_type, created_at FROM suites ORDER BY suite_type, name")