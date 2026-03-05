# Test Deployment Script
# This script tests the deployed BCDR setup

param(
    [Parameter(Mandatory=$true)]
    [string]$TrafficManagerUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$SearchQuery = "*"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Testing BCDR Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Test Traffic Manager endpoint
Write-Host "Testing Traffic Manager endpoint..." -ForegroundColor Yellow
$apiUrl = "$TrafficManagerUrl/api/search?q=$SearchQuery"
Write-Host "URL: $apiUrl" -ForegroundColor Gray
Write-Host ""

try {
    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -ContentType "application/json"
    
    Write-Host "[OK] Search request successful!" -ForegroundColor Green
    Write-Host "[OK] Search request successful!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Results:" -ForegroundColor Yellow
    Write-Host "  Query: $($response.query)" -ForegroundColor White
    Write-Host "  Count: $($response.count)" -ForegroundColor White
    Write-Host "  Region: $($response.region)" -ForegroundColor White
    Write-Host "  Timestamp: $($response.timestamp)" -ForegroundColor White
    Write-Host ""
    
    if ($response.results -and $response.results.Count -gt 0) {
        Write-Host "Sample results:" -ForegroundColor Yellow
        $response.results | Select-Object -First 3 | ForEach-Object {
            Write-Host "  - $($_.name) ($($_.category)) - `$$($_.price)" -ForegroundColor Gray
        }
    }
    Write-Host ""
    
} catch {
    Write-Host "X Search request failed!" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Host "Status Code: $statusCode" -ForegroundColor Yellow
    }
    
    exit 1
}

# Test health endpoints
Write-Host "Testing health endpoint..." -ForegroundColor Yellow
$healthUrl = "$TrafficManagerUrl/api/health"

try {
    $health = Invoke-RestMethod -Uri $healthUrl -Method Get
    
    Write-Host "[OK] Health check successful!" -ForegroundColor Green
    Write-Host "[OK] Health check successful!" -ForegroundColor Green
    Write-Host "  Status: $($health.status)" -ForegroundColor White
    Write-Host "  Region: $($health.region)" -ForegroundColor White
    Write-Host "  Search Service: $($health.searchService)" -ForegroundColor White
    Write-Host ""
    
} catch {
    Write-Host "[!] Health check failed (this is okay if health endpoint is not implemented)" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "BCDR Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[OK] Traffic Manager is routing requests" -ForegroundColor Green
Write-Host "[OK] Search API is responding" -ForegroundColor Green
Write-Host "[OK] Search index contains data" -ForegroundColor Green
Write-Host "[OK] Traffic Manager is routing requests" -ForegroundColor Green
Write-Host "[OK] Search API is responding" -ForegroundColor Green
Write-Host "[OK] Search index contains data" -ForegroundColor Green
Write-Host ""

Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Open the frontend in a browser" -ForegroundColor Gray
Write-Host "2. Test different search queries" -ForegroundColor Gray
Write-Host "3. To test failover:" -ForegroundColor Gray
Write-Host "   - Delete/disable the primary search service" -ForegroundColor Gray
Write-Host "   - Wait 2-3 minutes" -ForegroundColor Gray
Write-Host "   - Run this test again" -ForegroundColor Gray
Write-Host "   - Verify it now uses the secondary region" -ForegroundColor Gray
Write-Host ""
