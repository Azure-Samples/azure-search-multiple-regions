# Script to manually configure Azure AI Search indexes and indexers
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = ".bcdr-config.json"
)

# Load configuration
if (-not (Test-Path $ConfigFile)) {
    Write-Host "Error: Configuration file not found: $ConfigFile" -ForegroundColor Red
    Write-Host "Please run deploy.ps1 first to create the configuration." -ForegroundColor Yellow
    exit 1
}

$config = Get-Content $ConfigFile | ConvertFrom-Json

Write-Host ""
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host " CONFIGURING AZURE AI SEARCH" -ForegroundColor Yellow
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host ""

# Get search service keys
Write-Host "Retrieving search service admin keys..." -ForegroundColor Gray
$primaryKey = az search admin-key show `
    --resource-group $config.resourceGroupName `
    --service-name $config.primarySearchName `
    --query primaryKey -o tsv

$secondaryKey = az search admin-key show `
    --resource-group $config.resourceGroupName `
    --service-name $config.secondarySearchName `
    --query primaryKey -o tsv

# Get Cosmos DB connection info
Write-Host "Retrieving Cosmos DB connection info..." -ForegroundColor Gray
$cosmosEndpoint = az cosmosdb show `
    --resource-group $config.resourceGroupName `
    --name $config.cosmosAccountName `
    --query documentEndpoint -o tsv

$cosmosKey = az cosmosdb keys list `
    --resource-group $config.resourceGroupName `
    --name $config.cosmosAccountName `
    --query primaryMasterKey -o tsv

$apiVersion = "2024-07-01"

Write-Host "[OK] Retrieved credentials" -ForegroundColor Green
Write-Host "[OK] Retrieved credentials" -ForegroundColor Green
Write-Host ""

# Data source definition
$dataSource = @{
    name = "cosmosdb-datasource"
    type = "cosmosdb"
    credentials = @{
        connectionString = "AccountEndpoint=$cosmosEndpoint;AccountKey=$cosmosKey;Database=productsdb"
    }
    container = @{
        name = "products"
    }
    dataChangeDetectionPolicy = @{
        "@odata.type" = "#Microsoft.Azure.Search.HighWaterMarkChangeDetectionPolicy"
        highWaterMarkColumnName = "_ts"
    }
} | ConvertTo-Json -Depth 10

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

# Indexer definition
$indexer = @{
    name = "products-indexer"
    dataSourceName = "cosmosdb-datasource"
    targetIndexName = "products-index"
    schedule = @{
        interval = "PT5M"
    }
    fieldMappings = @()
} | ConvertTo-Json -Depth 10

function Invoke-SearchApi {
    param(
        [string]$SearchService,
        [string]$ApiKey,
        [string]$Method,
        [string]$Resource,
        [string]$Body
    )
    
    $uri = "https://$SearchService.search.windows.net/$Resource`?api-version=$apiVersion"
    $headers = @{
        "api-key" = $ApiKey
        "Content-Type" = "application/json"
    }
    
    try {
        if ($Method -eq "PUT" -or $Method -eq "POST") {
            $response = Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers -Body $Body -ContentType "application/json"
        } else {
            $response = Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers
        }
        return $response
    }
    catch {
        Write-Host "Error calling $uri" -ForegroundColor Red
        Write-Host "Status: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        Write-Host "Message: $($_.Exception.Message)" -ForegroundColor Red
        
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $reader.BaseStream.Position = 0
            $responseBody = $reader.ReadToEnd()
            Write-Host "Response: $responseBody" -ForegroundColor Red
        }
        throw
    }
}

# Configure primary search service
Write-Host "Configuring primary search service: $($config.primarySearchName)" -ForegroundColor Yellow
try {
    Invoke-SearchApi -SearchService $config.primarySearchName -ApiKey $primaryKey -Method "PUT" -Resource "datasources/cosmosdb-datasource" -Body $dataSource | Out-Null
    Write-Host "  [OK] Created data source" -ForegroundColor Green
    Write-Host "  [OK] Created data source" -ForegroundColor Green
    
    Invoke-SearchApi -SearchService $config.primarySearchName -ApiKey $primaryKey -Method "PUT" -Resource "indexes/products-index" -Body $index | Out-Null
    Write-Host "  [OK] Created index" -ForegroundColor Green
    Write-Host "  [OK] Created index" -ForegroundColor Green
    
    Invoke-SearchApi -SearchService $config.primarySearchName -ApiKey $primaryKey -Method "PUT" -Resource "indexers/products-indexer" -Body $indexer | Out-Null
    Write-Host "  [OK] Created indexer" -ForegroundColor Green
    Write-Host "  [OK] Created indexer" -ForegroundColor Green
}
catch {
    Write-Host "  X Failed to configure primary search service" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Configure secondary search service
Write-Host "Configuring secondary search service: $($config.secondarySearchName)" -ForegroundColor Yellow
try {
    Invoke-SearchApi -SearchService $config.secondarySearchName -ApiKey $secondaryKey -Method "PUT" -Resource "datasources/cosmosdb-datasource" -Body $dataSource | Out-Null
    Write-Host "  [OK] Created data source" -ForegroundColor Green
    Write-Host "  [OK] Created data source" -ForegroundColor Green
    
    Invoke-SearchApi -SearchService $config.secondarySearchName -ApiKey $secondaryKey -Method "PUT" -Resource "indexes/products-index" -Body $index | Out-Null
    Write-Host "  [OK] Created index" -ForegroundColor Green
    Write-Host "  [OK] Created index" -ForegroundColor Green
    
    Invoke-SearchApi -SearchService $config.secondarySearchName -ApiKey $secondaryKey -Method "PUT" -Resource "indexers/products-indexer" -Body $indexer | Out-Null
    Write-Host "  [OK] Created indexer" -ForegroundColor Green
    Write-Host "  [OK] Created indexer" -ForegroundColor Green
}
catch {
    Write-Host "  X Failed to configure secondary search service" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host " CONFIGURATION COMPLETE" -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Search indexes and indexers configured successfully!" -ForegroundColor Green
Write-Host "Indexers will run every 5 minutes to sync data from Cosmos DB." -ForegroundColor Gray
Write-Host ""
Write-Host "To trigger indexers immediately, run:" -ForegroundColor Yellow
Write-Host "  az search indexer run --service-name $($config.primarySearchName) --name products-indexer --resource-group $($config.resourceGroupName)" -ForegroundColor White
Write-Host ""
