// Storage account module
@description('Name of the storage account')
param storageAccountName string

@description('Location for the storage account')
param location string

@description('Enable static website hosting')
param enableStaticWebsite bool = false

// Storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    accessTier: 'Hot'
  }
}

// Enable static website if requested
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = if (enableStaticWebsite) {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: [
        {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'OPTIONS']
          maxAgeInSeconds: 3600
          exposedHeaders: ['*']
          allowedHeaders: ['*']
        }
      ]
    }
  }
}

// Container for function app if not static website
resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = if (!enableStaticWebsite) {
  name: '${storageAccount.name}/default/azure-webjobs-hosts'
  properties: {
    publicAccess: 'None'
  }
}

// Outputs
output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output primaryEndpoints object = storageAccount.properties.primaryEndpoints
@secure()
output connectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
output staticWebsiteUrl string = enableStaticWebsite ? storageAccount.properties.primaryEndpoints.web : ''
