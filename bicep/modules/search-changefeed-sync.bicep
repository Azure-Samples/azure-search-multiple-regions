// Configure search indexes and change feed function app settings for Option 2
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

// Managed identity for the settings merge deployment script
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'changefeed-deploy-identity'
  location: location
}

// Contributor role on the resource group so the script can read and update function app settings
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedIdentity.id, resourceGroup().id, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Deployment script to configure search indexes using Data Plane API 2025-09-01
// Uses the same Wait-SearchServiceReady + Invoke-SearchPost retry pattern as Option 1
resource indexDeployment 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'search-changefeed-deployment'
  location: location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '11.0'
    forceUpdateTag: deploymentTime
    retentionInterval: 'P1D'
    timeout: 'PT45M'
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

      Write-Host "Configuring Search indexes using Data Plane API $apiVersion..."

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
        param([string]$ServiceName, [string]$ApiKey, [string]$Label)
        Write-Host ""
        Write-Host "Configuring $Label search service: $ServiceName"

        Wait-SearchServiceReady -ServiceName $ServiceName -ApiKey $ApiKey

        # Clean up existing index if present
        $baseUri = "https://${ServiceName}.search.windows.net"
        $headers = @{ "api-key" = $ApiKey; "Content-Type" = "application/json" }
        Write-Host "  Cleaning up existing index if present..."
        try {
          $delR = Invoke-WebRequest -Uri "${baseUri}/indexes/products-index?api-version=${apiVersion}" -Method DELETE -Headers $headers -SkipHttpErrorCheck
          Write-Host "    Delete: HTTP $($delR.StatusCode)"
        } catch {
          Write-Host "    Cleanup skipped: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        Start-Sleep -Seconds 5

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
      }

      Configure-SearchService -ServiceName $PrimarySearchName -ApiKey $primaryKey -Label "primary"
      Configure-SearchService -ServiceName $SecondarySearchName -ApiKey $secondaryKey -Label "secondary"

      Write-Host ""
      Write-Host "[OK] Successfully configured search indexes" -ForegroundColor Green

      $DeploymentScriptOutputs = @{}
      $DeploymentScriptOutputs['status'] = 'completed'
    '''
  }
}

// Deployment script to merge change feed settings into function apps
// Uses Get-AzWebApp / Set-AzWebApp to READ-THEN-WRITE, preserving all existing
// settings (AzureWebJobsStorage, App Insights keys, SearchServiceEndpoint, etc.)
resource functionSettingsDeploy 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'changefeed-settings-deployment'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '11.0'
    forceUpdateTag: deploymentTime
    retentionInterval: 'P1D'
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    arguments: '-ResourceGroupName "${resourceGroup().name}" -PrimaryFunctionName "${primaryFunctionName}" -SecondaryFunctionName "${secondaryFunctionName}" -PrimarySearchName "${primarySearchName}" -SecondarySearchName "${secondarySearchName}"'
    environmentVariables: [
      {
        name: 'COSMOS_CONNECTION_STRING'
        secureValue: 'AccountEndpoint=${cosmosAccount.properties.documentEndpoint};AccountKey=${cosmosAccount.listKeys().primaryMasterKey}'
      }
      {
        name: 'SEARCH_API_KEY'
        secureValue: primarySearch.listAdminKeys().primaryKey
      }
    ]
    scriptContent: '''
      param(
        [string]$ResourceGroupName,
        [string]$PrimaryFunctionName,
        [string]$SecondaryFunctionName,
        [string]$PrimarySearchName,
        [string]$SecondarySearchName
      )

      $ErrorActionPreference = 'Stop'
      $cosmosConnection = $env:COSMOS_CONNECTION_STRING
      $searchApiKey = $env:SEARCH_API_KEY

      # Wait for managed identity role assignment to propagate before making management API calls
      Write-Host "Waiting for role assignment propagation..."
      Start-Sleep -Seconds 30

      function Merge-FunctionSettings {
        param(
          [string]$ResourceGroupName,
          [string]$FunctionAppName,
          [string]$PrimarySearchName,
          [string]$SecondarySearchName,
          [string]$SearchApiKey,
          [string]$CosmosConnection
        )

        Write-Host ""
        Write-Host "Merging change feed settings into $FunctionAppName..."

        # Read all existing settings first so we do not overwrite them
        $app = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName
        $settings = @{}
        foreach ($s in $app.SiteConfig.AppSettings) {
          $settings[$s.Name] = $s.Value
        }

        # Merge in the four change feed settings
        $settings['CosmosDBConnection']    = $CosmosConnection
        $settings['PrimarySearchService']  = $PrimarySearchName
        $settings['SecondarySearchService'] = $SecondarySearchName
        $settings['SearchApiKey']          = $SearchApiKey

        Set-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -AppSettings $settings | Out-Null
        Write-Host "  [OK] Change feed settings merged into $FunctionAppName" -ForegroundColor Green
      }

      Merge-FunctionSettings `
        -ResourceGroupName $ResourceGroupName `
        -FunctionAppName $PrimaryFunctionName `
        -PrimarySearchName $PrimarySearchName `
        -SecondarySearchName $SecondarySearchName `
        -SearchApiKey $searchApiKey `
        -CosmosConnection $cosmosConnection

      Merge-FunctionSettings `
        -ResourceGroupName $ResourceGroupName `
        -FunctionAppName $SecondaryFunctionName `
        -PrimarySearchName $PrimarySearchName `
        -SecondarySearchName $SecondarySearchName `
        -SearchApiKey $searchApiKey `
        -CosmosConnection $cosmosConnection

      Write-Host ""
      Write-Host "[OK] Change feed settings merged into both function apps" -ForegroundColor Green

      $DeploymentScriptOutputs = @{}
      $DeploymentScriptOutputs['status'] = 'completed'
    '''
  }
  dependsOn: [
    indexDeployment
    roleAssignment
  ]
}

output primaryIndexName string = 'products-index'
output secondaryIndexName string = 'products-index'
