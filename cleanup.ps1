# Cleanup Script
# This script deletes all resources created by the deployment

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = ".bcdr-config.json",
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "`n====================================================================" -ForegroundColor Red
Write-Host "`n====================================================================" -ForegroundColor Red
Write-Host " AZURE SEARCH BCDR CLEANUP" -ForegroundColor Yellow
Write-Host "====================================================================" -ForegroundColor Red
Write-Host "====================================================================" -ForegroundColor Red
Write-Host ""

# Try to load configuration
$resourceGroupName = $null
if (Test-Path $ConfigFile) {
    $config = Get-Content $ConfigFile | ConvertFrom-Json
    $resourceGroupName = $config.resourceGroupName
    Write-Host "Configuration loaded from: $ConfigFile" -ForegroundColor Gray
    Write-Host "Resource Group: $resourceGroupName" -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Host "No configuration file found. You'll need to specify the resource group." -ForegroundColor Yellow
    $resourceGroupName = Read-Host "Enter the Resource Group name to delete"
    Write-Host ""
}

if (-not $Force) {
    Write-Host "+---------------------------------------------------------------------+" -ForegroundColor Yellow
    Write-Host "|  WARNING: This will delete ALL resources in the resource group     |" -ForegroundColor Yellow
    Write-Host "+---------------------------------------------------------------------+" -ForegroundColor Yellow
    Write-Host "|                                                                     |" -ForegroundColor Yellow
    Write-Host "|  Resource Group: $($resourceGroupName.PadRight(49))|" -ForegroundColor Yellow
    Write-Host "|                                                                     |" -ForegroundColor Yellow
    Write-Host "|  This includes:                                                     |" -ForegroundColor Yellow
    Write-Host "|  * Azure AI Search services (2 regions)                            |" -ForegroundColor Yellow
    Write-Host "|  * Azure Function Apps (2 regions)                                 |" -ForegroundColor Yellow
    Write-Host "|  * Azure Front Door profile                                        |" -ForegroundColor Yellow
    Write-Host "|  * Storage Accounts (3 total)                                      |" -ForegroundColor Yellow
    Write-Host "|  * All search indexes and data                                     |" -ForegroundColor Yellow
    Write-Host "|  * All function code                                               |" -ForegroundColor Yellow
    Write-Host "|  * All configuration                                               |" -ForegroundColor Yellow
    Write-Host "|                                                                     |" -ForegroundColor Yellow
    Write-Host "+---------------------------------------------------------------------+" -ForegroundColor Yellow
    Write-Host ""
    
    $confirmation = Read-Host "Type 'yes' to confirm deletion"
    if ($confirmation -ne "yes") {
        Write-Host "`n[OK] Cleanup cancelled." -ForegroundColor Gray
        Write-Host "`n[OK] Cleanup cancelled." -ForegroundColor Gray
        Write-Host ""
        exit 0
    }
}

Write-Host ""
Write-Host "Deleting resource group: $resourceGroupName..." -ForegroundColor Yellow
Write-Host "This may take several minutes..." -ForegroundColor Gray
Write-Host ""

az group delete --name $resourceGroupName --yes --no-wait

if ($LASTEXITCODE -ne 0) {
    Write-Host "X Failed to delete resource group" -ForegroundColor Red
    exit 1
}

Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  CLEANUP INITIATED                                                  |" -ForegroundColor White -BackgroundColor DarkGreen
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  [OK] Resource group deletion initiated                               |" -ForegroundColor White
Write-Host "|  [OK] Running in background                                           |" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  The deletion is running asynchronously in Azure.                  |" -ForegroundColor Gray
Write-Host "|  All resources will be removed within 5-10 minutes.                |" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  To check deletion status:                                          |" -ForegroundColor Yellow
Write-Host "|  az group show --name $($resourceGroupName.PadRight(44))|" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|  CLEANUP INITIATED                                                  |" -ForegroundColor White -BackgroundColor DarkGreen
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  [OK] Resource group deletion initiated                               |" -ForegroundColor White
Write-Host "|  [OK] Running in background                                           |" -ForegroundColor White
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  The deletion is running asynchronously in Azure.                  |" -ForegroundColor Gray
Write-Host "|  All resources will be removed within 5-10 minutes.                |" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "|  To check deletion status:                                          |" -ForegroundColor Yellow
Write-Host "|  az group show --name $($resourceGroupName.PadRight(44))|" -ForegroundColor Gray
Write-Host "|                                                                     |" -ForegroundColor White
Write-Host "+---------------------------------------------------------------------+" -ForegroundColor White
Write-Host ""

# Clean up local configuration file
if (Test-Path $ConfigFile) {
    Remove-Item $ConfigFile -Force
    Write-Host "[OK] Removed local configuration file: $ConfigFile" -ForegroundColor Green
    Write-Host "[OK] Removed local configuration file: $ConfigFile" -ForegroundColor Green
}

Write-Host ""
Write-Host "You can check the status in the Azure Portal." -ForegroundColor Gray
Write-Host ""
Write-Host "To verify deletion is complete, run:" -ForegroundColor Yellow
Write-Host "  az group show --name $ResourceGroupName" -ForegroundColor Gray
Write-Host ""
