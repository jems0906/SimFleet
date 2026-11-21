"""Simulation engine adapter with a reproducible local demo implementation."""

from __future__ import annotations

import importlib
import random
from dataclasses import dataclass
from typing import Any, Protocol


@dataclass(frozen=True)
class RunResult:
    status: str
    passed: bool
    failure_category: str | None
    duration_ms: int
    metrics: dict[str, float]


class ScenarioRunner(Protocol):
    def run(self, scenario: dict[str, Any], params: dict[str, Any], seed: int, driver_version: str) -> RunResult: ...


class DemoRunner:
    """Deterministic stand-in; v2 intentionally regresses the merge scenario."""

    def run(self, scenario: dict[str, Any], params: dict[str, Any], seed: int, driver_version: str) -> RunResult:
        rng = random.Random(seed)
        base_pass_probability = 0.9
        if driver_version.startswith("v2") and scenario["category"] == "merge":
            base_pass_probability = 0.52
        passed = rng.random() < base_pass_probability
        duration_ms = 900 + round(abs(params.get("spawn_offset_m", 0.0)) * 40) + seed % 121
        return RunResult(
            status="completed",
            passed=passed,
            failure_category=None if passed else "collision",
            duration_ms=duration_ms,
            metrics={"comfort_jerk": round(rng.uniform(0.1, 2.4), 4), "min_ttc_s": round(rng.uniform(0.2, 5.0), 4)},
        )


class DriveBenchRunner:
    """Adapter contract: plugin module exports run_variation(scenario, params, seed, driver_version)."""

    def __init__(self, module_name: str):
        self.module = importlib.import_module(module_name)

    def run(self, scenario: dict[str, Any], params: dict[str, Any], seed: int, driver_version: str) -> RunResult:
        result = self.module.run_variation(scenario, params, seed, driver_version)
        return RunResult(**result)


def create_runner(engine: str = "demo", plugin_module: str | None = None) -> ScenarioRunner:
    if engine == "demo":
        return DemoRunner()
    if engine == "pydrivebench" and plugin_module:
        return DriveBenchRunner(plugin_module)
    raise ValueError("SIMFLEET_ENGINE must be 'demo' or 'pydrivebench' with SIMFLEET_DRIVEBENCH_MODULE set")