// Function code deployment module using Deployment Scripts
@description('Name of the function app to deploy code to')
param functionAppName string

@description('Location for the deployment script')
param location string

@description('Resource group name where function app exists')
param resourceGroupName string

@description('Unique identity for the script')
param scriptIdentity string

// Deployment script to deploy function code
resource functionCodeDeploy 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'deploy-function-code-${scriptIdentity}'
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
        name: 'FUNCTION_APP_NAME'
        value: functionAppName
      }
      {
        name: 'RESOURCE_GROUP'
        value: resourceGroupName
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = 'Stop'
      
      $functionAppName = $env:FUNCTION_APP_NAME
      $resourceGroup = $env:RESOURCE_GROUP
      
      Write-Host "Waiting for function app to be fully ready..."
      Start-Sleep -Seconds 30
      
      Write-Host "Creating function code ZIP package..."
      
      # Set temp directory (works on both Windows and Linux)
      $tempBase = if ($env:TEMP) { $env:TEMP } else { "/tmp" }
      
      # Create temporary directory for function files
      $tempDir = New-Item -ItemType Directory -Path "$tempBase/functions-$(Get-Random)" -Force
      $zipPath = "$tempBase/functions-$(Get-Random).zip"
      
      # Create function structure
      $searchApiDir = New-Item -ItemType Directory -Path "$tempDir/SearchApi" -Force
      $healthCheckDir = New-Item -ItemType Directory -Path "$tempDir/HealthCheck" -Force
      
      # Create SearchApi function.json
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
      
      # Create SearchApi run.csx
      $searchApiCode = @'
#r "Newtonsoft.Json"

using System.Net;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Primitives;
using Newtonsoft.Json;
using System.Text;

public static async Task<IActionResult> Run(HttpRequest req, ILogger log)
{
    log.LogInformation("Search API function triggered");

    string searchServiceEndpoint = Environment.GetEnvironmentVariable("SearchServiceEndpoint");
    string searchServiceKey = Environment.GetEnvironmentVariable("SearchServiceKey");
    string searchIndexName = Environment.GetEnvironmentVariable("SearchIndexName");
    string regionIdentifier = Environment.GetEnvironmentVariable("RegionIdentifier");

    string query = req.Query["q"];
    string topParam = req.Query["top"];
    string skipParam = req.Query["skip"];
    int top = 50;  // Default to 50 to get all results for client-side pagination
    int skip = 0;
    
    if (!string.IsNullOrEmpty(topParam) && int.TryParse(topParam, out int parsedTop))
    {
        top = parsedTop;
    }
    
    if (!string.IsNullOrEmpty(skipParam) && int.TryParse(skipParam, out int parsedSkip))
    {
        skip = parsedSkip;
    }

    if (string.IsNullOrEmpty(query))
    {
        return new BadRequestObjectResult(new { 
            error = "Query parameter 'q' is required",
            example = "/api/search?q=laptop&top=10&skip=0"
        });
    }

    try
    {
        string searchUrl = $"{searchServiceEndpoint}/indexes/{searchIndexName}/docs/search?api-version=2023-11-01";
        
        var searchRequest = new
        {
            search = query,
            top = top,
            skip = skip,
            count = true
        };

        using (var httpClient = new HttpClient())
        {
            httpClient.DefaultRequestHeaders.Add("api-key", searchServiceKey);
            
            var content = new StringContent(
                JsonConvert.SerializeObject(searchRequest),
                Encoding.UTF8,
                "application/json"
            );

            var response = await httpClient.PostAsync(searchUrl, content);
            var responseContent = await response.Content.ReadAsStringAsync();

            if (response.IsSuccessStatusCode)
            {
                dynamic searchResults = JsonConvert.DeserializeObject(responseContent);
                
                // Add region to each result
                var results = new List<dynamic>();
                foreach (var item in searchResults.value)
                {
                    var resultItem = JsonConvert.DeserializeObject<Dictionary<string, object>>(item.ToString());
                    resultItem["region"] = regionIdentifier;
                    results.Add(resultItem);
                }
                
                var result = new
                {
                    query = query,
                    count = (int)searchResults["@odata.count"],
                    results = results,
                    region = regionIdentifier,
                    timestamp = DateTime.UtcNow
                };

                log.LogInformation($"Search completed successfully. Query: {query}, Results: {result.count}, Region: {regionIdentifier}");
                
                return new OkObjectResult(result);
            }
            else
            {
                log.LogError($"Search service returned error: {response.StatusCode}");
                return new ObjectResult(new { 
                    error = "Search service error",
                    statusCode = (int)response.StatusCode,
                    details = responseContent
                })
                {
                    StatusCode = (int)response.StatusCode
                };
            }
        }
    }
    catch (Exception ex)
    {
        log.LogError($"Error executing search: {ex.Message}");
        return new ObjectResult(new { 
            error = "Internal server error",
            message = ex.Message
        })
        {
            StatusCode = 500
        };
    }
}
'@
      
      Set-Content -Path "$searchApiDir\run.csx" -Value $searchApiCode
      
      # Create SearchApi function.proj
      $searchApiProj = @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net6.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Azure.Search.Documents" Version="11.5.1" />
  </ItemGroup>
</Project>
'@
      
      Set-Content -Path "$searchApiDir\function.proj" -Value $searchApiProj
      
      # Create HealthCheck function.json
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
      
      # Create HealthCheck run.csx
      $healthCheckCode = @'
#r "Newtonsoft.Json"

using System.Net;
using Microsoft.AspNetCore.Mvc;
using Newtonsoft.Json;

public static async Task<IActionResult> Run(HttpRequest req, ILogger log)
{
    log.LogInformation("Health check endpoint called");

    string regionIdentifier = Environment.GetEnvironmentVariable("RegionIdentifier");
    string searchServiceEndpoint = Environment.GetEnvironmentVariable("SearchServiceEndpoint");
    string searchServiceKey = Environment.GetEnvironmentVariable("SearchServiceKey");
    string searchIndexName = Environment.GetEnvironmentVariable("SearchIndexName");

    try
    {
        using (var httpClient = new HttpClient())
        {
            string healthUrl = $"{searchServiceEndpoint}/indexes/{searchIndexName}?api-version=2023-11-01";
            httpClient.DefaultRequestHeaders.Add("api-key", searchServiceKey);
            
            var response = await httpClient.GetAsync(healthUrl);
            
            if (response.IsSuccessStatusCode)
            {
                return new OkObjectResult(new
                {
                    status = "healthy",
                    region = regionIdentifier,
                    timestamp = DateTime.UtcNow,
                    searchService = "available"
                });
            }
            else
            {
                log.LogWarning($"Search service health check failed: {response.StatusCode}");
                return new ObjectResult(new
                {
                    status = "unhealthy",
                    region = regionIdentifier,
                    timestamp = DateTime.UtcNow,
                    searchService = "unavailable"
                })
                {
                    StatusCode = 503
                };
            }
        }
    }
    catch (Exception ex)
    {
        log.LogError($"Health check error: {ex.Message}");
        return new ObjectResult(new
        {
            status = "unhealthy",
            region = regionIdentifier,
            timestamp = DateTime.UtcNow,
            error = ex.Message
        })
        {
            StatusCode = 503
        };
    }
}
'@
      
      Set-Content -Path "$healthCheckDir\run.csx" -Value $healthCheckCode
      
      # Create host.json
      $hostJson = @{
        version = "2.0"
        logging = @{
          applicationInsights = @{
            samplingSettings = @{
              isEnabled = $true
              maxTelemetryItemsPerSecond = 20
            }
          }
        }
        extensionBundle = @{
          id = "Microsoft.Azure.Functions.ExtensionBundle"
          version = "[3.*, 4.0.0)"
        }
      } | ConvertTo-Json -Depth 10
      
      Set-Content -Path "$tempDir\host.json" -Value $hostJson
      
      Write-Host "Creating ZIP archive..."
      Compress-Archive -Path "$tempDir\*" -DestinationPath $zipPath -Force
      
      Write-Host "Deploying function code to $functionAppName..."
      
      # Retry logic for deployment using PowerShell cmdlets
      $maxRetries = 3
      $retryCount = 0
      $deployed = $false
      
      while (-not $deployed -and $retryCount -lt $maxRetries) {
        try {
          $retryCount++
          Write-Host "Deployment attempt $retryCount of $maxRetries..."
          
          # Wait longer on first attempt for SCM site to be ready
          if ($retryCount -eq 1) {
            Write-Host "Waiting for SCM site to be fully provisioned..."
            Start-Sleep -Seconds 60
          }
          
          # Use Publish-AzWebApp cmdlet which handles authentication automatically
          Write-Host "Deploying ZIP package using Publish-AzWebApp..."
          Publish-AzWebApp `
            -ResourceGroupName $resourceGroup `
            -Name $functionAppName `
            -ArchivePath $zipPath `
            -Force
          
          Write-Host "Waiting for deployment to propagate..."
          Start-Sleep -Seconds 30
          
          # Verify deployment using PowerShell cmdlet
          $webApp = Get-AzWebApp -ResourceGroupName $resourceGroup -Name $functionAppName
          if ($webApp.State -eq "Running") {
            Write-Host "Function app is running, deployment successful!"
            $deployed = $true
          } else {
            Write-Host "Function app state: $($webApp.State), retrying..."
            Start-Sleep -Seconds 15
          }
        }
        catch {
          Write-Host "Deployment attempt $retryCount failed: $($_.Exception.Message)"
          if ($retryCount -lt $maxRetries) {
            Write-Host "Retrying in 15 seconds..."
            Start-Sleep -Seconds 15
          }
        }
      }
      
      if (-not $deployed) {
        throw "Failed to deploy function code after $maxRetries attempts"
      }
      
      # Cleanup
      Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
      Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
      
      Write-Host "Function code deployment complete for $functionAppName"
    '''
  }
}

// Create managed identity for deployment script
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'deploy-identity-${scriptIdentity}'
  location: location
}

// Role assignment for managed identity to deploy to function app
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedIdentity.id, functionAppName, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor role
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output deploymentStatus string = functionCodeDeploy.properties.provisioningState
