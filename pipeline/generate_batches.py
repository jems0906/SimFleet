"""Deterministic scenario variation generation and PostgreSQL batch creation."""

from __future__ import annotations

import argparse
import json
import random
from dataclasses import dataclass
from typing import Any
from uuid import NAMESPACE_URL, UUID, uuid5

import psycopg
from psycopg.types.json import Jsonb


@dataclass(frozen=True)
class VariationPolicy:
    speed_scale_min: float = 0.8
    speed_scale_max: float = 1.2
    spawn_offset_min_m: float = -2.0
    spawn_offset_max_m: float = 2.0
    timing_jitter_min_s: float = 0.0
    timing_jitter_max_s: float = 0.5


def generate_variations(
    scenario_id: int,
    policy: VariationPolicy,
    seed: int,
    count: int,
) -> list[dict[str, Any]]:
    if count < 1:
        raise ValueError("count must be positive")
    if policy.speed_scale_min > policy.speed_scale_max:
        raise ValueError("speed scale minimum must not exceed maximum")
    if policy.spawn_offset_min_m > policy.spawn_offset_max_m:
        raise ValueError("spawn offset minimum must not exceed maximum")
    if policy.timing_jitter_min_s > policy.timing_jitter_max_s:
        raise ValueError("timing jitter minimum must not exceed maximum")

    rng = random.Random(seed)
    variations = []
    for index in range(count):
        variation_seed = seed + index
        params = {
            "speed_scale": round(rng.uniform(policy.speed_scale_min, policy.speed_scale_max), 6),
            "spawn_offset_m": round(rng.uniform(policy.spawn_offset_min_m, policy.spawn_offset_max_m), 6),
            "timing_jitter_s": round(rng.uniform(policy.timing_jitter_min_s, policy.timing_jitter_max_s), 6),
        }
        identity = json.dumps(
            {"scenario_id": scenario_id, "seed": variation_seed, "params": params},
            sort_keys=True,
            separators=(",", ":"),
        )
        variations.append(
            {
                "variation_id": uuid5(NAMESPACE_URL, f"simfleet:{identity}"),
                "scenario_id": scenario_id,
                "seed": variation_seed,
                "params": params,
            }
        )
    return variations


def create_batch(
    conn: psycopg.Connection,
    scenario_id: int,
    driver_version: str,
    seed: int,
    count: int,
    policy: VariationPolicy,
    suite_name: str | None = None,
) -> UUID:
    variations = generate_variations(scenario_id, policy, seed, count)
    with conn.transaction():
        conn.execute(
            "INSERT INTO drivers (driver_version, git_sha) VALUES (%s, %s) "
            "ON CONFLICT (driver_version) DO NOTHING",
            (driver_version, "unknown"),
        )
        with conn.cursor() as cur:
            if suite_name:
                cur.execute("SELECT suite_id FROM suites WHERE name = %s", (suite_name,))
                suite_row = cur.fetchone()
                suite_id = suite_row["suite_id"] if isinstance(suite_row, dict) else suite_row[0] if suite_row else None
                if suite_id is None:
                    raise ValueError(f"unknown suite: {suite_name}")
            else:
                suite_id = None
            cur.execute(
                "INSERT INTO run_batches (suite_id, driver_version, expected_count) VALUES (%s, %s, %s) RETURNING batch_id",
                (suite_id, driver_version, count),
            )
            batch_row = cur.fetchone()
            batch_id = batch_row["batch_id"] if isinstance(batch_row, dict) else batch_row[0]
            for item in variations:
                cur.execute(
                    "INSERT INTO variations (variation_id, scenario_id, seed, params_json) "
                    "VALUES (%s, %s, %s, %s) ON CONFLICT (variation_id) DO NOTHING",
                    (item["variation_id"], scenario_id, item["seed"], Jsonb(item["params"])),
                )
                cur.execute(
                    "INSERT INTO batch_variations (batch_id, variation_id) VALUES (%s, %s)",
                    (batch_id, item["variation_id"]),
                )
    return batch_id


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario-id", type=int, required=True)
    parser.add_argument("--driver-version", required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--count", type=int, default=20)
    parser.add_argument("--batch-size", type=int, default=10)
    parser.add_argument("--suite", help="suite name to associate with the batch")
    parser.add_argument("--database-url", default="postgresql://simfleet:simfleet@localhost:55432/simfleet")
    args = parser.parse_args()
    if args.batch_size < 1:
        parser.error("--batch-size must be positive")

    policy = VariationPolicy()
    with psycopg.connect(args.database_url) as conn:
        for offset in range(0, args.count, args.batch_size):
            size = min(args.batch_size, args.count - offset)
            batch_id = create_batch(conn, args.scenario_id, args.driver_version, args.seed + offset, size, policy, args.suite)
            print(batch_id)


if __name__ == "__main__":
    main()