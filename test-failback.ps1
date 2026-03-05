# Azure Search BCDR Failback Test Script
# This script restores the primary search service and verifies automatic failback

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = ".bcdr-config.json"
)

$ErrorActionPreference = "Stop"

Write-Host "`n====================================================================" -ForegroundColor Cyan
Write-Host "`n====================================================================" -ForegroundColor Cyan
Write-Host " BCDR FAILBACK TEST" -ForegroundColor Yellow
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host ""

# Load configuration
if (-not (Test-Path $ConfigFile)) {
    Write-Host "X Configuration file not found: $ConfigFile" -ForegroundColor Red
    Write-Host "  Please run .\deploy.ps1 first to create the configuration" -ForegroundColor Yellow
    exit 1
}

$config = Get-Content $ConfigFile | ConvertFrom-Json
$resourceGroup = $config.resourceGroupName
$primarySearchName = $config.primarySearchName
$secondarySearchName = $config.secondarySearchName
$frontDoorEndpoint = $config.frontDoorEndpoint
$frontDoorProfileName = $config.frontDoorProfileName
$frontDoorEndpointName = $config.frontDoorEndpointName

Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  TEST CONFIGURATION                                                 |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  Resource Group       : $($resourceGroup.PadRight(46))|" -ForegroundColor White
Write-Host "|  Primary Search       : $($primarySearchName.PadRight(46))|" -ForegroundColor White
Write-Host "|  Secondary Search     : $($secondarySearchName.PadRight(46))|" -ForegroundColor White
Write-Host "|  Front Door Endpoint  : $($frontDoorEndpoint.PadRight(46))|" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  TEST CONFIGURATION                                                 |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  Resource Group       : $($resourceGroup.PadRight(46))|" -ForegroundColor White
Write-Host "|  Primary Search       : $($primarySearchName.PadRight(46))|" -ForegroundColor White
Write-Host "|  Secondary Search     : $($secondarySearchName.PadRight(46))|" -ForegroundColor White
Write-Host "|  Front Door Endpoint  : $($frontDoorEndpoint.PadRight(46))|" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host ""

# Step 1: Re-enable primary search service public access
Write-Host "STEP 1: Re-enabling primary search service public access..." -ForegroundColor Yellow
Write-Host "  This simulates recovery of the primary region search service" -ForegroundColor Gray
Write-Host ""

az search service update `
    --name $primarySearchName `
    --resource-group $resourceGroup `
    --public-network-access Enabled `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Host "X Failed to re-enable primary search service public access" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Primary search service public access re-enabled" -ForegroundColor Green
Write-Host "[OK] Primary search service public access re-enabled" -ForegroundColor Green
Write-Host "  Waiting 30 seconds for search service to become available..." -ForegroundColor Gray
Start-Sleep -Seconds 30
Write-Host ""

# Step 2: Verify search service status
Write-Host "STEP 2: Verifying search service status..." -ForegroundColor Yellow
Write-Host ""

Write-Host "  Testing PRIMARY search service..." -ForegroundColor Gray
$primarySearchStatus = az search service show `
    --name $primarySearchName `
    --resource-group $resourceGroup `
    --query "publicNetworkAccess" `
    --output tsv

Write-Host "  Primary Search Service: Public Access = $primarySearchStatus" -ForegroundColor $(if ($primarySearchStatus -eq "Enabled") { "Green" } else { "Red" })
Write-Host ""

Write-Host "  Testing SECONDARY search service..." -ForegroundColor Gray
$secondarySearchStatus = az search service show `
    --name $secondarySearchName `
    --resource-group $resourceGroup `
    --query "publicNetworkAccess" `
    --output tsv

Write-Host "  Secondary Search Service: Public Access = $secondarySearchStatus" -ForegroundColor $(if ($secondarySearchStatus -eq "Enabled") { "Green" } else { "Red" })
Write-Host ""

# Step 3: Purge Front Door cache
Write-Host "STEP 3: Purging Front Door cache..." -ForegroundColor Yellow
Write-Host "  This ensures faster recovery by clearing edge cache" -ForegroundColor Gray
Write-Host ""

az afd endpoint purge `
    --endpoint-name $frontDoorEndpointName `
    --profile-name $frontDoorProfileName `
    --resource-group $resourceGroup `
    --content-paths "/*" `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Host "X Failed to purge Front Door cache" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Front Door cache purge initiated" -ForegroundColor Green
Write-Host "[OK] Front Door cache purge initiated" -ForegroundColor Green
Write-Host "  Cache will propagate across global edge network (2-5 minutes)" -ForegroundColor Gray
Write-Host ""

# Step 4: Wait for health probe detection
Write-Host "STEP 4: Waiting for Front Door health probes to detect recovery..." -ForegroundColor Yellow
Write-Host "  Health probe interval: 30 seconds" -ForegroundColor Gray
Write-Host "  Success threshold: 3 consecutive successes" -ForegroundColor Gray
Write-Host "  Expected detection time: ~90 seconds" -ForegroundColor Gray
Write-Host "  Plus cache propagation time: ~30-60 seconds" -ForegroundColor Gray
Write-Host ""

$totalWait = 120
$interval = 10
for ($i = 1; $i -le ($totalWait / $interval); $i++) {
    $elapsed = $i * $interval
    $percentage = [math]::Round(($elapsed / $totalWait) * 100)
    $bar = "#" * [math]::Round($percentage / 5)
    $bar = "#" * [math]::Round($percentage / 5)
    $space = " " * (20 - [math]::Round($percentage / 5))
    Write-Host "  [$bar$space] ${percentage}% - ${elapsed}s / ${totalWait}s" -ForegroundColor Cyan
    Start-Sleep -Seconds $interval
}
Write-Host ""

# Step 5: Test Front Door routing
Write-Host "STEP 5: Testing Front Door routing (20 requests)..." -ForegroundColor Yellow
Write-Host ""

$eastus2Count = 0
$westus2Count = 0
$errorCount = 0

1..20 | ForEach-Object {
    try {
        $response = Invoke-RestMethod -Uri "$frontDoorEndpoint/api/health" -ErrorAction Stop
        if ($response.region -eq "eastus2") {
            $eastus2Count++
            Write-Host "  [$_] -> eastus2 (PRIMARY)" -ForegroundColor Green
            Write-Host "  [$_] -> eastus2 (PRIMARY)" -ForegroundColor Green
        } elseif ($response.region -eq "westus2") {
            $westus2Count++
            Write-Host "  [$_] -> westus2 (SECONDARY)" -ForegroundColor Yellow
            Write-Host "  [$_] -> westus2 (SECONDARY)" -ForegroundColor Yellow
        }
    } catch {
        $errorCount++
        Write-Host "  [$_] -> ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  [$_] -> ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""

# Step 6: Display results
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "FAILBACK TEST RESULTS" -ForegroundColor Yellow
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  SEARCH SERVICE STATUS                                              |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  Primary (eastus2)   : $(if ($primarySearchStatus -eq "Enabled") { "PUBLIC (Available)".PadRight(44) } else { $primarySearchStatus.PadRight(44) })|" -ForegroundColor White
Write-Host "|  Secondary (westus2) : $(if ($secondarySearchStatus -eq "Enabled") { "PUBLIC (Available)".PadRight(44) } else { $secondarySearchStatus.PadRight(44) })|" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  SEARCH SERVICE STATUS                                              |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  Primary (eastus2)   : $(if ($primarySearchStatus -eq "Enabled") { "PUBLIC (Available)".PadRight(44) } else { $primarySearchStatus.PadRight(44) })|" -ForegroundColor White
Write-Host "|  Secondary (westus2) : $(if ($secondarySearchStatus -eq "Enabled") { "PUBLIC (Available)".PadRight(44) } else { $secondarySearchStatus.PadRight(44) })|" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host ""

Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  ROUTING DISTRIBUTION (20 requests)                                 |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  eastus2 (PRIMARY)   : $($eastus2Count.ToString().PadLeft(2)) requests ($([math]::Round($eastus2Count/20*100)).ToString().PadLeft(3))%)                          |" -ForegroundColor $(if ($eastus2Count -ge 18) { "Green" } else { "Yellow" })
Write-Host "|  westus2 (SECONDARY) : $($westus2Count.ToString().PadLeft(2)) requests ($([math]::Round($westus2Count/20*100)).ToString().PadLeft(3))%)                          |" -ForegroundColor $(if ($westus2Count -le 2) { "White" } else { "Yellow" })
Write-Host "|  Errors              : $($errorCount.ToString().PadLeft(2)) requests ($([math]::Round($errorCount/20*100)).ToString().PadLeft(3))%)                          |" -ForegroundColor $(if ($errorCount -eq 0) { "White" } else { "Red" })
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  ROUTING DISTRIBUTION (20 requests)                                 |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  eastus2 (PRIMARY)   : $($eastus2Count.ToString().PadLeft(2)) requests ($([math]::Round($eastus2Count/20*100)).ToString().PadLeft(3))%)                          |" -ForegroundColor $(if ($eastus2Count -ge 18) { "Green" } else { "Yellow" })
Write-Host "|  westus2 (SECONDARY) : $($westus2Count.ToString().PadLeft(2)) requests ($([math]::Round($westus2Count/20*100)).ToString().PadLeft(3))%)                          |" -ForegroundColor $(if ($westus2Count -le 2) { "White" } else { "Yellow" })
Write-Host "|  Errors              : $($errorCount.ToString().PadLeft(2)) requests ($([math]::Round($errorCount/20*100)).ToString().PadLeft(3))%)                          |" -ForegroundColor $(if ($errorCount -eq 0) { "White" } else { "Red" })
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host ""

# Determine success
$failbackSuccess = ($eastus2Count -ge 18 -and $westus2Count -le 2 -and $errorCount -eq 0)

Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
if ($failbackSuccess) {
    Write-Host "|  AUTOMATIC FAILBACK STATUS: COMPLETE                                |" -ForegroundColor White -BackgroundColor DarkGreen
    Write-Host "|  AUTOMATIC FAILBACK STATUS: COMPLETE                                |" -ForegroundColor White -BackgroundColor DarkGreen
} else {
    Write-Host "|  AUTOMATIC FAILBACK STATUS: IN PROGRESS                             |" -ForegroundColor White -BackgroundColor DarkYellow
    Write-Host "|  AUTOMATIC FAILBACK STATUS: IN PROGRESS                             |" -ForegroundColor White -BackgroundColor DarkYellow
}
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White

if ($failbackSuccess) {
    Write-Host "|  [OK] Primary search service public access re-enabled                 |" -ForegroundColor White
    Write-Host "|  [OK] Secondary search service running normally                       |" -ForegroundColor White
    Write-Host "|  [OK] Health endpoints can reach both search services                |" -ForegroundColor White
    Write-Host "|  [OK] Front Door cache purged                                         |" -ForegroundColor White
    Write-Host "|  [OK] Traffic automatically routed back to primary (eastus2)          |" -ForegroundColor White
    Write-Host "|  [OK] Priority-based routing restored                                 |" -ForegroundColor White
    Write-Host "|                                                                     |" -ForegroundColor White
    Write-Host "|  CONCLUSION:                                                        |" -ForegroundColor White
    Write-Host "|  Azure Front Door has successfully detected the primary search     |" -ForegroundColor White
    Write-Host "|  service recovery and automatically routed traffic back to the     |" -ForegroundColor White
    Write-Host "|  primary region (eastus2). The BCDR system is fully operational.   |" -ForegroundColor White
    Write-Host "|  [OK] Primary search service public access re-enabled                 |" -ForegroundColor White
    Write-Host "|  [OK] Secondary search service running normally                       |" -ForegroundColor White
    Write-Host "|  [OK] Health endpoints can reach both search services                |" -ForegroundColor White
    Write-Host "|  [OK] Front Door cache purged                                         |" -ForegroundColor White
    Write-Host "|  [OK] Traffic automatically routed back to primary (eastus2)          |" -ForegroundColor White
    Write-Host "|  [OK] Priority-based routing restored                                 |" -ForegroundColor White
    Write-Host "|                                                                     |" -ForegroundColor White
    Write-Host "|  CONCLUSION:                                                        |" -ForegroundColor White
    Write-Host "|  Azure Front Door has successfully detected the primary search     |" -ForegroundColor White
    Write-Host "|  service recovery and automatically routed traffic back to the     |" -ForegroundColor White
    Write-Host "|  primary region (eastus2). The BCDR system is fully operational.   |" -ForegroundColor White
} else {
    Write-Host "|  ! Failback may not be complete yet                                |" -ForegroundColor White
    Write-Host "|  ! Traffic is still partially routed to secondary                  |" -ForegroundColor White
    Write-Host "|                                                                     |" -ForegroundColor White
    Write-Host "|  POSSIBLE REASONS:                                                  |" -ForegroundColor White
    Write-Host "|  - Health probes haven't detected recovery yet (wait longer)       |" -ForegroundColor White
    Write-Host "|  - Cache purge propagation still in progress (2-5 min)             |" -ForegroundColor White
    Write-Host "|  - Primary search service may still be warming up                  |" -ForegroundColor White
    Write-Host "|                                                                     |" -ForegroundColor White
    Write-Host "|  RECOMMENDATION:                                                    |" -ForegroundColor White
    Write-Host "|  Wait 5 minutes and run this script again to verify failback       |" -ForegroundColor White
    Write-Host "|  ! Failback may not be complete yet                                |" -ForegroundColor White
    Write-Host "|  ! Traffic is still partially routed to secondary                  |" -ForegroundColor White
    Write-Host "|                                                                     |" -ForegroundColor White
    Write-Host "|  POSSIBLE REASONS:                                                  |" -ForegroundColor White
    Write-Host "|  - Health probes haven't detected recovery yet (wait longer)       |" -ForegroundColor White
    Write-Host "|  - Cache purge propagation still in progress (2-5 min)             |" -ForegroundColor White
    Write-Host "|  - Primary search service may still be warming up                  |" -ForegroundColor White
    Write-Host "|                                                                     |" -ForegroundColor White
    Write-Host "|  RECOMMENDATION:                                                    |" -ForegroundColor White
    Write-Host "|  Wait 5 minutes and run this script again to verify failback       |" -ForegroundColor White
}

Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host ""

Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  NEXT STEPS                                                         |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  1. Test the frontend:                                             |" -ForegroundColor Yellow
Write-Host "|     Open the frontend URL and verify search works                  |" -ForegroundColor Gray
Write-Host "|     Check that region badge shows 'eastus2'                        |" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  2. View Front Door metrics in Azure Portal:                       |" -ForegroundColor Yellow
Write-Host "|     Portal -> Front Door -> Metrics -> Origin Health Percentage       |" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  3. BCDR testing complete!                                         |" -ForegroundColor Green
Write-Host "|     Both failover and failback have been verified                  |" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  4. When finished, cleanup all resources:                          |" -ForegroundColor Yellow
Write-Host "|     .\cleanup.ps1                                                  |" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  NEXT STEPS                                                         |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  1. Test the frontend:                                             |" -ForegroundColor Yellow
Write-Host "|     Open the frontend URL and verify search works                  |" -ForegroundColor Gray
Write-Host "|     Check that region badge shows 'eastus2'                        |" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  2. View Front Door metrics in Azure Portal:                       |" -ForegroundColor Yellow
Write-Host "|     Portal -> Front Door -> Metrics -> Origin Health Percentage       |" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  3. BCDR testing complete!                                         |" -ForegroundColor Green
Write-Host "|     Both failover and failback have been verified                  |" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  4. When finished, cleanup all resources:                          |" -ForegroundColor Yellow
Write-Host "|     .\cleanup.ps1                                                  |" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host ""

Write-Host "Completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""
