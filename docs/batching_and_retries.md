# Batching and Retry Design

A variation has a deterministic UUID derived from scenario, seed, and parameters. Batch creation is reproducible. A run uses `variation_id + driver_version + repeat_index` as an idempotency key.

`persist_result` uses `ON CONFLICT (idempotency_key) DO NOTHING`, writes metrics/verdict once, and marks the variation complete. Retried workers therefore only process rows whose `batch_variations.status` is not `complete`.

A simulated crash is triggered with `--fail-after N`. Already persisted rows survive; the batch is marked `incomplete`; rerunning the same batch skips completed variations. Unexpected runner failures leave the batch incomplete rather than converting missing work into successful work.

Trade-off: a database claim table is simpler than a separate queue, but polling contention grows with replica count. Service Bus should replace queue delivery before this becomes the hot path.
