// Azure Search service module
@description('Name of the Azure AI Search service')
param searchServiceName string

@description('Location for the search service')
param location string

@description('SKU of the search service')
@allowed([
  'basic'
  'standard'
  'standard2'
  'standard3'
])
param sku string = 'basic'

@description('Replica count')
@minValue(1)
@maxValue(12)
param replicaCount int = 1

@description('Partition count')
@minValue(1)
@maxValue(12)
param partitionCount int = 1

// Azure Search service
resource searchService 'Microsoft.Search/searchServices@2025-05-01' = {
  name: searchServiceName
  location: location
  sku: {
    name: sku
  }
  properties: {
    replicaCount: replicaCount
    partitionCount: partitionCount
    hostingMode: 'Default'
    publicNetworkAccess: 'enabled'
    networkRuleSet: {
      ipRules: []
    }
    encryptionWithCmk: {
      enforcement: 'Unspecified'
    }
    disableLocalAuth: false
    authOptions: {
      apiKeyOnly: {}
    }
  }
}

// Outputs
output searchServiceId string = searchService.id
output searchServiceName string = searchService.name
output searchEndpoint string = 'https://${searchService.name}.search.windows.net'
@secure()
output adminKey string = searchService.listAdminKeys().primaryKey
