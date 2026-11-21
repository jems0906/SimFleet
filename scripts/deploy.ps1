param(
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $AcrName,
    [Parameter(Mandatory)] [string] $PostgresName,
    [Parameter(Mandatory)] [PSCredential] $PostgresCredential,
    [string] $Location = "eastus"
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)
$plainPostgresPassword = $PostgresCredential.GetNetworkCredential().Password

az account set --subscription $SubscriptionId
az group create --name $ResourceGroup --location $Location | Out-Null

$first = az deployment group create `
    --resource-group $ResourceGroup `
    --template-file infra/azure/container-apps.bicep `
    --parameters acrName=$AcrName postgresName=$PostgresName postgresPassword=$plainPostgresPassword `
    --query properties.outputs -o json | ConvertFrom-Json

$tag = (git rev-parse --short HEAD)

az acr build --registry $AcrName --image "simfleet-api:$tag" --file pipeline/Dockerfile.api .
az acr build --registry $AcrName --image "simfleet-worker:$tag" --file pipeline/Dockerfile.worker .

$apiUrl = $first.apiUrl.value
$dashboardUrl = $first.dashboardUrl.value
az acr build --registry $AcrName --image "simfleet-dashboard:$tag" --build-arg "VITE_API_URL=$apiUrl" --file frontend/Dockerfile frontend

$acrServer = $first.acrLoginServer.value
az deployment group create `
    --resource-group $ResourceGroup `
    --template-file infra/azure/container-apps.bicep `
    --parameters acrName=$AcrName postgresName=$PostgresName postgresPassword=$plainPostgresPassword `
      apiImage="$acrServer/simfleet-api:$tag" `
      workerImage="$acrServer/simfleet-worker:$tag" `
      dashboardImage="$acrServer/simfleet-dashboard:$tag" `
      dashboardUrl=$dashboardUrl

$env:PGPASSWORD = $plainPostgresPassword
$postgresHost = "$PostgresName.postgres.database.azure.com"
psql "host=$postgresHost port=5432 dbname=simfleet user=simfleet sslmode=require" -v ON_ERROR_STOP=1 -f db/schema.sql
psql "host=$postgresHost port=5432 dbname=simfleet user=simfleet sslmode=require" -v ON_ERROR_STOP=1 -f db/seed/demo.sql

Write-Host "API: $apiUrl"
Write-Host "Dashboard: $dashboardUrl"
