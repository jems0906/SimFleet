SELECT s.scenario_id,
       s.name,
       r.run_id,
       r.repeat_index,
       m.metric_value,
       v.passed,
       v.failure_category,
       count(*) OVER () AS run_count
FROM run_metrics m
JOIN runs r USING (run_id)
JOIN verdicts v USING (run_id)
JOIN variations va USING (variation_id)
JOIN scenarios s USING (scenario_id)
WHERE r.driver_version = %s
  AND m.metric_name = %s
  AND r.completed_at >= %s
  AND r.completed_at < %s
ORDER BY m.metric_value DESC, r.run_id
LIMIT %s;
