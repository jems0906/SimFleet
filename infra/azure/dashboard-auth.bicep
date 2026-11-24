targetScope = 'resourceGroup'

param dashboardName string
@minLength(1)
param tenantId string
@minLength(1)
param clientId string
@minLength(1)
param allowedUserIds string[]

resource dashboard 'Microsoft.App/containerApps@2024-10-02-preview' existing = {
  name: dashboardName
}

resource authentication 'Microsoft.App/containerApps/authConfigs@2024-10-02-preview' = {
  parent: dashboard
  name: 'current'
  properties: {
    platform: { enabled: true }
    globalValidation: {
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'azureactivedirectory'
    }
    httpSettings: { requireHttps: true }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: clientId
          clientSecretSettingName: 'entra-client-secret'
          openIdIssuer: '${environment().authentication.loginEndpoint}${tenantId}/v2.0'
        }
        validation: {
          allowedAudiences: [clientId, 'api://${clientId}']
          defaultAuthorizationPolicy: {
            allowedPrincipals: { identities: allowedUserIds }
          }
        }
      }
    }
  }
}
