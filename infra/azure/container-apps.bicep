targetScope = 'resourceGroup'

param location string = resourceGroup().location
param acrName string
param postgresAdminUser string = 'simfleet'
@secure()
param postgresPassword string
param postgresName string
param apiImage string = 'mcr.microsoft.com/appsvc/staticsite:latest'
param workerImage string = 'mcr.microsoft.com/azure-cli:latest'
param dashboardImage string = 'nginx:1.27-alpine'
param dashboardUrl string = 'http://localhost:5173'
param workerScheduleCron string = '0 2 * * *'

var postgresDatabaseName = 'simfleet'
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: false }
}

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: postgresName
  location: location
  sku: { name: 'Standard_B1ms', tier: 'Burstable' }
  properties: {
    administratorLogin: postgresAdminUser
    administratorLoginPassword: postgresPassword
    version: '16'
    storage: { storageSizeGB: 32 }
    authConfig: { activeDirectoryAuth: 'Disabled', passwordAuth: 'Enabled' }
    backup: { backupRetentionDays: 7, geoRedundantBackup: 'Disabled' }
    highAvailability: { mode: 'Disabled' }
    network: { publicNetworkAccess: 'Enabled' }
  }
}

resource postgresDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: postgres
  name: postgresDatabaseName
  properties: { charset: 'UTF8', collation: 'en_US.utf8' }
}

resource allowDeployment 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: postgres
  name: 'allow-deployment-source'
  properties: { startIpAddress: '0.0.0.0', endIpAddress: '255.255.255.255' }
}

resource environment 'Microsoft.App/managedEnvironments@2024-10-02-preview' = {
  name: 'simfleet-env'
  location: location
  properties: {}
}

var databaseUrl = 'postgresql://${postgresAdminUser}:${postgresPassword}@${postgresName}.postgres.database.azure.com:5432/${postgresDatabaseName}?sslmode=require'

resource api 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: 'simfleet-api'
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      ingress: { external: true, targetPort: 8000, transport: 'http' }
      registries: [{ server: registry.properties.loginServer, identity: 'system-enforced' }]
    }
    template: {
      containers: [{ name: 'api', image: apiImage, resources: { cpu: json('0.25'), memory: '0.5Gi' }, env: [
        { name: 'DATABASE_URL', value: databaseUrl }
        { name: 'CORS_ORIGINS', value: dashboardUrl }
      ] }]
      scale: { minReplicas: 1, maxReplicas: 3 }
    }
  }
}

resource worker 'Microsoft.App/jobs@2024-10-02-preview' = {
  name: 'simfleet-worker'
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    environmentId: environment.id
    configuration: {
      triggerType: 'Schedule'
      scheduleTriggerConfig: { cronExpression: workerScheduleCron, parallelism: 20, replicaCompletionCount: 1 }
      replicaTimeout: 900
      replicaRetryLimit: 3
      registries: [{ server: registry.properties.loginServer, identity: 'system-enforced' }]
    }
    template: {
      containers: [{ name: 'worker', image: workerImage, resources: { cpu: json('0.25'), memory: '0.5Gi' }, env: [
        { name: 'DATABASE_URL', value: databaseUrl }
        { name: 'SIMFLEET_ENGINE', value: 'demo' }
      ] }]
    }
  }
}

resource dashboard 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: 'simfleet-dashboard'
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      ingress: { external: true, targetPort: 80, transport: 'http' }
      registries: [{ server: registry.properties.loginServer, identity: 'system-enforced' }]
    }
    template: {
      containers: [{ name: 'dashboard', image: dashboardImage, resources: { cpu: json('0.25'), memory: '0.5Gi' } }]
      scale: { minReplicas: 1, maxReplicas: 2 }
    }
  }
}

resource apiAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, api.id, acrPullRoleId)
  scope: registry
  properties: { principalId: api.identity.principalId, principalType: 'ServicePrincipal', roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId) }
}

resource workerAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, worker.id, acrPullRoleId)
  scope: registry
  properties: { principalId: worker.identity.principalId, principalType: 'ServicePrincipal', roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId) }
}

resource dashboardAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, dashboard.id, acrPullRoleId)
  scope: registry
  properties: { principalId: dashboard.identity.principalId, principalType: 'ServicePrincipal', roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId) }
}

output acrLoginServer string = registry.properties.loginServer
output apiUrl string = 'https://${api.properties.configuration.ingress.fqdn}'
output dashboardUrl string = 'https://${dashboard.properties.configuration.ingress.fqdn}'
output postgresHost string = postgres.properties.fullyQualifiedDomainName
output postgresDatabase string = postgresDatabaseName
