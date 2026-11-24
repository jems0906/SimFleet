targetScope = 'resourceGroup'

param location string = resourceGroup().location
param acrName string
param postgresAdminUser string = 'simfleet'
@secure()
param postgresPassword string
@secure()
param apiKey string
param postgresName string
param apiImage string = 'mcr.microsoft.com/k8se/quickstart-jobs:latest'
param workerImage string = 'mcr.microsoft.com/k8se/quickstart-jobs:latest'
param dashboardImage string = 'nginx:1.27-alpine'
param dashboardUrl string = 'http://localhost:5173'

var postgresDatabaseName = 'simfleet'

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: true }
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
  name: 'allow-azure-services'
  properties: { startIpAddress: '0.0.0.0', endIpAddress: '0.0.0.0' }
}

resource environment 'Microsoft.App/managedEnvironments@2024-10-02-preview' = {
  name: 'simfleet-env'
  location: location
  properties: {
    workloadProfiles: [{ name: 'Consumption', workloadProfileType: 'Consumption' }]
  }
}

var databaseUrl = 'postgresql://${postgresAdminUser}:${postgresPassword}@${postgresName}.postgres.database.azure.com:5432/${postgresDatabaseName}?sslmode=require'
var registryCredentials = registry.listCredentials()

var appSecrets = [
  { name: 'acr-password', value: registryCredentials.passwords[0].value }
  { name: 'database-url', value: databaseUrl }
  { name: 'api-key', value: apiKey }
]

var appRegistries = [{
  server: registry.properties.loginServer
  username: registryCredentials.username
  passwordSecretRef: 'acr-password'
}]

resource api 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: 'simfleet-api'
  location: location
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      ingress: { external: true, targetPort: 8000, transport: 'http' }
      secrets: appSecrets
      registries: appRegistries
    }
    template: {
      containers: [{ name: 'api', image: apiImage, resources: { cpu: json('0.25'), memory: '0.5Gi' }, env: [
        { name: 'DATABASE_URL', secretRef: 'database-url' }
        { name: 'SIMFLEET_API_KEY', secretRef: 'api-key' }
        { name: 'CORS_ORIGINS', value: dashboardUrl }
      ] }]
      scale: { minReplicas: 1, maxReplicas: 3 }
    }
  }
}

resource worker 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: 'simfleet-worker'
  location: location
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      secrets: appSecrets
      registries: appRegistries
    }
    template: {
      containers: [{ name: 'worker', image: workerImage, resources: { cpu: json('0.25'), memory: '0.5Gi' }, env: [
        { name: 'DATABASE_URL', secretRef: 'database-url' }
        { name: 'SIMFLEET_ENGINE', value: 'demo' }
      ], args: ['--initialize-db', '--poll-interval-seconds', '20'] }]
      scale: { minReplicas: 1, maxReplicas: 1 }
    }
  }
}

resource dashboard 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: 'simfleet-dashboard'
  location: location
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      ingress: { external: true, targetPort: 8080, transport: 'http' }
      secrets: appSecrets
      registries: appRegistries
    }
    template: {
      containers: [{ name: 'dashboard', image: dashboardImage, resources: { cpu: json('0.25'), memory: '0.5Gi' }, env: [
        { name: 'SIMFLEET_API_URL', value: 'https://${api.properties.configuration.ingress.fqdn}' }
        { name: 'SIMFLEET_API_KEY', secretRef: 'api-key' }
      ] }]
      scale: { minReplicas: 1, maxReplicas: 2 }
    }
  }
}

output acrLoginServer string = registry.properties.loginServer
output apiUrl string = 'https://${api.properties.configuration.ingress.fqdn}'
output dashboardUrl string = 'https://${dashboard.properties.configuration.ingress.fqdn}'
output postgresHost string = postgres.properties.fullyQualifiedDomainName
output postgresDatabase string = postgresDatabaseName
