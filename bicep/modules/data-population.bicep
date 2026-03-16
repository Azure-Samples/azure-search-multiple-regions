// Data population module using Deployment Scripts
@description('Name of the Azure Search service')
param searchServiceName string

@description('Admin key for the Azure Search service')
@secure()
param searchServiceKey string

@description('Location for the deployment script')
param location string

@description('Region identifier to tag the data')
param regionIdentifier string

@description('Unique identity for the script')
param scriptIdentity string

// Deployment script to create index and populate data
resource dataPopulationScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'populate-search-${scriptIdentity}'
  location: location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '11.0'
    retentionInterval: 'PT1H'
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      {
        name: 'SEARCH_SERVICE_NAME'
        value: searchServiceName
      }
      {
        name: 'SEARCH_ADMIN_KEY'
        secureValue: searchServiceKey
      }
      {
        name: 'REGION_ID'
        value: regionIdentifier
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = 'Stop'
      
      $searchServiceName = $env:SEARCH_SERVICE_NAME
      $searchAdminKey = $env:SEARCH_ADMIN_KEY
      $regionId = $env:REGION_ID
      $indexName = "products"
      $searchEndpoint = "https://$searchServiceName.search.windows.net"
      $apiVersion = "2023-11-01"
      
      Write-Host "Creating search index: $indexName"
      
      # Index schema
      $indexSchema = @{
        name = $indexName
        fields = @(
          @{
            name = "id"
            type = "Edm.String"
            key = $true
            searchable = $false
            filterable = $true
            sortable = $false
          }
          @{
            name = "name"
            type = "Edm.String"
            searchable = $true
            filterable = $true
            sortable = $true
          }
          @{
            name = "description"
            type = "Edm.String"
            searchable = $true
            filterable = $false
            sortable = $false
          }
          @{
            name = "category"
            type = "Edm.String"
            searchable = $true
            filterable = $true
            sortable = $true
            facetable = $true
          }
          @{
            name = "price"
            type = "Edm.Double"
            searchable = $false
            filterable = $true
            sortable = $true
            facetable = $true
          }
          @{
            name = "region"
            type = "Edm.String"
            searchable = $false
            filterable = $true
            sortable = $false
          }
        )
        suggesters = @()
        scoringProfiles = @()
        corsOptions = @{
          allowedOrigins = @("*")
        }
      }
      
      $headers = @{
        "api-key" = $searchAdminKey
        "Content-Type" = "application/json"
      }
      
      # Create index
      $indexUrl = "$searchEndpoint/indexes/$indexName`?api-version=$apiVersion"
      try {
        $response = Invoke-RestMethod -Uri $indexUrl -Method Put -Headers $headers -Body ($indexSchema | ConvertTo-Json -Depth 10)
        Write-Host "Index created successfully"
      }
      catch {
        if ($_.Exception.Response.StatusCode.Value__ -eq 204) {
          Write-Host "Index already exists, updating..."
        }
        else {
          Write-Host "Error creating index: $($_.Exception.Message)"
          throw
        }
      }
      
      # Sample documents
      $documents = @{
        value = @(
          @{
            "@search.action" = "mergeOrUpload"
            id = "1"
            name = "Laptop Pro 15"
            description = "High-performance laptop with 15-inch display, perfect for professionals"
            category = "Electronics"
            price = 1299.99
            region = $regionId
          }
          @{
            "@search.action" = "mergeOrUpload"
            id = "2"
            name = "Wireless Mouse"
            description = "Ergonomic wireless mouse with precision tracking"
            category = "Electronics"
            price = 29.99
            region = $regionId
          }
          @{
            "@search.action" = "mergeOrUpload"
            id = "3"
            name = "Office Chair Premium"
            description = "Comfortable ergonomic office chair with lumbar support"
            category = "Furniture"
            price = 399.99
            region = $regionId
          }
          @{
            "@search.action" = "mergeOrUpload"
            id = "4"
            name = "Mechanical Keyboard"
            description = "RGB mechanical keyboard with customizable keys"
            category = "Electronics"
            price = 149.99
            region = $regionId
          }
          @{
            "@search.action" = "mergeOrUpload"
            id = "5"
            name = "Standing Desk"
            description = "Adjustable height standing desk for better posture"
            category = "Furniture"
            price = 599.99
            region = $regionId
          }
          @{
            "@search.action" = "mergeOrUpload"
            id = "6"
            name = "USB-C Hub"
            description = "7-in-1 USB-C hub with multiple ports and power delivery"
            category = "Electronics"
            price = 49.99
            region = $regionId
          }
          @{
            "@search.action" = "mergeOrUpload"
            id = "7"
            name = "Monitor 27 inch"
            description = "4K UHD 27-inch monitor with HDR support"
            category = "Electronics"
            price = 449.99
            region = $regionId
          }
          @{
            "@search.action" = "mergeOrUpload"
            id = "8"
            name = "Desk Lamp LED"
            description = "Adjustable LED desk lamp with touch controls"
            category = "Furniture"
            price = 39.99
            region = $regionId
          }
        )
      }
      
      # Upload documents
      Write-Host "Uploading documents to index..."
      $docsUrl = "$searchEndpoint/indexes/$indexName/docs/index?api-version=$apiVersion"
      
      try {
        $response = Invoke-RestMethod -Uri $docsUrl -Method Post -Headers $headers -Body ($documents | ConvertTo-Json -Depth 10)
        Write-Host "Documents uploaded successfully"
        Write-Host "Indexed documents: $($response.value.Count)"
      }
      catch {
        Write-Host "Error uploading documents: $($_.Exception.Message)"
        throw
      }
      
      Write-Host "Data population complete for region: $regionId"
    '''
  }
}

// Outputs
output scriptStatus string = dataPopulationScript.properties.provisioningState
