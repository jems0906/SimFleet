param(
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $AcrName,
    [Parameter(Mandatory)] [string] $PostgresName,
    [Parameter(Mandatory)] [PSCredential] $PostgresCredential,
    [string] $Location = "northcentralus",
    [Parameter(Mandatory)] [PSCredential] $ApiCredential
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)
$plainPostgresPassword = $PostgresCredential.GetNetworkCredential().Password
$plainApiKey = $ApiCredential.GetNetworkCredential().Password

az account set --subscription $SubscriptionId
az group create --name $ResourceGroup --location $Location | Out-Null

$first = az deployment group create `
    --resource-group $ResourceGroup `
    --template-file infra/azure/container-apps.bicep `
    --parameters location=$Location acrName=$AcrName postgresName=$PostgresName postgresPassword=$plainPostgresPassword apiKey=$plainApiKey `
    --query properties.outputs -o json | ConvertFrom-Json

$tag = (git rev-parse --short HEAD)
$acrServer = $first.acrLoginServer.value
$acrCredentials = az acr credential show --name $AcrName | ConvertFrom-Json
$acrUsername = $acrCredentials.username
$acrPassword = $acrCredentials.passwords[0].value
"$acrPassword`n" | docker login $acrServer --username $acrUsername --password-stdin
if ($LASTEXITCODE -ne 0) { throw "Docker login to ACR failed" }

docker build --file pipeline/Dockerfile.api --tag "$acrServer/simfleet-api:$tag" .
if ($LASTEXITCODE -ne 0) { throw "API image build failed" }
docker build --file pipeline/Dockerfile.worker --tag "$acrServer/simfleet-worker:$tag" .
if ($LASTEXITCODE -ne 0) { throw "Worker image build failed" }

$apiUrl = $first.apiUrl.value
$dashboardUrl = $first.dashboardUrl.value
docker build --file frontend/Dockerfile --build-arg "VITE_API_URL=$apiUrl" --tag "$acrServer/simfleet-dashboard:$tag" frontend
if ($LASTEXITCODE -ne 0) { throw "Dashboard image build failed" }

docker push "$acrServer/simfleet-api:$tag"
if ($LASTEXITCODE -ne 0) { throw "API image push failed" }
docker push "$acrServer/simfleet-worker:$tag"
if ($LASTEXITCODE -ne 0) { throw "Worker image push failed" }
docker push "$acrServer/simfleet-dashboard:$tag"
if ($LASTEXITCODE -ne 0) { throw "Dashboard image push failed" }

az deployment group create `
    --resource-group $ResourceGroup `
    --template-file infra/azure/container-apps.bicep `
    --parameters location=$Location acrName=$AcrName postgresName=$PostgresName postgresPassword=$plainPostgresPassword apiKey=$plainApiKey `
      apiImage="$acrServer/simfleet-api:$tag" `
      workerImage="$acrServer/simfleet-worker:$tag" `
      dashboardImage="$acrServer/simfleet-dashboard:$tag" `
      dashboardUrl=$dashboardUrl

$postgresHost = "$PostgresName.postgres.database.azure.com"
$firewallRuleName = "local-deploy-$tag"
$clientIp = (Invoke-RestMethod -Uri "https://api.ipify.org").Trim()
az postgres flexible-server firewall-rule create `
    --resource-group $ResourceGroup `
    --server-name $PostgresName `
    --name $firewallRuleName `
    --start-ip-address $clientIp `
    --end-ip-address $clientIp `
    --output none
if ($LASTEXITCODE -ne 0) { throw "Temporary PostgreSQL firewall rule creation failed" }
try {
    $env:DATABASE_URL = "postgresql://simfleet:$plainPostgresPassword@$postgresHost`:5432/simfleet?sslmode=require"
    $python = Join-Path $PSScriptRoot "..\.venv\Scripts\python.exe"
    if (-not (Test-Path $python)) { $python = "python" }
    & $python -c "import os,pathlib,psycopg; c=psycopg.connect(os.environ['DATABASE_URL'],autocommit=True); c.execute(pathlib.Path('db/schema.sql').read_text(encoding='utf-8'),prepare=False); c.execute(pathlib.Path('db/seed/demo.sql').read_text(encoding='utf-8'),prepare=False); c.close()"
    if ($LASTEXITCODE -ne 0) { throw "Database schema or demo seed failed" }
}
finally {
    az postgres flexible-server firewall-rule delete --resource-group $ResourceGroup --server-name $PostgresName --name $firewallRuleName --yes --output none
}

Write-Host "API: $apiUrl"
Write-Host "Dashboard: $dashboardUrl"
