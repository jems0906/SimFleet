# Cost and Scale Notes

These estimates assume managed PostgreSQL, Container Apps Jobs, 5-second simulation runs, and 1-minute batch windows. Storage assumes roughly 1 KB of metrics/verdict metadata per run plus variation and audit data.

| Runs | Replicas | PostgreSQL shape | Monthly compute/storage note | Required change |
|---|---:|---|---|---|
| 1K | 1-20 | Burstable, 10-20 GB | Job cost is negligible; database dominates | None |
| 100K | 20-100 | 2-4 vCPU, 20-100 GB | Partition run tables or archive cold history | Add Service Bus and batch-aware claims |
| 10M | 100+ | Dedicated 8+ vCPU, 500 GB+ | Worker burst and database writes dominate | Partition by month, async metric rollups, object storage for artifacts |

At 1K runs, fixed database and dashboard cost dominates. At 100K, index maintenance and percentile queries become the first bottleneck. At 10M, raw row aggregation should use partitioned tables and precomputed summaries. Summary tables must retain source-window metadata and invalidation rules for late arrivals.
