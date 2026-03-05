# Configure Frontend Script
# Updates the frontend/index.html file with the Traffic Manager URL from deployment

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup
)

Write-Host "Configuring frontend with Traffic Manager URL..." -ForegroundColor Cyan

# Get the Traffic Manager URL from the deployment outputs
Write-Host "Retrieving Traffic Manager URL from deployment outputs..."
$trafficManagerUrl = az deployment group show `
    --resource-group $ResourceGroup `
    --name main `
    --query properties.outputs.trafficManagerUrl.value `
    -o tsv

if ([string]::IsNullOrWhiteSpace($trafficManagerUrl)) {
    Write-Host "Error: Could not retrieve Traffic Manager URL from deployment outputs" -ForegroundColor Red
    Write-Host "Please ensure the deployment has completed successfully" -ForegroundColor Yellow
    exit 1
}

Write-Host "Traffic Manager URL: $trafficManagerUrl" -ForegroundColor Green

# Update the HTML file
$htmlPath = Join-Path $PSScriptRoot "frontend\index.html"

if (-not (Test-Path $htmlPath)) {
    Write-Host "Error: Could not find $htmlPath" -ForegroundColor Red
    exit 1
}

Write-Host "Updating $htmlPath..."

# Read the HTML content
$htmlContent = Get-Content $htmlPath -Raw

# Replace the placeholder with the actual URL
$updatedContent = $htmlContent -replace '{{TRAFFIC_MANAGER_URL}}', $trafficManagerUrl

# Write back to file
Set-Content -Path $htmlPath -Value $updatedContent -NoNewline

Write-Host "Frontend configured successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "To test the application:" -ForegroundColor Cyan
Write-Host "1. Open: $htmlPath" -ForegroundColor White
Write-Host "2. Or run: start $htmlPath" -ForegroundColor White
Write-Host ""
Write-Host "The page will automatically search for '*' (all products) on load" -ForegroundColor Yellow
