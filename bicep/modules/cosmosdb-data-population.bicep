// Populate Cosmos DB with sample product data
param location string
param cosmosAccountName string
param cosmosDatabaseName string
param cosmosContainerName string

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' existing = {
  name: cosmosAccountName
}

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'cosmosdb-data-population'
  location: location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '11.0'
    retentionInterval: 'P1D'
    timeout: 'PT45M'
    arguments: '-CosmosAccountName "${cosmosAccountName}" -DatabaseName "${cosmosDatabaseName}" -ContainerName "${cosmosContainerName}"'
    environmentVariables: [
      {
        name: 'COSMOS_KEY'
        secureValue: cosmosAccount.listKeys().primaryMasterKey
      }
    ]
    scriptContent: '''
      param(
        [string]$CosmosAccountName,
        [string]$DatabaseName,
        [string]$ContainerName
      )
      
      $cosmosKey = $env:COSMOS_KEY
      $cosmosEndpoint = "https://${CosmosAccountName}.documents.azure.com:443/"
      
      Write-Host "Checking if Cosmos DB already contains sample products..."
      
      function New-CosmosDbAuthorizationToken {
        param(
          [string]$Verb,
          [string]$ResourceType,
          [string]$ResourceLink,
          [string]$Date,
          [string]$Key
        )
        
        $keyBytes = [System.Convert]::FromBase64String($Key)
        $text = @($Verb.ToLowerInvariant() + "`n" + $ResourceType.ToLowerInvariant() + "`n" + $ResourceLink + "`n" + $Date.ToLowerInvariant() + "`n" + "" + "`n")
        $body = [Text.Encoding]::UTF8.GetBytes($text)
        $hmacsha = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList @(,$keyBytes)
        $hash = $hmacsha.ComputeHash($body)
        $signature = [System.Convert]::ToBase64String($hash)
        [System.Web.HttpUtility]::UrlEncode("type=master&ver=1.0&sig=$signature")
      }
      
      Add-Type -AssemblyName System.Web

      # Wait for Cosmos DB data plane to become reachable before any operations
      Write-Host "Waiting for Cosmos DB data plane to become ready..."
      $waitResourceLink = "dbs/$DatabaseName/colls/$ContainerName"
      $waitElapsed = 0
      $waitMaxSeconds = 300
      $cosmosReady = $false
      while ($waitElapsed -lt $waitMaxSeconds) {
        try {
          $waitDateTime = [DateTime]::UtcNow.ToString("r")
          $waitAuthToken = New-CosmosDbAuthorizationToken -Verb "GET" -ResourceType "docs" -ResourceLink $waitResourceLink -Date $waitDateTime -Key $cosmosKey
          $waitHeaders = @{
            "authorization" = $waitAuthToken
            "x-ms-date" = $waitDateTime
            "x-ms-version" = "2018-12-31"
            "x-ms-max-item-count" = "1"
          }
          $waitR = Invoke-WebRequest -Uri "${cosmosEndpoint}${waitResourceLink}/docs" -Method Get -Headers $waitHeaders -TimeoutSec 10 -SkipHttpErrorCheck
          $waitSc = $waitR.StatusCode
          if ($waitSc -eq 200) {
            Write-Host "  [OK] Cosmos DB data plane ready (${waitElapsed}s)" -ForegroundColor Green
            $cosmosReady = $true
            break
          }
          if ($waitSc -eq 401 -or $waitSc -eq 403) {
            throw "Cosmos DB returned HTTP $waitSc - check access key"
          }
          Write-Host "  HTTP $waitSc (${waitElapsed}s)... retrying in 15s"
        } catch {
          Write-Host "  Connection error (${waitElapsed}s): $($_.Exception.Message) - retrying in 15s"
        }
        Start-Sleep -Seconds 15
        $waitElapsed += 15
      }
      if (-not $cosmosReady) {
        throw "Cosmos DB data plane did not become ready after ${waitMaxSeconds}s"
      }

      # Check if container already has documents
      $resourceLink = "dbs/$DatabaseName/colls/$ContainerName"
      $dateTime = [DateTime]::UtcNow.ToString("r")
      $authToken = New-CosmosDbAuthorizationToken -Verb "GET" -ResourceType "docs" -ResourceLink $resourceLink -Date $dateTime -Key $cosmosKey
      
      $headers = @{
        "authorization" = $authToken
        "x-ms-date" = $dateTime
        "x-ms-version" = "2018-12-31"
        "x-ms-max-item-count" = "1"
      }
      
      $uri = "$cosmosEndpoint$resourceLink/docs"
      
      try {
        $existingDocs = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ContentType "application/json"
        if ($existingDocs.Documents -and $existingDocs.Documents.Count -gt 0) {
          Write-Host "[OK] Container already has $($existingDocs._count) documents. Skipping data population."
          exit 0
        }
      }
      catch {
        Write-Host "Container is empty or checking failed. Proceeding with data population..."
      }
      
      Write-Host "Populating Cosmos DB with 50 sample products using REST API..."
      
      $products = @(
        @{id="1"; name="Laptop Pro 15"; description="High-performance laptop with 15-inch display"; category="Electronics"; price=1299.99},
        @{id="2"; name="Wireless Mouse"; description="Ergonomic wireless mouse with precision tracking"; category="Electronics"; price=29.99},
        @{id="3"; name="USB-C Hub"; description="7-in-1 USB-C hub with HDMI and Ethernet"; category="Electronics"; price=49.99},
        @{id="4"; name="Office Chair"; description="Ergonomic office chair with lumbar support"; category="Furniture"; price=299.99},
        @{id="5"; name="Standing Desk"; description="Height-adjustable standing desk"; category="Furniture"; price=599.99},
        @{id="6"; name="Desk Lamp"; description="LED desk lamp with adjustable brightness"; category="Furniture"; price=39.99},
        @{id="7"; name="Bookshelf"; description="5-tier wooden bookshelf"; category="Furniture"; price=149.99},
        @{id="8"; name="Monitor 27in"; description="4K UHD monitor with HDR support"; category="Electronics"; price=449.99},
        @{id="9"; name="Mechanical Keyboard"; description="RGB backlit mechanical keyboard"; category="Electronics"; price=129.99},
        @{id="10"; name="Webcam HD"; description="1080p HD webcam with built-in mic"; category="Electronics"; price=79.99},
        @{id="11"; name="Headphones"; description="Noise-cancelling wireless headphones"; category="Electronics"; price=199.99},
        @{id="12"; name="Tablet 10in"; description="10-inch tablet with stylus support"; category="Electronics"; price=399.99},
        @{id="13"; name="Smartphone"; description="Latest smartphone with 5G support"; category="Electronics"; price=899.99},
        @{id="14"; name="Smartwatch"; description="Fitness tracking smartwatch"; category="Electronics"; price=249.99},
        @{id="15"; name="External SSD 1TB"; description="Portable SSD with USB 3.2"; category="Electronics"; price=119.99},
        @{id="16"; name="Router WiFi 6"; description="Dual-band WiFi 6 router"; category="Electronics"; price=179.99},
        @{id="17"; name="Printer All-in-One"; description="Wireless all-in-one printer"; category="Electronics"; price=149.99},
        @{id="18"; name="Conference Table"; description="8-person conference table"; category="Furniture"; price=799.99},
        @{id="19"; name="File Cabinet"; description="3-drawer locking file cabinet"; category="Furniture"; price=199.99},
        @{id="20"; name="Whiteboard"; description="6x4 ft magnetic whiteboard"; category="Furniture"; price=129.99},
        @{id="21"; name="Coffee Table"; description="Modern glass coffee table"; category="Furniture"; price=179.99},
        @{id="22"; name="Sofa 3-Seater"; description="Comfortable 3-seater sofa"; category="Furniture"; price=699.99},
        @{id="23"; name="Dining Table"; description="6-person dining table with chairs"; category="Furniture"; price=899.99},
        @{id="24"; name="TV Stand"; description="Modern TV stand up to 65in"; category="Furniture"; price=249.99},
        @{id="25"; name="Gaming Console"; description="Next-gen gaming console"; category="Electronics"; price=499.99},
        @{id="26"; name="Graphics Card"; description="High-end graphics card for gaming"; category="Electronics"; price=799.99},
        @{id="27"; name="RAM 32GB Kit"; description="32GB DDR4 RAM kit"; category="Electronics"; price=159.99},
        @{id="28"; name="Power Supply 850W"; description="Modular 850W power supply"; category="Electronics"; price=129.99},
        @{id="29"; name="CPU Cooler"; description="Liquid CPU cooler with RGB"; category="Electronics"; price=99.99},
        @{id="30"; name="Microphone USB"; description="Professional USB microphone"; category="Electronics"; price=89.99},
        @{id="31"; name="Speaker System"; description="5.1 surround sound speaker system"; category="Electronics"; price=299.99},
        @{id="32"; name="Projector 4K"; description="4K home theater projector"; category="Electronics"; price=1199.99},
        @{id="33"; name="Screen Projector"; description="120-inch projector screen"; category="Electronics"; price=199.99},
        @{id="34"; name="Cable Management"; description="Under-desk cable management kit"; category="Furniture"; price=29.99},
        @{id="35"; name="Monitor Arm"; description="Dual monitor arm mount"; category="Furniture"; price=79.99},
        @{id="36"; name="Footrest"; description="Ergonomic footrest"; category="Furniture"; price=39.99},
        @{id="37"; name="Desk Organizer"; description="Bamboo desk organizer"; category="Furniture"; price=24.99},
        @{id="38"; name="Plant Stand"; description="3-tier metal plant stand"; category="Furniture"; price=49.99},
        @{id="39"; name="Storage Ottoman"; description="Storage ottoman with cushion"; category="Furniture"; price=89.99},
        @{id="40"; name="Laptop Stand"; description="Aluminum laptop stand"; category="Electronics"; price=44.99},
        @{id="41"; name="Docking Station"; description="Thunderbolt 4 docking station"; category="Electronics"; price=299.99},
        @{id="42"; name="UPS Battery Backup"; description="1500VA UPS with surge protection"; category="Electronics"; price=179.99},
        @{id="43"; name="Smart Speaker"; description="AI-powered smart speaker"; category="Electronics"; price=99.99},
        @{id="44"; name="Smart Bulbs 4-Pack"; description="Color-changing smart bulbs"; category="Electronics"; price=59.99},
        @{id="45"; name="Security Camera"; description="Indoor security camera with night vision"; category="Electronics"; price=49.99},
        @{id="46"; name="Door Lock Smart"; description="Keyless smart door lock"; category="Electronics"; price=199.99},
        @{id="47"; name="Thermostat Smart"; description="Learning thermostat"; category="Electronics"; price=249.99},
        @{id="48"; name="Air Purifier"; description="HEPA air purifier"; category="Electronics"; price=199.99},
        @{id="49"; name="Humidifier"; description="Ultrasonic cool mist humidifier"; category="Electronics"; price=79.99},
        @{id="50"; name="Desk Converter"; description="Sit-stand desk converter"; category="Furniture"; price=199.99}
      )
      
      $resourceLink = "dbs/$DatabaseName/colls/$ContainerName"
      
      foreach ($product in $products) {
        $dateTime = [DateTime]::UtcNow.ToString("r")
        $authToken = New-CosmosDbAuthorizationToken -Verb "POST" -ResourceType "docs" -ResourceLink $resourceLink -Date $dateTime -Key $cosmosKey
        
        $headers = @{
          "authorization" = $authToken
          "x-ms-date" = $dateTime
          "x-ms-version" = "2018-12-31"
          "x-ms-documentdb-partitionkey" = "[`"$($product.id)`"]"
          "Content-Type" = "application/json"
        }
        
        $body = $product | ConvertTo-Json -Compress
        $uri = "$cosmosEndpoint$resourceLink/docs"
        
        try {
          Write-Host "Adding product $($product.id): $($product.name)"
          $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ContentType "application/json"
        }
        catch {
          Write-Warning "Failed to add product $($product.id): $_"
        }
      }
      
      Write-Host "Successfully populated 50 products in Cosmos DB"
    '''
  }
}

output scriptStatus string = deploymentScript.properties.provisioningState
