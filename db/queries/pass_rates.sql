SELECT r.driver_version, s.category,
       count(*) AS run_count,
       count(*) FILTER (WHERE v.passed) AS passed_count,
       round(count(*) FILTER (WHERE v.passed)::numeric / NULLIF(count(*), 0), 4) AS pass_rate
FROM runs r
JOIN verdicts v USING (run_id)
JOIN variations va USING (variation_id)
JOIN scenarios s USING (scenario_id)
WHERE r.completed_at >= %s AND r.completed_at < %s
GROUP BY r.driver_version, s.category
ORDER BY r.driver_version, s.category;