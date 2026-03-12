#r "Newtonsoft.Json"

using System.Net;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Primitives;
using Newtonsoft.Json;
using System.Text;

public static async Task<IActionResult> Run(HttpRequest req, ILogger log)
{
    log.LogInformation("Search API function triggered");

    // Get configuration from environment variables
    string searchServiceEndpoint = Environment.GetEnvironmentVariable("SearchServiceEndpoint");
    string searchServiceKey = Environment.GetEnvironmentVariable("SearchServiceKey");
    string searchIndexName = Environment.GetEnvironmentVariable("SearchIndexName");
    string regionIdentifier = Environment.GetEnvironmentVariable("RegionIdentifier");

    // Get query parameters
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
        // Build search request
        string searchUrl = $"{searchServiceEndpoint}/indexes/{searchIndexName}/docs/search?api-version=2025-09-01";
        
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
