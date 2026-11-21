from __future__ import annotations

import os
from collections.abc import Iterator

import psycopg
from psycopg.rows import dict_row


def connect() -> psycopg.Connection:
    return psycopg.connect(
        os.getenv("DATABASE_URL", "postgresql://simfleet:simfleet@localhost:55432/simfleet"),
        row_factory=dict_row,
    )


def fetch_all(query: str, params: tuple = ()) -> list[dict]:
    with connect() as conn:
        return conn.execute(query, params).fetchall()


def fetch_window(query: str, params: tuple, start: str, end: str) -> dict:
    rows = fetch_all(query, params)
    return {"run_count": sum(row.get("run_count", 0) for row in rows), "window": {"start": start, "end": end}, "results": rows}