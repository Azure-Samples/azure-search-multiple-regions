// Configure indexers on both search services to pull from Cosmos DB using Data Plane API
param location string
param primarySearchName string
param secondarySearchName string
param cosmosAccountName string
param cosmosDatabaseName string
param cosmosContainerName string
param deploymentTime string

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' existing = {
  name: cosmosAccountName
}

resource primarySearch 'Microsoft.Search/searchServices@2025-05-01' existing = {
  name: primarySearchName
}

resource secondarySearch 'Microsoft.Search/searchServices@2025-05-01' existing = {
  name: secondarySearchName
}

// Deployment script to configure data sources, indexes, and indexers using Data Plane API 2025-09-01
resource indexerDeployment 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'search-indexer-deployment'
  location: location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '11.0'
    forceUpdateTag: deploymentTime
    retentionInterval: 'P1D'
    timeout: 'PT45M'
    arguments: '-PrimarySearchName "${primarySearchName}" -SecondarySearchName "${secondarySearchName}" -CosmosEndpoint "${cosmosAccount.properties.documentEndpoint}" -CosmosKey "${cosmosAccount.listKeys().primaryMasterKey}" -DatabaseName "${cosmosDatabaseName}" -ContainerName "${cosmosContainerName}"'
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
        [string]$SecondarySearchName,
        [string]$CosmosEndpoint,
        [string]$CosmosKey,
        [string]$DatabaseName,
        [string]$ContainerName
      )
      
      $primaryKey = $env:PRIMARY_SEARCH_KEY
      $secondaryKey = $env:SECONDARY_SEARCH_KEY
      $apiVersion = "2025-09-01"
      
      Write-Host "Configuring Search indexes and indexers using Data Plane API $apiVersion..."
      
      function Wait-SearchServiceReady {
        param([string]$ServiceName, [string]$ApiKey, [int]$MaxWaitSeconds = 300)
        $uri = "https://${ServiceName}.search.windows.net/indexes?api-version=${apiVersion}"
        $headers = @{ "api-key" = $ApiKey }
        $elapsed = 0
        Write-Host "  Waiting for $ServiceName data plane..."
        while ($elapsed -lt $MaxWaitSeconds) {
          try {
            $r = Invoke-WebRequest -Uri $uri -Method GET -Headers $headers -TimeoutSec 10 -SkipHttpErrorCheck
            if ($r.StatusCode -eq 200) {
              Write-Host "  [OK] $ServiceName ready (${elapsed}s)" -ForegroundColor Green
              return
            }
            Write-Host "  HTTP $($r.StatusCode) (${elapsed}s)..." -ForegroundColor Yellow
          } catch {
            Write-Host "  Connection error (${elapsed}s): $($_.Exception.Message)" -ForegroundColor Yellow
          }
          Start-Sleep -Seconds 15
          $elapsed += 15
        }
        throw "$ServiceName not available after ${MaxWaitSeconds}s"
      }
      
      function Invoke-SearchPost {
        param(
          [string]$SearchService,
          [string]$ApiKey,
          [string]$Collection,
          [string]$Body,
          [int]$MaxRetries = 6
        )
        $baseUri = "https://${SearchService}.search.windows.net"
        $headers = @{ "api-key" = $ApiKey; "Content-Type" = "application/json" }
        
        for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
          $postUri = "${baseUri}/${Collection}?api-version=${apiVersion}"
          Write-Host "  POST ${Collection} (attempt $attempt)..."
          try {
            $r = Invoke-WebRequest -Uri $postUri -Method POST -Headers $headers -Body $Body -ContentType "application/json" -SkipHttpErrorCheck
          } catch {
            Write-Host "  Connection error: $($_.Exception.Message)" -ForegroundColor Yellow
            if ($attempt -lt $MaxRetries) { Start-Sleep -Seconds 20; continue }
            throw "Connection failed after $MaxRetries attempts"
          }
          
          $sc = $r.StatusCode
          Write-Host "  Response: HTTP $sc" -ForegroundColor $(if ($sc -lt 300) { "Green" } else { "Yellow" })
          
          if ($sc -eq 201 -or $sc -eq 200) {
            return ($r.Content | ConvertFrom-Json -ErrorAction SilentlyContinue)
          }
          
          # Always log the response body on non-success for diagnostics
          Write-Host "  Response body: $($r.Content)" -ForegroundColor Red
          
          # 400 Bad Request is never retryable - fail immediately
          if ($sc -eq 400) {
            throw "HTTP 400 Bad Request on POST ${Collection}: $($r.Content)"
          }
          
          if ($sc -eq 404 -or $sc -eq 503 -or $sc -eq 409 -or $sc -eq 429) {
            if ($attempt -lt $MaxRetries) {
              Write-Host "  Retrying in 20s..." -ForegroundColor Yellow
              Start-Sleep -Seconds 20
              continue
            }
          }
          
          if ($attempt -eq $MaxRetries) {
            throw "Failed after $MaxRetries attempts: HTTP $sc on POST ${Collection}"
          }
          
          Start-Sleep -Seconds 20
        }
      }
      
      function Configure-SearchService {
        param(
          [string]$ServiceName,
          [string]$ApiKey,
          [string]$Label
        )
        Write-Host ""
        Write-Host "Configuring $Label search service: $ServiceName"
        
        Wait-SearchServiceReady -ServiceName $ServiceName -ApiKey $ApiKey
        
        # Clean up any existing resources in reverse dependency order
        # (indexer depends on datasource + index, so must be deleted first)
        $baseUri = "https://${ServiceName}.search.windows.net"
        $headers = @{ "api-key" = $ApiKey; "Content-Type" = "application/json" }
        foreach ($resource in @("indexers/products-indexer", "indexes/products-index", "datasources/cosmosdb-datasource")) {
          $name = $resource.Split("/")[1]
          $collection = $resource.Split("/")[0]
          Write-Host "  Cleaning up $resource if it exists..."
          try {
            # Reset indexer change tracking before deletion
            if ($collection -eq "indexers") {
              $resetUri = "${baseUri}/${resource}/reset?api-version=${apiVersion}"
              $resetR = Invoke-WebRequest -Uri $resetUri -Method POST -Headers $headers -SkipHttpErrorCheck
              Write-Host "    Reset: HTTP $($resetR.StatusCode)"
            }
            $delUri = "${baseUri}/${resource}?api-version=${apiVersion}"
            $delR = Invoke-WebRequest -Uri $delUri -Method DELETE -Headers $headers -SkipHttpErrorCheck
            Write-Host "    Delete: HTTP $($delR.StatusCode)"
          } catch {
            Write-Host "    Cleanup skipped: $($_.Exception.Message)" -ForegroundColor Yellow
          }
        }
        Start-Sleep -Seconds 5
        
        # Create data source
        $dsBody = @{
          name = "cosmosdb-datasource"
          type = "cosmosdb"
          credentials = @{
            connectionString = "AccountEndpoint=$CosmosEndpoint;AccountKey=$CosmosKey;Database=$DatabaseName"
          }
          container = @{ name = $ContainerName }
          dataChangeDetectionPolicy = @{
            "@odata.type" = "#Microsoft.Azure.Search.HighWaterMarkChangeDetectionPolicy"
            highWaterMarkColumnName = "_ts"
          }
        } | ConvertTo-Json -Depth 10
        
        Invoke-SearchPost -SearchService $ServiceName -ApiKey $ApiKey -Collection "datasources" -Body $dsBody | Out-Null
        Write-Host "  [OK] Data source created" -ForegroundColor Green
        
        # Create index
        $idxBody = @{
          name = "products-index"
          fields = @(
            @{ name = "id"; type = "Edm.String"; key = $true; searchable = $false; filterable = $true; sortable = $true; facetable = $false }
            @{ name = "name"; type = "Edm.String"; searchable = $true; filterable = $true; sortable = $true; facetable = $false }
            @{ name = "description"; type = "Edm.String"; searchable = $true; filterable = $false; sortable = $false; facetable = $false }
            @{ name = "category"; type = "Edm.String"; searchable = $true; filterable = $true; sortable = $true; facetable = $true }
            @{ name = "price"; type = "Edm.Double"; searchable = $false; filterable = $true; sortable = $true; facetable = $true }
          )
        } | ConvertTo-Json -Depth 10
        
        Invoke-SearchPost -SearchService $ServiceName -ApiKey $ApiKey -Collection "indexes" -Body $idxBody | Out-Null
        Write-Host "  [OK] Index created" -ForegroundColor Green
        
        # Create indexer
        $ixrBody = @{
          name = "products-indexer"
          dataSourceName = "cosmosdb-datasource"
          targetIndexName = "products-index"
          schedule = @{ interval = "PT5M" }
          fieldMappings = @()
        } | ConvertTo-Json -Depth 10
        
        Invoke-SearchPost -SearchService $ServiceName -ApiKey $ApiKey -Collection "indexers" -Body $ixrBody | Out-Null
        Write-Host "  [OK] Indexer created" -ForegroundColor Green
      }
      
      Configure-SearchService -ServiceName $PrimarySearchName -ApiKey $primaryKey -Label "primary"
      Configure-SearchService -ServiceName $SecondarySearchName -ApiKey $secondaryKey -Label "secondary"
      
      Write-Host ""
      Write-Host "[OK] Successfully configured both search services" -ForegroundColor Green
      
      $DeploymentScriptOutputs = @{}
      $DeploymentScriptOutputs['status'] = 'completed'
    '''
  }
}

output primaryIndexName string = 'products-index'
output secondaryIndexName string = 'products-index'
