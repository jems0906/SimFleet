# SimFleet Architecture

GitHub Actions or an Azure scheduler creates replayable batches. Each batch owns an ordered set of variation IDs and a target driver version. Azure Container Apps Jobs pull independent batches, execute the same variation contract, and commit each run atomically with metrics and verdict.

PostgreSQL is the system of record. `runs`, `verdicts`, and `run_metrics` are append-only simulation evidence; `run_batches` and `batch_variations` expose completion state. The API only exposes version-controlled SQL under `db/queries`.

## Batch granularity

Small batches (10-100 variations) limit retry cost and keep job duration short. Large batches improve database efficiency but make a worker loss expensive. The current design favors short jobs and horizontally independent work.

## Queue choice

PostgreSQL currently acts as a minimal claim table. It is sufficient for local demos and low-throughput deployments. Azure Service Bus would be added before queue polling becomes a database bottleneck; each message would carry only `batch_id`, while PostgreSQL remains authoritative.
