# Redeploy function code to fix the search API issue
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = ".bcdr-config.json"
)

if (-not (Test-Path $ConfigFile)) {
    Write-Host "Error: Configuration file not found: $ConfigFile" -ForegroundColor Red
    exit 1
}

$config = Get-Content $ConfigFile | ConvertFrom-Json

Write-Host ""
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host " REDEPLOYING FUNCTION CODE" -ForegroundColor Yellow
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host ""

# Create temp directory
$tempDir = New-Item -ItemType Directory -Path "$env:TEMP\functions-redeploy-$(Get-Random)" -Force
$zipPath = "$env:TEMP\functions-$(Get-Random).zip"

Write-Host "Creating function package..." -ForegroundColor Gray

# Create SearchApi directory and files
$searchApiDir = New-Item -ItemType Directory -Path "$tempDir\SearchApi" -Force

$searchApiFunctionJson = @{
    bindings = @(
        @{
            authLevel = "anonymous"
            type = "httpTrigger"
            direction = "in"
            name = "req"
            methods = @("get", "post")
            route = "search"
        }
        @{
            type = "http"
            direction = "out"
            name = "res"
        }
    )
} | ConvertTo-Json -Depth 10

Set-Content -Path "$searchApiDir\function.json" -Value $searchApiFunctionJson
Copy-Item -Path "functions\SearchApi\run.csx" -Destination "$searchApiDir\run.csx"

# Create HealthCheck directory and files
$healthCheckDir = New-Item -ItemType Directory -Path "$tempDir\HealthCheck" -Force

$healthCheckFunctionJson = @{
    bindings = @(
        @{
            authLevel = "anonymous"
            type = "httpTrigger"
            direction = "in"
            name = "req"
            methods = @("get")
            route = "health"
        }
        @{
            type = "http"
            direction = "out"
            name = "res"
        }
    )
} | ConvertTo-Json -Depth 10

Set-Content -Path "$healthCheckDir\function.json" -Value $healthCheckFunctionJson
Copy-Item -Path "functions\HealthCheck\run.csx" -Destination "$healthCheckDir\run.csx"

# Create host.json
Copy-Item -Path "functions\host.json" -Destination "$tempDir\host.json"

# Create ZIP file
Write-Host "Creating ZIP package..." -ForegroundColor Gray
Compress-Archive -Path "$tempDir\*" -DestinationPath $zipPath -Force

# Deploy to primary function
Write-Host ""
Write-Host "Deploying to primary function: $($config.primaryFunctionName)" -ForegroundColor Yellow
az functionapp deployment source config-zip `
    --resource-group $config.resourceGroupName `
    --name $config.primaryFunctionName `
    --src $zipPath `
    --build-remote false `
    --only-show-errors

if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Primary function deployed" -ForegroundColor Green
    Write-Host "  [OK] Primary function deployed" -ForegroundColor Green
} else {
    Write-Host "  X Primary function deployment failed" -ForegroundColor Red
}

# Deploy to secondary function
Write-Host ""
Write-Host "Deploying to secondary function: $($config.secondaryFunctionName)" -ForegroundColor Yellow
az functionapp deployment source config-zip `
    --resource-group $config.resourceGroupName `
    --name $config.secondaryFunctionName `
    --src $zipPath `
    --build-remote false `
    --only-show-errors

if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Secondary function deployed" -ForegroundColor Green
    Write-Host "  [OK] Secondary function deployed" -ForegroundColor Green
} else {
    Write-Host "  X Secondary function deployment failed" -ForegroundColor Red
}

# Cleanup
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host " DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Function code has been redeployed. Wait 30-60 seconds for functions to restart." -ForegroundColor Yellow
Write-Host ""
