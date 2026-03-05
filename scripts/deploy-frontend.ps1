# Deploy Frontend Script
# This script deploys the frontend to Azure Storage static website

param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$false)]
    [string]$TrafficManagerUrl
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deploying Frontend" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Enable static website
Write-Host "Enabling static website on storage account..." -ForegroundColor Yellow
az storage blob service-properties update `
    --account-name $StorageAccountName `
    --static-website `
    --404-document index.html `
    --index-document index.html `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Host "X Failed to enable static website" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Static website enabled" -ForegroundColor Green
Write-Host "[OK] Static website enabled" -ForegroundColor Green
Write-Host ""

# Upload frontend files
$frontendPath = Join-Path $PSScriptRoot "frontend"
if (-not (Test-Path $frontendPath)) {
    Write-Host "X Frontend directory not found: $frontendPath" -ForegroundColor Red
    exit 1
}

Write-Host "Uploading frontend files..." -ForegroundColor Yellow
az storage blob upload-batch `
    -d '$web' `
    -s $frontendPath `
    --account-name $StorageAccountName `
    --content-type "text/html" `
    --pattern "*.html" `
    --overwrite `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Host "X Failed to upload frontend files" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Frontend files uploaded" -ForegroundColor Green
Write-Host "[OK] Frontend files uploaded" -ForegroundColor Green
Write-Host ""

# Get the static website URL
$properties = az storage account show `
    --name $StorageAccountName `
    --query "primaryEndpoints.web" `
    --output tsv

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Frontend Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Frontend URL: $properties" -ForegroundColor Yellow
Write-Host ""

if ($TrafficManagerUrl) {
    Write-Host "Remember to enter this Traffic Manager URL in the frontend:" -ForegroundColor Yellow
    Write-Host "  $TrafficManagerUrl" -ForegroundColor White
    Write-Host ""
}

Write-Host "Open the URL in your browser to test the application." -ForegroundColor Gray
