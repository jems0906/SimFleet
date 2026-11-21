SELECT r.driver_version, v.failure_category, count(*) AS failure_count
FROM runs r
JOIN verdicts v USING (run_id)
WHERE NOT v.passed AND r.completed_at >= %s AND r.completed_at < %s
GROUP BY r.driver_version, v.failure_category
ORDER BY r.driver_version, failure_count DESC, v.failure_category;