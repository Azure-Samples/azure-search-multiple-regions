#r "Newtonsoft.Json"
#r "Microsoft.Azure.DocumentDB.Core"

using System;
using System.Collections.Generic;
using Microsoft.Azure.Documents;
using Newtonsoft.Json;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;

private static readonly HttpClient client = new HttpClient();

public static async Task Run(IReadOnlyList<Document> documents, ILogger log)
{
    if (documents != null && documents.Count > 0)
    {
        log.LogInformation($"Documents modified: {documents.Count}");
        
        var primarySearchService = Environment.GetEnvironmentVariable("PrimarySearchService");
        var secondarySearchService = Environment.GetEnvironmentVariable("SecondarySearchService");
        var searchApiKey = Environment.GetEnvironmentVariable("SearchApiKey");
        var indexName = "products-index";
        
        // Convert documents to search format
        var searchDocuments = new List<object>();
        foreach (var doc in documents)
        {
            var searchDoc = new
            {
                id = doc.GetPropertyValue<string>("id"),
                name = doc.GetPropertyValue<string>("name"),
                description = doc.GetPropertyValue<string>("description"),
                category = doc.GetPropertyValue<string>("category"),
                price = doc.GetPropertyValue<double>("price"),
                __key = doc.GetPropertyValue<string>("id") // Use id as the document key
            };
            searchDocuments.Add(searchDoc);
        }
        
        var payload = new
        {
            value = searchDocuments
        };
        
        var json = JsonConvert.SerializeObject(payload);
        var content = new StringContent(json, Encoding.UTF8, "application/json");
        
        // Update primary search service
        await UpdateSearchIndex(primarySearchService, indexName, searchApiKey, content, log, "Primary");
        
        // Update secondary search service
        await UpdateSearchIndex(secondarySearchService, indexName, searchApiKey, content, log, "Secondary");
    }
}

private static async Task UpdateSearchIndex(string searchService, string indexName, string apiKey, StringContent content, ILogger log, string region)
{
    try
    {
        var url = $"https://{searchService}.search.windows.net/indexes/{indexName}/docs/index?api-version=2023-11-01";
        
        var request = new HttpRequestMessage(HttpMethod.Post, url);
        request.Headers.Add("api-key", apiKey);
        request.Content = content;
        
        var response = await client.SendAsync(request);
        
        if (response.IsSuccessStatusCode)
        {
            log.LogInformation($"{region} search service updated successfully");
        }
        else
        {
            var error = await response.Content.ReadAsStringAsync();
            log.LogError($"{region} search service update failed: {error}");
        }
    }
    catch (Exception ex)
    {
        log.LogError($"{region} search service update error: {ex.Message}");
    }
}
