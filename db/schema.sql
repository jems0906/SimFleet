CREATE TABLE IF NOT EXISTS drivers (
    driver_version text PRIMARY KEY,
    git_sha text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS suites (
    suite_id bigserial PRIMARY KEY,
    name text NOT NULL UNIQUE,
    suite_type text NOT NULL CHECK (suite_type IN ('smoke', 'full')),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS scenarios (
    scenario_id bigserial PRIMARY KEY,
    name text NOT NULL,
    category text NOT NULL,
    base_config jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS suite_scenarios (
    suite_id bigint NOT NULL REFERENCES suites(suite_id) ON DELETE CASCADE,
    scenario_id bigint NOT NULL REFERENCES scenarios(scenario_id) ON DELETE CASCADE,
    PRIMARY KEY (suite_id, scenario_id)
);

CREATE TABLE IF NOT EXISTS variations (
    variation_id uuid PRIMARY KEY,
    scenario_id bigint NOT NULL REFERENCES scenarios(scenario_id),
    seed bigint NOT NULL,
    params_json jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS run_batches (
    batch_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    suite_id bigint REFERENCES suites(suite_id),
    driver_version text NOT NULL REFERENCES drivers(driver_version),
    expected_count integer NOT NULL CHECK (expected_count > 0),
    status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'running', 'complete', 'incomplete', 'failed')),
    created_at timestamptz NOT NULL DEFAULT now(),
    started_at timestamptz,
    completed_at timestamptz
);

CREATE TABLE IF NOT EXISTS batch_variations (
    batch_id uuid NOT NULL REFERENCES run_batches(batch_id) ON DELETE CASCADE,
    variation_id uuid NOT NULL REFERENCES variations(variation_id),
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'complete')),
    completed_at timestamptz,
    PRIMARY KEY (batch_id, variation_id)
);

CREATE TABLE IF NOT EXISTS runs (
    run_id bigserial PRIMARY KEY,
    suite_id bigint REFERENCES suites(suite_id),
    idempotency_key text NOT NULL UNIQUE,
    batch_id uuid NOT NULL REFERENCES run_batches(batch_id),
    variation_id uuid NOT NULL REFERENCES variations(variation_id),
    driver_version text NOT NULL REFERENCES drivers(driver_version),
    repeat_index integer NOT NULL DEFAULT 0 CHECK (repeat_index >= 0),
    started_at timestamptz NOT NULL,
    duration_ms integer NOT NULL CHECK (duration_ms >= 0),
    status text NOT NULL CHECK (status IN ('completed', 'failed')),
    completed_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (variation_id, driver_version, repeat_index)
);

CREATE TABLE IF NOT EXISTS run_metrics (
    run_id bigint NOT NULL REFERENCES runs(run_id) ON DELETE CASCADE,
    metric_name text NOT NULL,
    metric_value double precision NOT NULL,
    PRIMARY KEY (run_id, metric_name)
);

CREATE TABLE IF NOT EXISTS verdicts (
    run_id bigint PRIMARY KEY REFERENCES runs(run_id) ON DELETE CASCADE,
    passed boolean NOT NULL,
    failure_category text
);

ALTER TABLE run_batches ADD COLUMN IF NOT EXISTS suite_id bigint REFERENCES suites(suite_id);
ALTER TABLE runs ADD COLUMN IF NOT EXISTS suite_id bigint REFERENCES suites(suite_id);

CREATE INDEX IF NOT EXISTS runs_version_time_idx ON runs (driver_version, completed_at);
CREATE INDEX IF NOT EXISTS variations_scenario_seed_idx ON variations (scenario_id, seed);
CREATE INDEX IF NOT EXISTS run_batches_status_idx ON run_batches (status, created_at);