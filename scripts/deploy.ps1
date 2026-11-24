param(
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $AcrName,
    [Parameter(Mandatory)] [string] $PostgresName,
    [Parameter(Mandatory)] [PSCredential] $PostgresCredential,
    [string] $Location = "northcentralus",
    [Parameter(Mandatory)] [PSCredential] $ApiCredential,
    [string] $EntraTenantId = "",
    [string] $EntraClientId = "",
    [string[]] $EntraAllowedUserIds = @(),
    [PSCredential] $EntraCredential
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)
$plainPostgresPassword = $PostgresCredential.GetNetworkCredential().Password
$plainApiKey = $ApiCredential.GetNetworkCredential().Password
$plainEntraSecret = if ($EntraCredential) { $EntraCredential.GetNetworkCredential().Password } else { "" }
if ($EntraClientId -or $EntraTenantId -or $EntraCredential -or $EntraAllowedUserIds.Count) {
    if (-not ($EntraClientId -and $EntraTenantId -and $plainEntraSecret -and $EntraAllowedUserIds.Count)) {
        throw "Entra tenant, client, credential, and allowed user IDs must be provided together"
    }
}

az account set --subscription $SubscriptionId
az group create --name $ResourceGroup --location $Location | Out-Null

az acr show --name $AcrName --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    az acr create --name $AcrName --resource-group $ResourceGroup --location $Location --sku Basic --admin-enabled true --output none
    if ($LASTEXITCODE -ne 0) { throw "Registry creation failed" }
}

$tag = (git rev-parse --short HEAD)
$acrServer = az acr show --name $AcrName --query loginServer -o tsv
$acrCredentials = az acr credential show --name $AcrName | ConvertFrom-Json
$acrUsername = $acrCredentials.username
$acrPassword = $acrCredentials.passwords[0].value
"$acrPassword`n" | docker login $acrServer --username $acrUsername --password-stdin
if ($LASTEXITCODE -ne 0) { throw "Docker login to ACR failed" }

docker build --file pipeline/Dockerfile.api --tag "$acrServer/simfleet-api:$tag" .
if ($LASTEXITCODE -ne 0) { throw "API image build failed" }
docker build --file pipeline/Dockerfile.worker --tag "$acrServer/simfleet-worker:$tag" .
if ($LASTEXITCODE -ne 0) { throw "Worker image build failed" }

docker build --file frontend/Dockerfile --tag "$acrServer/simfleet-dashboard:$tag" frontend
if ($LASTEXITCODE -ne 0) { throw "Dashboard image build failed" }

docker push "$acrServer/simfleet-api:$tag"
if ($LASTEXITCODE -ne 0) { throw "API image push failed" }
docker push "$acrServer/simfleet-worker:$tag"
if ($LASTEXITCODE -ne 0) { throw "Worker image push failed" }
docker push "$acrServer/simfleet-dashboard:$tag"
if ($LASTEXITCODE -ne 0) { throw "Dashboard image push failed" }

$authEnabled = az containerapp auth show --name simfleet-dashboard --resource-group $ResourceGroup --query platform.enabled -o tsv 2>$null
if ($authEnabled -eq "true" -and -not $EntraClientId) { throw "Refusing to remove existing Entra settings" }
$allowedUserIdsJson = ConvertTo-Json -InputObject @($EntraAllowedUserIds) -Compress
$deployment = az deployment group create `
    --resource-group $ResourceGroup `
    --template-file infra/azure/container-apps.bicep `
    --parameters location=$Location acrName=$AcrName postgresName=$PostgresName postgresPassword=$plainPostgresPassword apiKey=$plainApiKey `
      apiImage="$acrServer/simfleet-api:$tag" `
      workerImage="$acrServer/simfleet-worker:$tag" `
      dashboardImage="$acrServer/simfleet-dashboard:$tag" `
    entraTenantId=$EntraTenantId entraClientId=$EntraClientId `
    entraClientSecret=$plainEntraSecret entraAllowedUserIds=$allowedUserIdsJson `
    --query properties.outputs -o json
if ($LASTEXITCODE -ne 0) { throw "Application deployment failed" }
$outputs = $deployment | ConvertFrom-Json
$apiUrl = $outputs.apiUrl.value
$dashboardUrl = $outputs.dashboardUrl.value

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
