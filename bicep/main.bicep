// Main Bicep template for Azure Search BCDR setup
targetScope = 'resourceGroup'

@description('Name of the project (3-10 characters) - used as prefix for all resources. Use lowercase letters and numbers only, no spaces or special characters.')
@minLength(3)
@maxLength(10)
param projectName string

@description('Primary Azure region for deployment (e.g., westus2, eastus2, westus3)')
param primaryRegion string

@description('Secondary Azure region for deployment (e.g., westus2, eastus2, westus3)')
param secondaryRegion string

@description('Azure Search service SKU')
@allowed([
  'basic'
  'standard'
  'standard2'
  'standard3'
])
param searchSku string

@description('Synchronization method: indexer (5-min schedule) or changefeed (real-time)')
@allowed([
  'indexer'
  'changefeed'
])
param syncMethod string = 'indexer'

@description('Unique suffix for globally unique resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Timestamp used to force deployment scripts to re-run on every deployment')
param deploymentTime string = utcNow()

// Region abbreviation mapping for storage account names (24 char limit)
var regionAbbreviations = {
  eastus: 'eus'
  eastus2: 'eus2'
  westus: 'wus'
  westus2: 'wus2'
  westus3: 'wus3'
  centralus: 'cus'
  northcentralus: 'ncus'
  westcentralus: 'wcus'
  northeurope: 'neu'
  westeurope: 'weu'
  uksouth: 'uks'
  ukwest: 'ukw'
  southeastasia: 'sea'
  eastasia: 'eas'
  australiaeast: 'aue'
  australiasoutheast: 'ause'
  japaneast: 'jpe'
  japanwest: 'jpw'
  koreacentral: 'krc'
  canadacentral: 'cac'
  canadaeast: 'cae'
  brazilsouth: 'brs'
  southafricanorth: 'san'
  southindia: 'sin'
  centralindia: 'cin'
  westindia: 'win'
  francecentral: 'frc'
  germanywestcentral: 'gwc'
  norwayeast: 'nwe'
  switzerlandnorth: 'chn'
  uaenorth: 'uan'
}

// Get abbreviated region names for storage accounts
var primaryRegionAbbr = regionAbbreviations[?primaryRegion] ?? replace(primaryRegion, '-', '')
var secondaryRegionAbbr = regionAbbreviations[?secondaryRegion] ?? replace(secondaryRegion, '-', '')

// Variables
var primarySearchName = '${projectName}-search-${primaryRegion}-${uniqueSuffix}'
var secondarySearchName = '${projectName}-search-${secondaryRegion}-${uniqueSuffix}'
var primaryFunctionName = '${projectName}-func-${primaryRegion}-${uniqueSuffix}'
var secondaryFunctionName = '${projectName}-func-${secondaryRegion}-${uniqueSuffix}'

// Storage account names use abbreviated regions to stay within 24-character limit
// Format: {projectName}st{regionAbbr}{uniqueSuffix(4)}
// Example: "bcdrtest" + "st" + "scus" + "1a2b" = "bcdrtestscus1a2b" (16 chars)
var primaryStorageName = toLower('${projectName}st${primaryRegionAbbr}${substring(uniqueSuffix, 0, 4)}')
var secondaryStorageName = toLower('${projectName}st${secondaryRegionAbbr}${substring(uniqueSuffix, 0, 4)}')
var frontDoorName = '${projectName}-fd-${uniqueSuffix}'

// Deploy primary Azure Search service
module primarySearch 'modules/search.bicep' = {
  name: 'primarySearch'
  params: {
    searchServiceName: primarySearchName
    location: primaryRegion
    sku: searchSku
  }
}

// Deploy secondary Azure Search service
module secondarySearch 'modules/search.bicep' = {
  name: 'secondarySearch'
  params: {
    searchServiceName: secondarySearchName
    location: secondaryRegion
    sku: searchSku
  }
}

// Deploy primary storage account
module primaryStorage 'modules/storage.bicep' = {
  name: 'primaryStorage'
  params: {
    storageAccountName: primaryStorageName
    location: primaryRegion
  }
}

// Deploy secondary storage account
module secondaryStorage 'modules/storage.bicep' = {
  name: 'secondaryStorage'
  params: {
    storageAccountName: secondaryStorageName
    location: secondaryRegion
  }
}

// Deploy primary function app
module primaryFunction 'modules/function.bicep' = {
  name: 'primaryFunction'
  params: {
    functionAppName: primaryFunctionName
    location: primaryRegion
    storageAccountName: primaryStorageName
    searchServiceName: primarySearchName
    searchServiceKey: primarySearch.outputs.adminKey
    regionIdentifier: primaryRegion
  }
  dependsOn: [
    primaryStorage
  ]
}

// Deploy secondary function app
module secondaryFunction 'modules/function.bicep' = {
  name: 'secondaryFunction'
  params: {
    functionAppName: secondaryFunctionName
    location: secondaryRegion
    storageAccountName: secondaryStorageName
    searchServiceName: secondarySearchName
    searchServiceKey: secondarySearch.outputs.adminKey
    regionIdentifier: secondaryRegion
  }
  dependsOn: [
    secondaryStorage
  ]
}

// Deploy Azure Front Door
module frontDoor 'modules/frontdoor.bicep' = {
  name: 'frontDoor'
  params: {
    frontDoorName: frontDoorName
    primaryFunctionHostname: '${primaryFunctionName}.azurewebsites.net'
    secondaryFunctionHostname: '${secondaryFunctionName}.azurewebsites.net'
  }
  dependsOn: [
    primaryFunction
    secondaryFunction
  ]
}

// Deploy Cosmos DB for data synchronization
module cosmosDb 'modules/cosmosdb.bicep' = {
  name: 'cosmosDb'
  params: {
    location: primaryRegion
    projectName: projectName
    uniqueSuffix: uniqueSuffix
  }
}

// Populate Cosmos DB with 50 sample products
module cosmosDataPopulation 'modules/cosmosdb-data-population.bicep' = {
  name: 'cosmosDataPopulation'
  params: {
    location: primaryRegion
    cosmosAccountName: cosmosDb.outputs.cosmosAccountName
    cosmosDatabaseName: cosmosDb.outputs.cosmosDatabaseName
    cosmosContainerName: cosmosDb.outputs.cosmosContainerName
  }
}

// Option 1: Configure indexers (scheduled sync every 5 minutes)
module indexerSync 'modules/search-indexer-sync.bicep' = if (syncMethod == 'indexer') {
  name: 'indexerSync'
  params: {
    location: primaryRegion
    primarySearchName: primarySearchName
    secondarySearchName: secondarySearchName
    cosmosAccountName: cosmosDb.outputs.cosmosAccountName
    cosmosDatabaseName: cosmosDb.outputs.cosmosDatabaseName
    cosmosContainerName: cosmosDb.outputs.cosmosContainerName
    deploymentTime: deploymentTime
  }
  dependsOn: [
    primarySearch
    secondarySearch
    cosmosDataPopulation
  ]
}

// Option 2: Configure change feed sync (real-time)
module changefeedSync 'modules/search-changefeed-sync.bicep' = if (syncMethod == 'changefeed') {
  name: 'changefeedSync'
  params: {
    location: primaryRegion
    primarySearchName: primarySearchName
    secondarySearchName: secondarySearchName
    primaryFunctionName: primaryFunctionName
    secondaryFunctionName: secondaryFunctionName
    cosmosAccountName: cosmosDb.outputs.cosmosAccountName
    deploymentTime: deploymentTime
  }
  dependsOn: [
    primarySearch
    secondarySearch
    primaryFunction
    secondaryFunction
    cosmosDataPopulation
  ]
}

// Deploy function code to primary function app
module primaryFunctionCodeDeploy 'modules/function-code-deploy.bicep' = {
  name: 'primaryFunctionCodeDeploy'
  params: {
    functionAppName: primaryFunctionName
    location: primaryRegion
    resourceGroupName: resourceGroup().name
    scriptIdentity: 'primary'
  }
  dependsOn: [
    primaryFunction
    indexerSync
    changefeedSync
  ]
}

// Deploy function code to secondary function app
module secondaryFunctionCodeDeploy 'modules/function-code-deploy.bicep' = {
  name: 'secondaryFunctionCodeDeploy'
  params: {
    functionAppName: secondaryFunctionName
    location: secondaryRegion
    resourceGroupName: resourceGroup().name
    scriptIdentity: 'secondary'
  }
  dependsOn: [
    secondaryFunction
    indexerSync
    changefeedSync
  ]
}

// Outputs
output frontDoorEndpoint string = frontDoor.outputs.frontDoorEndpointUrl
output frontDoorEndpointName string = split(frontDoor.outputs.frontDoorEndpointHostname, '.')[0]
output frontDoorProfileName string = frontDoorName
output primarySearchEndpoint string = primarySearch.outputs.searchEndpoint
output secondarySearchEndpoint string = secondarySearch.outputs.searchEndpoint
output primarySearchName string = primarySearchName
output secondarySearchName string = secondarySearchName
output primaryFunctionUrl string = 'https://${primaryFunctionName}.azurewebsites.net'
output secondaryFunctionUrl string = 'https://${secondaryFunctionName}.azurewebsites.net'
output primaryFunctionName string = primaryFunctionName
output secondaryFunctionName string = secondaryFunctionName
output frontendUrl string = 'file:///${replace(deployment().name, '\\', '/')}/frontend/index.html'
output cosmosAccountName string = cosmosDb.outputs.cosmosAccountName
output syncMethod string = syncMethod
