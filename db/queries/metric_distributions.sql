SELECT s.scenario_id, s.name, m.metric_name,
       count(*) AS run_count,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY m.metric_value) AS median,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY m.metric_value) AS p95
FROM run_metrics m
JOIN runs r USING (run_id)
JOIN variations v USING (variation_id)
JOIN scenarios s USING (scenario_id)
WHERE r.driver_version = %s AND m.metric_name = %s
  AND r.completed_at >= %s AND r.completed_at < %s
GROUP BY s.scenario_id, s.name, m.metric_name
ORDER BY s.scenario_id, m.metric_name;