WITH per_variation AS (
    SELECT r.driver_version, va.scenario_id, va.seed,
           count(*) AS repeat_count,
           count(DISTINCT v.passed) AS distinct_outcomes
    FROM runs r
    JOIN verdicts v USING (run_id)
    JOIN variations va USING (variation_id)
    WHERE r.driver_version = %s AND r.completed_at >= %s AND r.completed_at < %s
    GROUP BY r.driver_version, va.scenario_id, va.seed
    HAVING count(*) > 1
)
SELECT s.scenario_id, s.name, s.category,
       count(*) AS repeated_seed_count,
       count(*) FILTER (WHERE distinct_outcomes > 1) AS disagreeing_seed_count,
       round(count(*) FILTER (WHERE distinct_outcomes > 1)::numeric / count(*), 4) AS disagreement_rate
FROM per_variation p
JOIN scenarios s USING (scenario_id)
GROUP BY s.scenario_id, s.name, s.category
HAVING count(*) FILTER (WHERE distinct_outcomes > 1) > 0
ORDER BY disagreement_rate DESC, s.scenario_id;