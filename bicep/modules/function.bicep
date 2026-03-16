// Azure Function App module
@description('Name of the function app')
param functionAppName string

@description('Location for the function app')
param location string

@description('Name of the storage account for function app')
param storageAccountName string

@description('Name of the Azure Search service')
param searchServiceName string

@description('Admin key for the Azure Search service')
@secure()
param searchServiceKey string

@description('Region identifier for responses')
param regionIdentifier string

// Get reference to existing storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// App Service Plan (Consumption/Dynamic Y1 - Serverless)
resource hostingPlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: '${functionAppName}-plan'
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: false
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${functionAppName}-insights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    RetentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'SearchServiceName'
          value: searchServiceName
        }
        {
          name: 'SearchServiceEndpoint'
          value: 'https://${searchServiceName}.search.windows.net'
        }
        {
          name: 'SearchServiceKey'
          value: searchServiceKey
        }
        {
          name: 'SearchIndexName'
          value: 'products-index'
        }
        {
          name: 'RegionIdentifier'
          value: regionIdentifier
        }
      ]
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
  }
}

// Outputs
output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output functionAppDefaultHostname string = functionApp.properties.defaultHostName
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
