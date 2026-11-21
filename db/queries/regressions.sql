WITH rates AS (
    SELECT s.scenario_id, s.name, s.category, r.driver_version,
           count(*) AS run_count,
           count(*) FILTER (WHERE v.passed) AS passed_count,
           count(*) FILTER (WHERE NOT v.passed) AS failed_count,
           count(*) FILTER (WHERE v.passed)::double precision / NULLIF(count(*), 0) AS pass_rate
    FROM runs r
    JOIN verdicts v USING (run_id)
    JOIN variations va USING (variation_id)
    JOIN scenarios s USING (scenario_id)
    WHERE r.driver_version IN (%s, %s) AND r.completed_at >= %s AND r.completed_at < %s
    GROUP BY s.scenario_id, s.name, s.category, r.driver_version
), paired AS (
    SELECT old.scenario_id, old.name, old.category,
           old.run_count AS baseline_run_count, new.run_count AS candidate_run_count,
           old.pass_rate AS baseline_pass_rate, new.pass_rate AS candidate_pass_rate,
           old.passed_count AS baseline_passed, old.failed_count AS baseline_failed,
           new.passed_count AS candidate_passed, new.failed_count AS candidate_failed
    FROM rates old JOIN rates new USING (scenario_id, name, category)
    WHERE old.driver_version = %s AND new.driver_version = %s
), scored AS (
    SELECT *, baseline_pass_rate - candidate_pass_rate AS pass_rate_drop,
      (baseline_pass_rate - candidate_pass_rate) /
      NULLIF(sqrt(((baseline_passed + candidate_passed)::double precision /
          NULLIF(baseline_run_count + candidate_run_count, 0)) *
          (1 - (baseline_passed + candidate_passed)::double precision /
          NULLIF(baseline_run_count + candidate_run_count, 0)) *
          (1.0 / NULLIF(baseline_run_count, 0) + 1.0 / NULLIF(candidate_run_count, 0))), 0) AS z_score
    FROM paired
)
SELECT scenario_id, name, category, baseline_run_count, candidate_run_count,
       round(baseline_pass_rate::numeric, 4) AS baseline_pass_rate,
       round(candidate_pass_rate::numeric, 4) AS candidate_pass_rate,
       round(pass_rate_drop::numeric, 4) AS pass_rate_drop,
       round(z_score::numeric, 3) AS z_score
FROM scored
WHERE pass_rate_drop > 0 AND z_score >= 1.96
ORDER BY pass_rate_drop DESC, scenario_id;