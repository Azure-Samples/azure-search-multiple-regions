# Azure Search BCDR Deployment Script
# This script deploys the complete BCDR infrastructure with Azure Front Door

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "westus2",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("indexer", "changefeed")]
    [string]$SyncMethod = "indexer",
    
    [Parameter(Mandatory=$false)]
    [string]$ParametersFile = "bicep/main.parameters.json"
)

$ErrorActionPreference = "Stop"

Write-Host "`n====================================================================" -ForegroundColor Cyan
Write-Host "`n====================================================================" -ForegroundColor Cyan
Write-Host " AZURE SEARCH BCDR DEPLOYMENT" -ForegroundColor Yellow
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Sync Method: $SyncMethod" -ForegroundColor Yellow
if ($SyncMethod -eq "indexer") {
    Write-Host "  -> Scheduled indexers will sync data every 5 minutes" -ForegroundColor Gray
} else {
    Write-Host "  -> Change feed will sync data in real-time" -ForegroundColor Gray
}
Write-Host ""

# Check if logged in to Azure
Write-Host "Checking Azure CLI login status..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Not logged in. Please log in to Azure..." -ForegroundColor Red
    az login
    $account = az account show | ConvertFrom-Json
}

Write-Host "[OK] Logged in as: $($account.user.name)" -ForegroundColor Green
Write-Host "[OK] Subscription: $($account.name) ($($account.id))" -ForegroundColor Green
Write-Host ""

# Check if resource group exists
Write-Host "Checking resource group: $ResourceGroupName..." -ForegroundColor Yellow
$rgExists = az group exists --name $ResourceGroupName --output tsv
if ($rgExists -eq "true") {
    $existingRg = az group show --name $ResourceGroupName --output json | ConvertFrom-Json
    Write-Host "[OK] Using existing resource group in $($existingRg.location)" -ForegroundColor Green
} else {
    Write-Host "Creating resource group: $ResourceGroupName in $Location..." -ForegroundColor Yellow
    az group create --name $ResourceGroupName --location $Location --output none
    Write-Host "[OK] Resource group created" -ForegroundColor Green
}
Write-Host ""

# Deploy infrastructure
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  DEPLOYING INFRASTRUCTURE (15-20 minutes)                           |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|   > Azure AI Search services (2 regions)                            |" -ForegroundColor Gray
Write-Host "|   > Azure Functions (2 regions)                                     |" -ForegroundColor Gray
Write-Host "|   > Azure Front Door (global SSL termination)                       |" -ForegroundColor Gray
Write-Host "|   > Cosmos DB NoSQL (serverless)                                    |" -ForegroundColor Gray
Write-Host "|   > Data population (50 sample products)                            |" -ForegroundColor Gray
if ($SyncMethod -eq "indexer") {
    Write-Host "|   > Search indexers (5-minute schedule)                             |" -ForegroundColor Gray
} else {
    Write-Host "|   > Change feed triggers (real-time sync)                           |" -ForegroundColor Gray
}
Write-Host "|   > Function code deployment (automatic)                            |" -ForegroundColor Gray
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host ""

# Validate deployment first
Write-Host "Validating deployment template..." -ForegroundColor Yellow
$validateOutput = az deployment group validate `
    --resource-group $ResourceGroupName `
    --template-file bicep/main.bicep `
    --parameters "@$ParametersFile" `
    --parameters syncMethod=$SyncMethod `
    --output json 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "X Template validation failed:" -ForegroundColor Red
    Write-Host "$validateOutput" -ForegroundColor Red
    Write-Host ""
    exit 1
}

Write-Host "[OK] Template validation passed" -ForegroundColor Green
Write-Host ""

# Start deployment
Write-Host "Starting deployment (this will take 15-20 minutes)..." -ForegroundColor Yellow
Write-Host ""

try {
    # Start deployment with error capture
    $deployOutput = az deployment group create `
        --resource-group $ResourceGroupName `
        --template-file bicep/main.bicep `
        --parameters "@$ParametersFile" `
        --parameters syncMethod=$SyncMethod `
        --name main `
        --no-wait `
        --output json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "X Failed to start deployment" -ForegroundColor Red
        Write-Host "Error details:" -ForegroundColor Yellow
        Write-Host "$deployOutput" -ForegroundColor Red
        Write-Host ""
        exit 1
    }
    
    Write-Host "[OK] Deployment started successfully" -ForegroundColor Green
    Write-Host ""
    Write-Host "Waiting for deployment to complete..." -ForegroundColor Yellow
    Write-Host "  (Checking status every 30 seconds)" -ForegroundColor Gray
    Write-Host ""
    
    # Poll deployment status
    $maxWaitMinutes = 30
    $waitSeconds = 0
    $checkInterval = 30
    $lastState = ""
    
    while ($waitSeconds -lt ($maxWaitMinutes * 60)) {
        Start-Sleep -Seconds $checkInterval
        $waitSeconds += $checkInterval
        
        # Check deployment status (do NOT suppress errors)
        $statusOutput = az deployment group show `
            --resource-group $ResourceGroupName `
            --name main `
            --query "properties.provisioningState" `
            --output tsv 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "" -ForegroundColor Red
            Write-Host "X Error checking deployment status:" -ForegroundColor Red
            Write-Host "$statusOutput" -ForegroundColor Red
            Write-Host "" -ForegroundColor Red
            continue
        }
        
        $status = $statusOutput
        
        if ($status -and $status -ne $lastState) {
            $lastState = $status
            $elapsed = [math]::Floor($waitSeconds / 60)
            
            if ($status -eq "Succeeded") {
                Write-Host "[OK] Deployment completed successfully! (${elapsed}m)" -ForegroundColor Green
                break
            }
            elseif ($status -eq "Failed") {
                Write-Host "X Deployment failed after ${elapsed} minutes" -ForegroundColor Red
                Write-Host ""
                
                # Get detailed error information from failed operations
                Write-Host "===================================================================" -ForegroundColor Red
                Write-Host "DEPLOYMENT FAILED - Error Details:" -ForegroundColor Yellow
                Write-Host "===================================================================" -ForegroundColor Red
                Write-Host ""
                
                $failedOpsJson = az deployment operation group list `
                    --resource-group $ResourceGroupName `
                    --name main `
                    --query "[?properties.provisioningState=='Failed']" `
                    --output json 2>&1
                
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "Error retrieving deployment operations:" -ForegroundColor Red
                    Write-Host "$failedOpsJson" -ForegroundColor Red
                    Write-Host ""
                    exit 1
                }
                
                $failedOps = $failedOpsJson | ConvertFrom-Json
                
                if ($failedOps -and $failedOps.Count -gt 0) {
                    Write-Host "Failed Resources ($($failedOps.Count)):" -ForegroundColor Yellow
                    foreach ($op in $failedOps) {
                        $resourceName = $op.properties.targetResource.resourceName
                        $resourceType = $op.properties.targetResource.resourceType
                        $errorCode = $op.properties.statusMessage.error.code
                        $errorMessage = $op.properties.statusMessage.error.message
                        
                        Write-Host ""
                        Write-Host "-------------------------------------------------------------------" -ForegroundColor DarkGray
                        Write-Host "Resource: $resourceName" -ForegroundColor Cyan
                        Write-Host "Type: $resourceType" -ForegroundColor Gray
                        Write-Host "Error Code: $errorCode" -ForegroundColor Red
                        Write-Host "Message:" -ForegroundColor Yellow
                        Write-Host "  $errorMessage" -ForegroundColor White
                        
                        # Show ALL error details at all levels
                        if ($op.properties.statusMessage.error.details) {
                            Write-Host "Additional Details:" -ForegroundColor Yellow
                            foreach ($detail in $op.properties.statusMessage.error.details) {
                                if ($detail.code) {
                                    Write-Host "  - $($detail.code): $($detail.message)" -ForegroundColor Gray
                                }
                                if ($detail.details) {
                                    foreach ($innerDetail in $detail.details) {
                                        Write-Host "    -> $($innerDetail.code): $($innerDetail.message)" -ForegroundColor DarkGray
                                    }
                                }
                            }
                        }
                    }
                    Write-Host ""
                    Write-Host "===================================================================" -ForegroundColor Red
                } else {
                    # Fallback to top-level error if no operation details
                    Write-Host "Retrieving top-level error details..." -ForegroundColor Yellow
                    $errorJson = az deployment group show `
                        --resource-group $ResourceGroupName `
                        --name main `
                        --query "properties.error" `
                        --output json 2>&1
                    
                    if ($LASTEXITCODE -eq 0 -and $errorJson) {
                        $deployError = $errorJson | ConvertFrom-Json
                        if ($deployError) {
                            Write-Host "Error Code: $($deployError.code)" -ForegroundColor Red
                            Write-Host "Message: $($deployError.message)" -ForegroundColor Red
                            
                            if ($deployError.details) {
                                Write-Host "Details:" -ForegroundColor Yellow
                                foreach ($detail in $deployError.details) {
                                    Write-Host "  - $($detail.code): $($detail.message)" -ForegroundColor Gray
                                }
                            }
                        }
                    } else {
                        Write-Host "Could not retrieve error details. Check Azure Portal." -ForegroundColor Red
                        Write-Host "Raw output: $errorJson" -ForegroundColor DarkGray
                    }
                    Write-Host ""
                    Write-Host "===================================================================" -ForegroundColor Red
                }
                
                # Show troubleshooting guidance
                Write-Host ""
                Write-Host "TROUBLESHOOTING STEPS:" -ForegroundColor Cyan
                Write-Host "1. Check the error details above for specific resource failures" -ForegroundColor White
                Write-Host "2. Common issues:" -ForegroundColor White
                Write-Host "   - Quota limits (check Azure Portal > Subscriptions > Usage + quotas)" -ForegroundColor Gray
                Write-Host "   - Resource name conflicts (try changing projectName in parameters)" -ForegroundColor Gray
                Write-Host "   - Region availability (ensure services available in chosen regions)" -ForegroundColor Gray
                Write-Host "3. View full deployment in Azure Portal:" -ForegroundColor White
                Write-Host "   Resource Groups > $ResourceGroupName > Deployments > main" -ForegroundColor Gray
                Write-Host "4. For quota issues, request increase in Azure Portal" -ForegroundColor White
                Write-Host ""
                exit 1
            }
            elseif ($status -eq "Running") {
                Write-Host "  [${elapsed}m] Deployment in progress..." -ForegroundColor Cyan
            }
            else {
                Write-Host "  [${elapsed}m] Status: $status" -ForegroundColor Gray
            }
        }
    }
    
    if ($waitSeconds -ge ($maxWaitMinutes * 60)) {
        Write-Host "X Deployment timed out after $maxWaitMinutes minutes" -ForegroundColor Red
        Write-Host "  Check Azure Portal for deployment status" -ForegroundColor Yellow
        exit 1
    }
    
    # Get deployment outputs
    $deploymentJson = az deployment group show --resource-group $ResourceGroupName --name main --output json | ConvertFrom-Json
    
    if (-not $deploymentJson) {
        Write-Host "X Failed to retrieve deployment outputs" -ForegroundColor Red
        exit 1
    }
    
    $deployment = $deploymentJson
    Write-Host ""
}
catch {
    Write-Host "X Deployment error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Extract deployment outputs
$outputs = $deployment.properties.outputs

# Store outputs for other scripts
$config = @{
    resourceGroupName = $ResourceGroupName
    primaryFunctionName = $outputs.primaryFunctionName.value
    secondaryFunctionName = $outputs.secondaryFunctionName.value
    primarySearchName = $outputs.primarySearchName.value
    secondarySearchName = $outputs.secondarySearchName.value
    frontDoorEndpoint = $outputs.frontDoorEndpoint.value
    frontDoorProfileName = $outputs.frontDoorProfileName.value
    frontDoorEndpointName = $outputs.frontDoorEndpointName.value
    primaryRegion = $outputs.primaryRegion.value
    secondaryRegion = $outputs.secondaryRegion.value
    syncMethod = $SyncMethod
    cosmosAccountName = $outputs.cosmosAccountName.value
}

$config | ConvertTo-Json | Out-File -FilePath ".bcdr-config.json" -Encoding UTF8

# Configure frontend with Front Door URL
Write-Host "Configuring frontend with Front Door URL..." -ForegroundColor Yellow
$htmlPath = "frontend\index.html"

if (Test-Path $htmlPath) {
    $htmlContent = Get-Content $htmlPath -Raw
    $frontDoorUrl = $outputs.frontDoorEndpoint.value
    
    # Replace the TRAFFIC_MANAGER_URL constant with the Front Door URL
    $updatedContent = $htmlContent -replace "const TRAFFIC_MANAGER_URL = '[^']*';", "const TRAFFIC_MANAGER_URL = '$frontDoorUrl';"
    Set-Content -Path $htmlPath -Value $updatedContent -NoNewline
    
    Write-Host "[OK] Frontend configured with Front Door endpoint" -ForegroundColor Green
} else {
    Write-Host "[!] Frontend file not found: $htmlPath" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "`n====================================================================" -ForegroundColor Cyan
Write-Host "  DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  DEPLOYED RESOURCES                                                 |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  Front Door URL (single endpoint):                                 |" -ForegroundColor Yellow
Write-Host "|    $($outputs.frontDoorEndpoint.value.PadRight(65))|" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  Primary Search Service (westus2):                                 |" -ForegroundColor Yellow
Write-Host "|    $($outputs.primarySearchEndpoint.value.PadRight(65))|" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  Secondary Search Service (westus3):                               |" -ForegroundColor Yellow
Write-Host "|    $($outputs.secondarySearchEndpoint.value.PadRight(65))|" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  Primary Function (westus2):                                       |" -ForegroundColor Yellow
Write-Host "|    $($outputs.primaryFunctionUrl.value.PadRight(65))|" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  Secondary Function (westus3):                                     |" -ForegroundColor Yellow
Write-Host "|    $($outputs.secondaryFunctionUrl.value.PadRight(65))|" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  Cosmos DB:                                                         |" -ForegroundColor Yellow
Write-Host "|    $($outputs.cosmosAccountName.value.PadRight(65))|" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host ""

Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  NEXT STEPS                                                         |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  1. Test the deployment:                                           |" -ForegroundColor Yellow
Write-Host "|       Open frontend\index.html in your browser                     |" -ForegroundColor White
Write-Host "|       Frontend is pre-configured with Front Door URL               |" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  2. Test automatic failover:                                       |" -ForegroundColor Yellow
Write-Host "|       .\test-failover.ps1                                          |" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  3. Test automatic failback:                                       |" -ForegroundColor Yellow
Write-Host "|       .\test-failback.ps1                                          |" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  4. Cleanup all resources:                                         |" -ForegroundColor Yellow
Write-Host "|       .\cleanup.ps1                                                |" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host ""

Write-Host "Note: Front Door may take 15-30 minutes for initial global propagation" -ForegroundColor Gray
Write-Host "Configuration saved to .bcdr-config.json for use by test scripts" -ForegroundColor Gray
Write-Host ""
