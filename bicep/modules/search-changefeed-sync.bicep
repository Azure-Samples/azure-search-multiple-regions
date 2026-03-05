// Configure search indexes and change feed function for Option 2
param primarySearchName string
param secondarySearchName string
param primaryFunctionName string
param secondaryFunctionName string
param cosmosAccountName string
param location string
param deploymentTime string

resource primarySearch 'Microsoft.Search/searchServices@2025-05-01' existing = {
  name: primarySearchName
}

resource secondarySearch 'Microsoft.Search/searchServices@2025-05-01' existing = {
  name: secondarySearchName
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' existing = {
  name: cosmosAccountName
}

resource primaryFunction 'Microsoft.Web/sites@2023-01-01' existing = {
  name: primaryFunctionName
}

resource secondaryFunction 'Microsoft.Web/sites@2023-01-01' existing = {
  name: secondaryFunctionName
}

// Deployment script to configure indexes using Data Plane API 2025-09-01
resource indexDeployment 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'search-changefeed-deployment'
  location: location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '11.0'
    forceUpdateTag: deploymentTime
    retentionInterval: 'P1D'
    timeout: 'PT30M'
    arguments: '-PrimarySearchName "${primarySearchName}" -SecondarySearchName "${secondarySearchName}"'
    environmentVariables: [
      {
        name: 'PRIMARY_SEARCH_KEY'
        secureValue: primarySearch.listAdminKeys().primaryKey
      }
      {
        name: 'SECONDARY_SEARCH_KEY'
        secureValue: secondarySearch.listAdminKeys().primaryKey
      }
    ]
    scriptContent: '''
      param(
        [string]$PrimarySearchName,
        [string]$SecondarySearchName
      )
      
      $primaryKey = $env:PRIMARY_SEARCH_KEY
      $secondaryKey = $env:SECONDARY_SEARCH_KEY
      $apiVersion = "2025-09-01"
      $ErrorActionPreference = "Stop"
      
      Write-Host "Configuring Search indexes using Data Plane API $apiVersion..."
      
      # Index definition
      $index = @{
        name = "products-index"
        fields = @(
          @{ name = "id"; type = "Edm.String"; key = $true; searchable = $false; filterable = $true; sortable = $true; facetable = $false }
          @{ name = "name"; type = "Edm.String"; searchable = $true; filterable = $true; sortable = $true; facetable = $false }
          @{ name = "description"; type = "Edm.String"; searchable = $true; filterable = $false; sortable = $false; facetable = $false }
          @{ name = "category"; type = "Edm.String"; searchable = $true; filterable = $true; sortable = $true; facetable = $true }
          @{ name = "price"; type = "Edm.Double"; searchable = $false; filterable = $true; sortable = $true; facetable = $true }
        )
      } | ConvertTo-Json -Depth 10
      
      function Invoke-SearchApi {
        param(
          [string]$SearchService,
          [string]$ApiKey,
          [string]$Method,
          [string]$Resource,
          [string]$Body
        )
        
        $uri = "https://$SearchService.search.windows.net/$Resource?api-version=$apiVersion"
        $headers = @{
          "api-key" = $ApiKey
          "Content-Type" = "application/json"
        }
        
        try {
          if ($Method -eq "PUT" -or $Method -eq "POST") {
            Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers -Body $Body -ContentType "application/json"
          } else {
            Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers
          }
        }
        catch {
          Write-Host "  [ERROR] API call failed: $($_.Exception.Message)" -ForegroundColor Red
          if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Host "  Response: $responseBody" -ForegroundColor Red
          }
          $statusCode = $_.Exception.Response.StatusCode.value__
          if ($statusCode -eq 404) {
            return $null
          }
          throw
        }
      }
      
      # Configure primary search service
      Write-Host "Configuring primary search service: $PrimarySearchName"
      try {
        Invoke-SearchApi -SearchService $PrimarySearchName -ApiKey $primaryKey -Method "PUT" -Resource "indexes/products-index" -Body $index | Out-Null
        Write-Host "  - Created index" -ForegroundColor Green
      } catch {
        Write-Host "  [FAILED] Index creation failed" -ForegroundColor Red
        throw
      }
      
      # Configure secondary search service
      Write-Host "Configuring secondary search service: $SecondarySearchName"
      try {
        Invoke-SearchApi -SearchService $SecondarySearchName -ApiKey $secondaryKey -Method "PUT" -Resource "indexes/products-index" -Body $index | Out-Null
        Write-Host "  - Created index" -ForegroundColor Green
      } catch {
        Write-Host "  [FAILED] Index creation failed" -ForegroundColor Red
        throw
      }
      
      Write-Host "[OK] Successfully configured search indexes with Data Plane API $apiVersion"
      
      # Output results for verification
      $DeploymentScriptOutputs = @{}
      $DeploymentScriptOutputs['status'] = 'completed'
    '''
  }
}

// Configure function app settings for Cosmos DB change feed
resource primaryFunctionSettings 'Microsoft.Web/sites/config@2023-01-01' = {
  name: 'appsettings'
  parent: primaryFunction
  properties: {
    CosmosDBConnection: 'AccountEndpoint=${cosmosAccount.properties.documentEndpoint};AccountKey=${cosmosAccount.listKeys().primaryMasterKey}'
    PrimarySearchService: primarySearch.name
    SecondarySearchService: secondarySearch.name
    SearchApiKey: primarySearch.listAdminKeys().primaryKey
    FUNCTIONS_EXTENSION_VERSION: '~4'
    FUNCTIONS_WORKER_RUNTIME: 'dotnet'
  }
  dependsOn: [
    indexDeployment
  ]
}

resource secondaryFunctionSettings 'Microsoft.Web/sites/config@2023-01-01' = {
  name: 'appsettings'
  parent: secondaryFunction
  properties: {
    CosmosDBConnection: 'AccountEndpoint=${cosmosAccount.properties.documentEndpoint};AccountKey=${cosmosAccount.listKeys().primaryMasterKey}'
    PrimarySearchService: primarySearch.name
    SecondarySearchService: secondarySearch.name
    SearchApiKey: primarySearch.listAdminKeys().primaryKey
    FUNCTIONS_EXTENSION_VERSION: '~4'
    FUNCTIONS_WORKER_RUNTIME: 'dotnet'
  }
  dependsOn: [
    indexDeployment
  ]
}

output primaryIndexName string = 'products-index'
output secondaryIndexName string = 'products-index'
