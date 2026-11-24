-- Repeatable demo dataset: v1 baseline, v2 merge regression, and a flaky crossing.
INSERT INTO suites (name, suite_type) VALUES ('pr-smoke', 'smoke'), ('nightly-full', 'full')
ON CONFLICT (name) DO NOTHING;

INSERT INTO drivers (driver_version, git_sha)
VALUES ('v1', 'demo-v1'), ('v2', 'demo-v2')
ON CONFLICT (driver_version) DO UPDATE SET git_sha = EXCLUDED.git_sha;

WITH ranked_scenarios AS (
  SELECT scenario_id, min(scenario_id) OVER (PARTITION BY name) AS canonical_id,
         row_number() OVER (PARTITION BY name ORDER BY scenario_id) AS row_number
  FROM scenarios
), duplicates AS (
  SELECT scenario_id, canonical_id FROM ranked_scenarios WHERE row_number > 1
)
DELETE FROM suite_scenarios ss USING duplicates d WHERE ss.scenario_id = d.scenario_id;

WITH ranked_scenarios AS (
  SELECT scenario_id, min(scenario_id) OVER (PARTITION BY name) AS canonical_id,
         row_number() OVER (PARTITION BY name ORDER BY scenario_id) AS row_number
  FROM scenarios
), duplicates AS (
  SELECT scenario_id, canonical_id FROM ranked_scenarios WHERE row_number > 1
)
UPDATE variations v SET scenario_id = d.canonical_id
FROM duplicates d WHERE v.scenario_id = d.scenario_id;

WITH ranked_scenarios AS (
  SELECT scenario_id,
         row_number() OVER (PARTITION BY name ORDER BY scenario_id) AS row_number
  FROM scenarios
)
DELETE FROM scenarios s USING ranked_scenarios r
WHERE s.scenario_id = r.scenario_id AND r.row_number > 1;

CREATE UNIQUE INDEX IF NOT EXISTS scenarios_name_unique_idx ON scenarios (name);

INSERT INTO scenarios (name, category, base_config)
VALUES
  ('urban_merge_01', 'merge', '{"road":"urban", "lanes":3}'::jsonb),
  ('crosswalk_01', 'crosswalk', '{"pedestrians":4}'::jsonb),
  ('intersection_01', 'intersection', '{"traffic":"dense"}'::jsonb)
ON CONFLICT (name) DO NOTHING;

INSERT INTO suite_scenarios (suite_id, scenario_id)
SELECT suite_id, scenario_id FROM suites, scenarios
WHERE (suites.suite_type = 'smoke' AND scenarios.category IN ('merge', 'crosswalk'))
   OR suites.suite_type = 'full'
ON CONFLICT DO NOTHING;

DO $$
DECLARE
  v_scenario record;
  v_variation uuid;
  v_batch uuid;
  v_run bigint;
  v_seed bigint;
  v_pass boolean;
  v_metric double precision;
  v_version text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('simfleet-demo-seed'));
  FOREACH v_version IN ARRAY ARRAY['v1', 'v2'] LOOP
    FOR v_scenario IN SELECT * FROM scenarios LOOP
      v_batch := NULL;

      FOR v_seed IN 1..60 LOOP
        IF NOT EXISTS (
          SELECT 1 FROM runs
          WHERE idempotency_key = 'demo:' || v_version || ':' || v_scenario.scenario_id || ':' || v_seed
        ) THEN
          IF v_batch IS NULL THEN
            INSERT INTO run_batches (driver_version, expected_count, status, started_at, completed_at)
            VALUES (v_version, 60, 'complete', now() - interval '1 day', now() - interval '23 hours')
            RETURNING batch_id INTO v_batch;
          END IF;

          v_variation := gen_random_uuid();
          INSERT INTO variations (variation_id, scenario_id, seed, params_json)
          VALUES (v_variation, v_scenario.scenario_id, v_seed,
            jsonb_build_object('speed_scale', 0.9 + (v_seed % 10) * 0.02,
                               'spawn_offset_m', (v_seed % 5) - 2.0,
                               'timing_jitter_s', (v_seed % 4) * 0.1));
          INSERT INTO batch_variations (batch_id, variation_id, status, completed_at)
          VALUES (v_batch, v_variation, 'complete', now());

          IF v_scenario.category = 'merge' AND v_version = 'v2' THEN
            v_pass := v_seed <= 24;
          ELSE
            v_pass := v_seed <= 52;
          END IF;

          IF v_scenario.category = 'crosswalk' AND v_seed IN (8, 24, 37) THEN
            v_pass := ((v_seed + CASE WHEN v_version = 'v1' THEN 0 ELSE 1 END) % 2) = 0;
          END IF;

          INSERT INTO runs (idempotency_key, batch_id, variation_id, driver_version, repeat_index,
                           started_at, duration_ms, status, completed_at)
          VALUES ('demo:' || v_version || ':' || v_scenario.scenario_id || ':' || v_seed,
                  v_batch, v_variation, v_version, 0, now() - interval '1 hour',
                  900 + v_seed, 'completed', now() - interval '30 minutes')
          RETURNING run_id INTO v_run;

          INSERT INTO verdicts (run_id, passed, failure_category)
          VALUES (v_run, v_pass, CASE WHEN v_pass THEN NULL ELSE 'collision' END);

          v_metric := 0.5 + (v_seed % 20) * 0.12;
          INSERT INTO run_metrics (run_id, metric_name, metric_value)
          VALUES (v_run, 'comfort_jerk', v_metric),
                 (v_run, 'min_ttc_s', 1.5 + (v_seed % 30) * 0.1);
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;
END $$;

-- Add repeated executions for a planted flaky scenario.
DO $$
DECLARE
  v_scenario_id bigint;
  v_variation uuid;
  v_batch uuid;
  v_run bigint;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('simfleet-demo-seed'));
  SELECT scenario_id INTO v_scenario_id
  FROM scenarios WHERE name = 'urban_merge_01' LIMIT 1;

  SELECT variation_id INTO v_variation FROM variations
  WHERE scenario_id = v_scenario_id AND seed = 42 AND params_json = '{"flaky":true}'::jsonb
  ORDER BY created_at LIMIT 1;

  IF v_variation IS NULL THEN
    SELECT batch_id INTO v_batch FROM run_batches WHERE driver_version = 'v1' ORDER BY created_at LIMIT 1;
    v_variation := gen_random_uuid();
    INSERT INTO variations (variation_id, scenario_id, seed, params_json)
    VALUES (v_variation, v_scenario_id, 42, '{"flaky":true}'::jsonb);
    INSERT INTO batch_variations (batch_id, variation_id, status, completed_at)
    VALUES (v_batch, v_variation, 'complete', now())
    ON CONFLICT (batch_id, variation_id) DO NOTHING;
  ELSE
    SELECT batch_id INTO v_batch FROM batch_variations
    WHERE variation_id = v_variation ORDER BY completed_at NULLS LAST LIMIT 1;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM runs WHERE idempotency_key = 'demo:flaky-repeat-0') THEN
    INSERT INTO runs (idempotency_key, batch_id, variation_id, driver_version, repeat_index,
                      started_at, duration_ms, status, completed_at)
    VALUES ('demo:flaky-repeat-0', v_batch, v_variation, 'v1', 0,
            now() - interval '20 minutes', 950, 'completed', now() - interval '19 minutes')
    RETURNING run_id INTO v_run;
    INSERT INTO verdicts (run_id, passed, failure_category) VALUES (v_run, true, NULL);
    INSERT INTO run_metrics (run_id, metric_name, metric_value) VALUES (v_run, 'comfort_jerk', 1.1);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM runs WHERE idempotency_key = 'demo:flaky-repeat-1') THEN
    INSERT INTO runs (idempotency_key, batch_id, variation_id, driver_version, repeat_index,
                      started_at, duration_ms, status, completed_at)
    VALUES ('demo:flaky-repeat-1', v_batch, v_variation, 'v1', 1,
            now() - interval '10 minutes', 980, 'completed', now() - interval '9 minutes')
    RETURNING run_id INTO v_run;
    INSERT INTO verdicts (run_id, passed, failure_category) VALUES (v_run, false, 'race');
    INSERT INTO run_metrics (run_id, metric_name, metric_value) VALUES (v_run, 'comfort_jerk', 1.8);
  END IF;
END $$;
