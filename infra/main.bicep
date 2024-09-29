targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Id of the user or app to assign application roles')
param principalId string = ''

param apimServiceName string = ''
param applicationInsightsDashboardName string = ''
param applicationInsightsName string = ''
param containerAppsEnvironmentName string = ''
param containerRegistryName string = ''
param keyVaultName string = ''
param logAnalyticsName string = ''
param storageAccountName string = ''
param storageContainerName string = ''
param appServicePlanName string = ''

// Set to true to use Azure API Management
@description('Flag to use Azure API Management to mediate the calls between the Web frontend and the backend API')
param useAPIM bool = false

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

/////////// Common ///////////

// Store secrets in a keyvault
module keyVault './core/security/keyvault.bicep' = {
  name: 'keyvault'
  scope: rg
  params: {
    name: !empty(keyVaultName) ? keyVaultName : '${abbrs.keyVaultVaults}${resourceToken}'
    location: location
    tags: tags
    principalId: principalId
  }
}

// Monitor application with Azure Monitor
module monitoring './core/monitor/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    tags: tags
    logAnalyticsName: !empty(logAnalyticsName)
      ? logAnalyticsName
      : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: !empty(applicationInsightsName)
      ? applicationInsightsName
      : '${abbrs.insightsComponents}${resourceToken}'
    applicationInsightsDashboardName: !empty(applicationInsightsDashboardName)
      ? applicationInsightsDashboardName
      : '${abbrs.portalDashboards}${resourceToken}'
  }
}

// Container apps host (including container registry)
module containerApps './core/host/container-apps.bicep' = {
  name: 'container-apps'
  scope: rg
  params: {
    name: 'app'
    containerAppsEnvironmentName: !empty(containerAppsEnvironmentName)
      ? containerAppsEnvironmentName
      : '${abbrs.appManagedEnvironments}${resourceToken}'
    containerRegistryName: !empty(containerRegistryName)
      ? containerRegistryName
      : '${abbrs.containerRegistryRegistries}${resourceToken}'
    location: location
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
  }
}

module storageAccount './core/storage/storage-account.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
    allowBlobPublicAccess: true
    location: location
    containers: [
      {
        name: !empty(storageContainerName) ? storageContainerName : 'stc${resourceToken}'
        publicAccess: 'Blob'
      }
    ]
  }
}

// Creates Azure API Management (APIM) service to mediate the requests between the frontend and the backend API
module apim './core/gateway/apim.bicep' = if (useAPIM) {
  name: 'apim'
  scope: rg
  params: {
    name: !empty(apimServiceName) ? apimServiceName : '${abbrs.apiManagementService}${resourceToken}'
    location: location
    tags: tags
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    sku: 'Developer'
  }
}

/////////// Portal API ///////////

module appServicePlan './core/host/appserviceplan.bicep' = {
  name: 'appserviceplan'
  scope: rg
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
    location: location
    tags: tags
    sku: {
      name: 'Y1'
      tier: 'Dynamic'
    }
  }
}

// App outputs
output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.applicationInsightsConnectionString
output APPLICATIONINSIGHTS_NAME string = monitoring.outputs.applicationInsightsName

output AZURE_CONTAINER_ENVIRONMENT_NAME string = containerApps.outputs.environmentName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerApps.outputs.registryLoginServer
output AZURE_CONTAINER_REGISTRY_NAME string = containerApps.outputs.registryName
output AZURE_KEY_VAULT_ENDPOINT string = keyVault.outputs.endpoint
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId

output USE_APIM bool = useAPIM

output STORAGE_ACCOUNT_NAME string = storageAccount.outputs.name
output STORAGE_CONTAINER_NAME string = storageContainerName
