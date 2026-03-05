# Deploy Azure Functions Script
# This script deploys the function code to both function apps

param(
    [Parameter(Mandatory=$true)]
    [string]$PrimaryFunctionAppName,
    
    [Parameter(Mandatory=$true)]
    [string]$SecondaryFunctionAppName
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deploying Function Code" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Azure Functions Core Tools is installed
Write-Host "Checking Azure Functions Core Tools..." -ForegroundColor Yellow
$funcVersion = func --version 2>$null
if (-not $funcVersion) {
    Write-Host "X Azure Functions Core Tools not found!" -ForegroundColor Red
    Write-Host "Please install it from: https://docs.microsoft.com/azure/azure-functions/functions-run-local" -ForegroundColor Yellow
    exit 1
}
Write-Host "[OK] Azure Functions Core Tools version: $funcVersion" -ForegroundColor Green
Write-Host "[OK] Azure Functions Core Tools version: $funcVersion" -ForegroundColor Green
Write-Host ""

# Navigate to functions directory
$functionsPath = Join-Path $PSScriptRoot "functions"
if (-not (Test-Path $functionsPath)) {
    Write-Host "X Functions directory not found: $functionsPath" -ForegroundColor Red
    exit 1
}

Set-Location $functionsPath

# Deploy to primary function app
Write-Host "Deploying to PRIMARY function app: $PrimaryFunctionAppName..." -ForegroundColor Yellow
func azure functionapp publish $PrimaryFunctionAppName

if ($LASTEXITCODE -ne 0) {
    Write-Host "X Failed to deploy to primary function app" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Primary function app deployed successfully" -ForegroundColor Green
Write-Host "[OK] Primary function app deployed successfully" -ForegroundColor Green
Write-Host ""

# Deploy to secondary function app
Write-Host "Deploying to SECONDARY function app: $SecondaryFunctionAppName..." -ForegroundColor Yellow
func azure functionapp publish $SecondaryFunctionAppName

if ($LASTEXITCODE -ne 0) {
    Write-Host "X Failed to deploy to secondary function app" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Secondary function app deployed successfully" -ForegroundColor Green
Write-Host "[OK] Secondary function app deployed successfully" -ForegroundColor Green
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Function Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Test the functions:" -ForegroundColor Yellow
Write-Host "  Primary:   https://$PrimaryFunctionAppName.azurewebsites.net/api/search?q=*" -ForegroundColor Gray
Write-Host "  Secondary: https://$SecondaryFunctionAppName.azurewebsites.net/api/search?q=*" -ForegroundColor Gray
Write-Host "  Health:    https://$PrimaryFunctionAppName.azurewebsites.net/api/health" -ForegroundColor Gray
