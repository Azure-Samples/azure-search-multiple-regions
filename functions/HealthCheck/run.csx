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
        // Check if search service is accessible
        using (var httpClient = new HttpClient())
        {
            string healthUrl = $"{searchServiceEndpoint}/indexes/{searchIndexName}?api-version=2025-09-01";
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
