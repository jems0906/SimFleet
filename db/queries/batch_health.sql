SELECT b.batch_id, b.driver_version, b.status, b.expected_count,
       count(*) FILTER (WHERE bv.status = 'complete') AS completed_count,
       count(*) FILTER (WHERE bv.status <> 'complete') AS missing_count,
       count(r.run_id) FILTER (WHERE r.status = 'failed') AS failed_run_count,
       b.created_at, b.started_at, b.completed_at
FROM run_batches b
LEFT JOIN batch_variations bv USING (batch_id)
LEFT JOIN runs r ON r.batch_id = b.batch_id AND r.variation_id = bv.variation_id
GROUP BY b.batch_id
ORDER BY b.created_at DESC;