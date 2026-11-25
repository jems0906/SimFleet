# SimFleet

SimFleet is a distributed simulation pipeline that executes reproducible DriveBench-style scenario variations, preserves partial progress in PostgreSQL, and serves SQL-defined regression analytics.

## Run locally

```powershell
docker compose -f infra/docker-compose.yml up -d db
docker compose -f infra/docker-compose.yml up --build api dashboard
```

Open `http://localhost:5173`. API docs: `http://localhost:8000/docs`.

## Create and execute a demo batch

```powershell
$batch = docker compose -f infra/docker-compose.yml run --rm worker python -m pipeline.generate_batches --scenario-id 1 --driver-version v2 --seed 100 --count 20 --batch-size 20
docker compose -f infra/docker-compose.yml run --rm worker python -m pipeline.worker.main --batch-id $batch
```

Simulate a partial worker loss:

```powershell
docker compose -f infra/docker-compose.yml run --rm worker python -m pipeline.worker.main --batch-id $batch --fail-after 5
```

Rerun the command without `--fail-after`; only uncompleted variations execute.

## Tests

In VS Code, run **Tasks: Run Test Task** and select `SimFleet: Test`, or use:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test.ps1
```

The script starts PostgreSQL, applies the schema, and runs the fixture tests.

Dashboard regression tests (desktop and mobile):

```powershell
npm --prefix frontend ci
npx --prefix frontend playwright install chromium
npm --prefix frontend test
```

## Azure deployment

Current deployment mode is a public demo: the dashboard and its same-origin API proxy are publicly accessible, and Entra sign-in is deferred. The deployed dashboard data is synthetic demo data. Do not load real DriveBench results or personal, confidential, or otherwise sensitive data into this deployment. This demo is not production-ready; see [Production Readiness](docs/production-readiness.md) for the remaining controls and blockers.

GitHub Actions deploys on pushes to `main` or by manual workflow dispatch. This Azure for Students subscription currently permits North Central US and exposes Container Apps Express environments, which do not support ACA Jobs. The deployed worker is therefore a single-replica polling Container App; the Bicep Job design is not used in this subscription. Configure repository variables:

- `AZURE_RESOURCE_GROUP`
- `ACR_NAME`
- `POSTGRES_NAME`
- `AZURE_LOCATION` (optional, defaults to `northcentralus`)

Configure secrets:

- `POSTGRES_PASSWORD`
- `SIMFLEET_API_KEY`

Configure these repository variables for GitHub OIDC:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

The Azure identity needs a federated credential with subject `repo:jems0906/SimFleet:environment:production` and Contributor access scoped to the deployment resource group. The workflow uses the existing registry's admin credentials only during image pushes; keep registry administration enabled for this Student Express deployment.

The workflow builds and pushes real images before applying one infrastructure deployment; it no longer resets running apps to placeholders. Automatic deployment follows successful main-branch CI. ACR Tasks are disabled for this subscription, so image builds run on the GitHub runner. On startup, the worker applies the idempotent schema/demo seed from its packaged SQL files, so PostgreSQL does not need to be opened to GitHub runner IPs.

For a local deployment:

```powershell
$postgresCredential = Get-Credential -UserName simfleet -Message "Enter a strong PostgreSQL password"
$apiCredential = Get-Credential -UserName api -Message "Enter the API key"
scripts/deploy.ps1 -SubscriptionId "<subscription-id>" -ResourceGroup "simfleet-rg" -AcrName "<globally-unique-acr>" -PostgresName "<globally-unique-server>" -PostgresCredential $postgresCredential -ApiCredential $apiCredential
```

The demo database seeds two driver versions, a planted merge regression, and repeat-run flaky evidence.

## Production Readiness

The demo is operational, but production sign-off is still blocked on Entra tenant
permissions, real DriveBench assets, and cloud networking/recovery work. See
[the production readiness runbook](docs/production-readiness.md) for identity setup,
audit retention, restore verification, and the remaining acceptance checks.

## Completion checklist

- [x] Deterministic scenario variation generation
- [x] Idempotent, retry-safe worker writes
- [x] Mid-batch crash and incomplete-batch handling
- [x] Pass-rate, percentile, regression, flaky, failure, batch-health, and worst-trajectory SQL
- [x] Hand-computed fixture tests for SQL and 1,000-run order independence
- [x] Smoke/full suite metadata and PR CI pass-rate comments
- [x] Docker Compose local stack
- [x] Azure Container Apps and PostgreSQL deployment automation
- [x] Cost and scale, batching/retry, and SQL semantics documentation
