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

## Azure deployment

GitHub Actions deploys on pushes to `main` or by manual workflow dispatch. Configure repository variables:

- `AZURE_RESOURCE_GROUP`
- `ACR_NAME`
- `POSTGRES_NAME`
- `AZURE_LOCATION` (optional, defaults to `eastus`)

Configure secrets:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `POSTGRES_PASSWORD`

The workflow provisions PostgreSQL, ACR, Container Apps, and the worker job; builds three images; redeploys with the real URLs; and seeds the demo database.

For a local deployment:

```powershell
$postgresCredential = Get-Credential -UserName simfleet -Message "Enter a strong PostgreSQL password"
scripts/deploy.ps1 -SubscriptionId "<subscription-id>" -ResourceGroup "simfleet-rg" -AcrName "<globally-unique-acr>" -PostgresName "<globally-unique-server>" -PostgresCredential $postgresCredential
```

The demo database seeds two driver versions, a planted merge regression, and repeat-run flaky evidence.

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
