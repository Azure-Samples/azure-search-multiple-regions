// Frontend deployment module using Deployment Scripts
@description('Name of the storage account for frontend')
param storageAccountName string

@description('Location for the deployment script')
param location string

@description('Traffic Manager DNS URL')
param trafficManagerDns string

// Deployment script to upload frontend files
resource frontendDeploy 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'deploy-frontend'
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
    retentionInterval: 'PT1H'
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      {
        name: 'STORAGE_ACCOUNT_NAME'
        value: storageAccountName
      }
      {
        name: 'TRAFFIC_MANAGER_DNS'
        value: trafficManagerDns
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = 'Stop'
      
      $storageAccountName = $env:STORAGE_ACCOUNT_NAME
      $trafficManagerDns = $env:TRAFFIC_MANAGER_DNS
      
      Write-Host "Uploading frontend to storage account: $storageAccountName"
      Write-Host "Traffic Manager DNS: $trafficManagerDns"
      
      # Wait for storage account to be ready
      Start-Sleep -Seconds 15
      
      # Get storage account key
      $storageKey = (az storage account keys list --account-name $storageAccountName --query "[0].value" -o tsv)
      
      # Create index.html content with pre-configured Traffic Manager URL
      $indexHtml = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Azure Search BCDR Test</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { text-align: center; color: white; margin-bottom: 40px; }
        .header h1 { font-size: 2.5em; margin-bottom: 10px; text-shadow: 2px 2px 4px rgba(0,0,0,0.3); }
        .header p { font-size: 1.1em; opacity: 0.9; }
        .search-card {
            background: white;
            border-radius: 15px;
            padding: 30px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            margin-bottom: 30px;
        }
        .search-form { display: flex; gap: 10px; margin-bottom: 20px; }
        .search-input {
            flex: 1;
            padding: 15px 20px;
            border: 2px solid #e0e0e0;
            border-radius: 10px;
            font-size: 16px;
            transition: all 0.3s;
        }
        .search-input:focus {
            outline: none;
            border-color: #667eea;
            box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
        }
        .search-button {
            padding: 15px 40px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 10px;
            font-size: 16px;
            font-weight: bold;
            cursor: pointer;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        .search-button:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 20px rgba(102, 126, 234, 0.4);
        }
        .search-button:disabled { opacity: 0.6; cursor: not-allowed; transform: none; }
        .status {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 15px;
            background: #e8f5e9;
            border-left: 4px solid #4caf50;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        .status.error { background: #ffebee; border-left-color: #f44336; }
        .status.loading { background: #e3f2fd; border-left-color: #2196f3; }
        .region-badge {
            display: inline-block;
            padding: 5px 15px;
            background: #4caf50;
            color: white;
            border-radius: 20px;
            font-weight: bold;
            font-size: 0.9em;
        }
        .results {
            background: white;
            border-radius: 15px;
            padding: 30px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
        }
        .results h2 {
            margin-bottom: 20px;
            color: #333;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }
        .result-count { font-size: 0.9em; color: #666; font-weight: normal; }
        .result-item {
            padding: 20px;
            border: 1px solid #e0e0e0;
            border-radius: 10px;
            margin-bottom: 15px;
            transition: all 0.3s;
        }
        .result-item:hover {
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            transform: translateY(-2px);
        }
        .result-title {
            font-size: 1.3em;
            font-weight: bold;
            color: #667eea;
            margin-bottom: 10px;
        }
        .result-description { color: #666; margin-bottom: 10px; line-height: 1.5; }
        .result-meta { display: flex; gap: 20px; font-size: 0.9em; color: #999; }
        .result-meta span { display: flex; align-items: center; gap: 5px; }
        .price { color: #4caf50; font-weight: bold; font-size: 1.1em; }
        .no-results { text-align: center; padding: 40px; color: #999; }
        .spinner {
            display: inline-block;
            width: 20px;
            height: 20px;
            border: 3px solid rgba(255,255,255,.3);
            border-radius: 50%;
            border-top-color: #fff;
            animation: spin 1s ease-in-out infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
        .hidden { display: none; }
        .info-box {
            background: #d1ecf1;
            border: 1px solid #bee5eb;
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 20px;
            color: #0c5460;
        }
        .info-box strong { display: block; margin-bottom: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>[Search] Azure Search BCDR Test</h1>
            <p>Multi-Region Business Continuity & Disaster Recovery Demo</p>
        </div>

        <div class="search-card">
            <div class="info-box">
                <strong>[OK] Configured!</strong>
                Traffic Manager URL: https://$trafficManagerDns
            </div>

            <form class="search-form" onsubmit="performSearch(event)">
                <input 
                    type="text" 
                    id="searchQuery" 
                    class="search-input" 
                    placeholder="Enter search query (e.g., 'laptop', 'furniture', or '*' for all)" 
                    value="*"
                    required
                />
                <button type="submit" class="search-button" id="searchButton">
                    Search
                </button>
            </form>

            <div id="statusMessage" class="hidden"></div>
        </div>

        <div id="resultsContainer" class="hidden results">
            <h2>
                Search Results
                <span class="result-count" id="resultCount"></span>
            </h2>
            <div id="resultsList"></div>
        </div>
    </div>

    <script>
        const TRAFFIC_MANAGER_URL = 'https://$trafficManagerDns';

        async function performSearch(event) {
            event.preventDefault();

            const query = document.getElementById('searchQuery').value;
            const statusMessage = document.getElementById('statusMessage');
            const resultsContainer = document.getElementById('resultsContainer');
            const searchButton = document.getElementById('searchButton');

            searchButton.disabled = true;
            searchButton.innerHTML = '<span class="spinner"></span> Searching...';
            showStatus('Searching...', 'loading');
            resultsContainer.classList.add('hidden');

            try {
                const apiUrl = TRAFFIC_MANAGER_URL + '/api/search?q=' + encodeURIComponent(query);
                console.log('Calling API:', apiUrl);

                const response = await fetch(apiUrl, {
                    method: 'GET',
                    headers: { 'Accept': 'application/json' }
                });

                if (!response.ok) {
                    throw new Error('HTTP error! status: ' + response.status);
                }

                const data = await response.json();
                displayResults(data);
                showStatus(
                    '<span>Search completed successfully!</span>' +
                    '<span class="region-badge">[Location] ' + (data.region || 'Unknown Region') + '</span>',
                    'success'
                );

            } catch (error) {
                console.error('Search error:', error);
                showStatus('Error: ' + error.message + '. Please wait for deployment to complete.', 'error');
            } finally {
                searchButton.disabled = false;
                searchButton.textContent = 'Search';
            }
        }

        function showStatus(message, type) {
            const statusMessage = document.getElementById('statusMessage');
            statusMessage.innerHTML = message;
            statusMessage.className = 'status ' + type;
            statusMessage.classList.remove('hidden');
        }

        function displayResults(data) {
            const resultsContainer = document.getElementById('resultsContainer');
            const resultsList = document.getElementById('resultsList');
            const resultCount = document.getElementById('resultCount');

            if (!data.results || data.results.length === 0) {
                resultsList.innerHTML = '<div class="no-results">No results found. Try a different search query.</div>';
                resultCount.textContent = '(0 results)';
            } else {
                resultCount.textContent = '(' + data.count + ' result' + (data.count !== 1 ? 's' : '') + ')';
                
                resultsList.innerHTML = data.results.map(function(item) {
                    return '<div class="result-item">' +
                        '<div class="result-title">' + escapeHtml(item.name) + '</div>' +
                        '<div class="result-description">' + escapeHtml(item.description) + '</div>' +
                        '<div class="result-meta">' +
                        '<span>[Category] ' + escapeHtml(item.category) + '</span>' +
                        '<span class="price">[Price] $' + item.price.toFixed(2) + '</span>' +
                        '<span>[Region] ' + escapeHtml(item.region) + '</span>' +
                        '</div></div>';
                }).join('');
            }

            resultsContainer.classList.remove('hidden');
        }

        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        window.addEventListener('load', function() {
            setTimeout(function() {
                performSearch(new Event('submit'));
            }, 1000);
        });
    </script>
</body>
</html>
"@
      
      # Save to temp file
      $tempFile = New-TemporaryFile
      Set-Content -Path $tempFile.FullName -Value $indexHtml -Encoding UTF8
      
      Write-Host "Uploading index.html to `$web container..."
      
      # Upload to blob storage
      $maxRetries = 3
      $retryCount = 0
      $uploaded = $false
      
      while (-not $uploaded -and $retryCount -lt $maxRetries) {
        try {
          $retryCount++
          Write-Host "Upload attempt $retryCount of $maxRetries..."
          
          az storage blob upload `
            --account-name $storageAccountName `
            --account-key $storageKey `
            --container-name '$web' `
            --name 'index.html' `
            --file $tempFile.FullName `
            --content-type 'text/html' `
            --overwrite
          
          $uploaded = $true
          Write-Host "Frontend uploaded successfully!"
        }
        catch {
          Write-Host "Upload attempt $retryCount failed: $($_.Exception.Message)"
          if ($retryCount -lt $maxRetries) {
            Write-Host "Retrying in 10 seconds..."
            Start-Sleep -Seconds 10
          }
        }
      }
      
      if (-not $uploaded) {
        throw "Failed to upload frontend after $maxRetries attempts"
      }
      
      # Cleanup
      Remove-Item -Path $tempFile.FullName -Force -ErrorAction SilentlyContinue
      
      Write-Host "Frontend deployment complete!"
      Write-Host "URL: https://$storageAccountName.z13.web.core.windows.net/"
    '''
  }
}

// Create managed identity for deployment script
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'frontend-deploy-identity'
  location: location
}

// Get reference to storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// Role assignment for managed identity
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedIdentity.id, storageAccount.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output deploymentStatus string = frontendDeploy.properties.provisioningState
