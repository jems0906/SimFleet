$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

docker compose -f infra/docker-compose.yml up -d db

$ready = $false
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    docker exec infra-db-1 pg_isready -U simfleet -d simfleet 2>$null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $ready) { throw "SimFleet PostgreSQL did not become ready" }

Get-Content db/schema.sql -Raw | docker exec -i infra-db-1 psql -v ON_ERROR_STOP=1 -U simfleet -d simfleet

$env:DATABASE_URL = "postgresql://simfleet:simfleet@localhost:55432/simfleet"
$python = Join-Path $PSScriptRoot "..\.venv\Scripts\python.exe"
if (-not (Test-Path $python)) { $python = "python" }
& $python -m pytest pipeline/tests
