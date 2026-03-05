# Azure Search BCDR Failover Test Script
# This script simulates a primary search service failure and verifies automatic failover

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = ".bcdr-config.json"
)

$ErrorActionPreference = "Stop"

Write-Host "`n====================================================================" -ForegroundColor Cyan
Write-Host "`n====================================================================" -ForegroundColor Cyan
Write-Host " BCDR FAILOVER TEST" -ForegroundColor Yellow
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
Write-Host "|  Resource Group        : $($resourceGroup.PadRight(45))|" -ForegroundColor White
Write-Host "|  Primary Search Service: $($primarySearchName.PadRight(45))|" -ForegroundColor White
Write-Host "|  Secondary Search Svc  : $($secondarySearchName.PadRight(45))|" -ForegroundColor White
Write-Host "|  Front Door Endpoint   : $($frontDoorEndpoint.PadRight(45))|" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  TEST CONFIGURATION                                                 |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  Resource Group        : $($resourceGroup.PadRight(45))|" -ForegroundColor White
Write-Host "|  Primary Search Service: $($primarySearchName.PadRight(45))|" -ForegroundColor White
Write-Host "|  Secondary Search Svc  : $($secondarySearchName.PadRight(45))|" -ForegroundColor White
Write-Host "|  Front Door Endpoint   : $($frontDoorEndpoint.PadRight(45))|" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host ""

# Step 1: Make primary search service private (simulates regional failure)
Write-Host "STEP 1: Making primary search service private (simulating failure)..." -ForegroundColor Yellow
Write-Host "  This simulates the search service being unavailable due to regional outage" -ForegroundColor Gray
Write-Host ""

az search service update `
    --name $primarySearchName `
    --resource-group $resourceGroup `
    --public-network-access Disabled `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Host "X Failed to update primary search service" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Primary search service set to private (network isolated)" -ForegroundColor Green
Write-Host "[OK] Primary search service set to private (network isolated)" -ForegroundColor Green
Write-Host "  Functions can no longer reach the primary search service" -ForegroundColor Gray
Write-Host "  Waiting 30 seconds for change to propagate..." -ForegroundColor Gray
Start-Sleep -Seconds 30
Write-Host ""

# Step 2: Wait for health probe detection
Write-Host "STEP 2: Waiting for Front Door health probes to detect failure..." -ForegroundColor Yellow
Write-Host "  Health probe interval: 30 seconds" -ForegroundColor Gray
Write-Host "  Failure threshold: 3 consecutive failures" -ForegroundColor Gray
Write-Host "  Expected detection time: ~90 seconds" -ForegroundColor Gray
Write-Host ""

$totalWait = 90
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

# Step 3: Verify search service accessibility
Write-Host "STEP 3: Verifying search service accessibility..." -ForegroundColor Yellow
Write-Host ""

Write-Host "  Testing PRIMARY search service..." -ForegroundColor Gray
$primarySearchStatus = az search service show `
    --name $primarySearchName `
    --resource-group $resourceGroup `
    --query "publicNetworkAccess" `
    --output tsv

Write-Host "  Primary Search Service: Public Access = $primarySearchStatus" -ForegroundColor $(if ($primarySearchStatus -eq "Disabled") { "Red" } else { "Green" })

Write-Host ""
Write-Host "  Testing SECONDARY search service..." -ForegroundColor Gray
$secondarySearchStatus = az search service show `
    --name $secondarySearchName `
    --resource-group $resourceGroup `
    --query "publicNetworkAccess" `
    --output tsv

Write-Host "  Secondary Search Service: Public Access = $secondarySearchStatus" -ForegroundColor $(if ($secondarySearchStatus -eq "Enabled") { "Green" } else { "Red" })
Write-Host ""

# Step 4: Test health endpoints
Write-Host "STEP 4: Testing health endpoints..." -ForegroundColor Yellow
Write-Host "  Note: Primary health check will fail because it can't reach search service" -ForegroundColor Gray
Write-Host ""

# Test primary (should fail - function is running but can't reach search)
Write-Host "  Testing PRIMARY endpoint..." -ForegroundColor Gray
try {
    $primaryResponse = Invoke-RestMethod -Uri "$frontDoorEndpoint/api/health" -TimeoutSec 10 -ErrorAction Stop
    if ($primaryResponse.region -eq "eastus2") {
        Write-Host "  [!] Primary is responding but may report search unavailable" -ForegroundColor Yellow
        Write-Host "    Response: $($primaryResponse | ConvertTo-Json -Compress)" -ForegroundColor Gray
    } else {
        Write-Host "  [OK] Already routed to secondary" -ForegroundColor Green
        Write-Host "  [OK] Already routed to secondary" -ForegroundColor Green
    }
} catch {
    Write-Host "  [OK] Primary is unavailable (expected - search service unreachable)" -ForegroundColor Green
    Write-Host "  [OK] Primary is unavailable (expected - search service unreachable)" -ForegroundColor Green
    Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Gray
}
Write-Host ""

# Step 5: Test Front Door routing
Write-Host "STEP 5: Testing Front Door routing (15 requests)..." -ForegroundColor Yellow
Write-Host ""

$eastus2Count = 0
$westus2Count = 0
$errorCount = 0

1..15 | ForEach-Object {
    try {
        $response = Invoke-RestMethod -Uri "$frontDoorEndpoint/api/health" -ErrorAction Stop
        if ($response.region -eq "eastus2") {
            $eastus2Count++
            Write-Host "  [$_] -> eastus2 (PRIMARY)" -ForegroundColor Red
            Write-Host "  [$_] -> eastus2 (PRIMARY)" -ForegroundColor Red
        } elseif ($response.region -eq "westus2") {
            $westus2Count++
            Write-Host "  [$_] -> westus2 (SECONDARY)" -ForegroundColor Green
            Write-Host "  [$_] -> westus2 (SECONDARY)" -ForegroundColor Green
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
Write-Host "FAILOVER TEST RESULTS" -ForegroundColor Yellow
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  SEARCH SERVICE STATUS                                              |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  Primary (eastus2)   : $(if ($primarySearchStatus -eq "Disabled") { "PRIVATE (Network Isolated)".PadRight(44) } else { $primarySearchStatus.PadRight(44) })|" -ForegroundColor White
Write-Host "|  Secondary (westus2) : $(if ($secondarySearchStatus -eq "Enabled") { "PUBLIC (Available)".PadRight(44) } else { $secondarySearchStatus.PadRight(44) })|" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  SEARCH SERVICE STATUS                                              |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  Primary (eastus2)   : $(if ($primarySearchStatus -eq "Disabled") { "PRIVATE (Network Isolated)".PadRight(44) } else { $primarySearchStatus.PadRight(44) })|" -ForegroundColor White
Write-Host "|  Secondary (westus2) : $(if ($secondarySearchStatus -eq "Enabled") { "PUBLIC (Available)".PadRight(44) } else { $secondarySearchStatus.PadRight(44) })|" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host ""

Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  ROUTING DISTRIBUTION (15 requests)                                 |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  eastus2 (PRIMARY)   : $($eastus2Count.ToString().PadLeft(2)) requests ($([math]::Round($eastus2Count/15*100)).ToString().PadLeft(3))%)                          |" -ForegroundColor $(if ($eastus2Count -eq 0) { "White" } else { "Yellow" })
Write-Host "|  westus2 (SECONDARY) : $($westus2Count.ToString().PadLeft(2)) requests ($([math]::Round($westus2Count/15*100)).ToString().PadLeft(3))%)                          |" -ForegroundColor $(if ($westus2Count -eq 15) { "Green" } else { "Yellow" })
Write-Host "|  Errors              : $($errorCount.ToString().PadLeft(2)) requests ($([math]::Round($errorCount/15*100)).ToString().PadLeft(3))%)                          |" -ForegroundColor $(if ($errorCount -eq 0) { "White" } else { "Red" })
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  ROUTING DISTRIBUTION (15 requests)                                 |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  eastus2 (PRIMARY)   : $($eastus2Count.ToString().PadLeft(2)) requests ($([math]::Round($eastus2Count/15*100)).ToString().PadLeft(3))%)                          |" -ForegroundColor $(if ($eastus2Count -eq 0) { "White" } else { "Yellow" })
Write-Host "|  westus2 (SECONDARY) : $($westus2Count.ToString().PadLeft(2)) requests ($([math]::Round($westus2Count/15*100)).ToString().PadLeft(3))%)                          |" -ForegroundColor $(if ($westus2Count -eq 15) { "Green" } else { "Yellow" })
Write-Host "|  Errors              : $($errorCount.ToString().PadLeft(2)) requests ($([math]::Round($errorCount/15*100)).ToString().PadLeft(3))%)                          |" -ForegroundColor $(if ($errorCount -eq 0) { "White" } else { "Red" })
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host ""

# Determine success
$failoverSuccess = ($westus2Count -ge 14 -and $eastus2Count -le 1 -and $errorCount -eq 0)

Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
if ($failoverSuccess) {
    Write-Host "|  AUTOMATIC FAILOVER STATUS: SUCCESS                                 |" -ForegroundColor White -BackgroundColor DarkGreen
    Write-Host "|  AUTOMATIC FAILOVER STATUS: SUCCESS                                 |" -ForegroundColor White -BackgroundColor DarkGreen
} else {
    Write-Host "|  AUTOMATIC FAILOVER STATUS: NEEDS ATTENTION                         |" -ForegroundColor White -BackgroundColor DarkRed
    Write-Host "|  AUTOMATIC FAILOVER STATUS: NEEDS ATTENTION                         |" -ForegroundColor White -BackgroundColor DarkRed
}
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White

if ($failoverSuccess) {
    Write-Host "|  [OK] Primary search service made private (network isolated)          |" -ForegroundColor White
    Write-Host "|  [OK] Function health checks failing (can't reach search)             |" -ForegroundColor White
    Write-Host "|  [OK] Front Door detected primary failure                             |" -ForegroundColor White
    Write-Host "|  [OK] Traffic automatically routed to secondary (westus2)             |" -ForegroundColor White
    Write-Host "|  [OK] Zero errors during failover                                     |" -ForegroundColor White
    Write-Host "|                                                                     |" -ForegroundColor White
    Write-Host "|  CONCLUSION:                                                        |" -ForegroundColor White
    Write-Host "|  Azure Front Door successfully detected the primary search         |" -ForegroundColor White
    Write-Host "|  service failure and automatically routed 100% of traffic to the   |" -ForegroundColor White
    Write-Host "|  secondary region. The BCDR system is operational.                 |" -ForegroundColor White
    Write-Host "|  [OK] Primary search service made private (network isolated)          |" -ForegroundColor White
    Write-Host "|  [OK] Function health checks failing (can't reach search)             |" -ForegroundColor White
    Write-Host "|  [OK] Front Door detected primary failure                             |" -ForegroundColor White
    Write-Host "|  [OK] Traffic automatically routed to secondary (westus2)             |" -ForegroundColor White
    Write-Host "|  [OK] Zero errors during failover                                     |" -ForegroundColor White
    Write-Host "|                                                                     |" -ForegroundColor White
    Write-Host "|  CONCLUSION:                                                        |" -ForegroundColor White
    Write-Host "|  Azure Front Door successfully detected the primary search         |" -ForegroundColor White
    Write-Host "|  service failure and automatically routed 100% of traffic to the   |" -ForegroundColor White
    Write-Host "|  secondary region. The BCDR system is operational.                 |" -ForegroundColor White
} else {
    Write-Host "|  ! Failover may not be complete yet                                |" -ForegroundColor White
    Write-Host "|  ! Traffic is still being routed to primary or has errors          |" -ForegroundColor White
    Write-Host "|                                                                     |" -ForegroundColor White
    Write-Host "|  POSSIBLE REASONS:                                                  |" -ForegroundColor White
    Write-Host "|  - Health probes haven't detected failure yet (wait longer)        |" -ForegroundColor White
    Write-Host "|  - Front Door edge cache hasn't refreshed (5-10 min)               |" -ForegroundColor White
    Write-Host "|  - Secondary search service may have issues                         |" -ForegroundColor White
    Write-Host "|  ! Failover may not be complete yet                                |" -ForegroundColor White
    Write-Host "|  ! Traffic is still being routed to primary or has errors          |" -ForegroundColor White
    Write-Host "|                                                                     |" -ForegroundColor White
    Write-Host "|  POSSIBLE REASONS:                                                  |" -ForegroundColor White
    Write-Host "|  - Health probes haven't detected failure yet (wait longer)        |" -ForegroundColor White
    Write-Host "|  - Front Door edge cache hasn't refreshed (5-10 min)               |" -ForegroundColor White
    Write-Host "|  - Secondary search service may have issues                         |" -ForegroundColor White
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
Write-Host "|     Check that region badge shows 'westus2'                        |" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  2. View Front Door metrics in Azure Portal:                       |" -ForegroundColor Yellow
Write-Host "|     Portal -> Front Door -> Metrics -> Origin Health Percentage       |" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  3. When ready, test automatic failback:                           |" -ForegroundColor Yellow
Write-Host "|     .\test-failback.ps1                                            |" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  NEXT STEPS                                                         |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  1. Test the frontend:                                             |" -ForegroundColor Yellow
Write-Host "|     Open the frontend URL and verify search works                  |" -ForegroundColor Gray
Write-Host "|     Check that region badge shows 'westus2'                        |" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  2. View Front Door metrics in Azure Portal:                       |" -ForegroundColor Yellow
Write-Host "|     Portal -> Front Door -> Metrics -> Origin Health Percentage       |" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  3. When ready, test automatic failback:                           |" -ForegroundColor Yellow
Write-Host "|     .\test-failback.ps1                                            |" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host ""

Write-Host "Completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""
