# Multi-region deployment of Azure AI Search with Azure Front Door for business continuity and disaster recovery

This sample demonstrates automatic failover for Azure AI Search using Azure Front Door with priority-based routing.

The deployment creates Azure AI Search services in two regions with Azure Functions APIs and automatic failover capabilities.

Learn more: [Multi-region deployments in Azure AI Search](https://learn.microsoft.com/azure/search/search-multi-region?tabs=push-apis%2Capplication-gateway)

## Prerequisites

- [Azure subscription](https://azure.microsoft.com/free/)
- Permission to create resources in Azure
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [PowerShell](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) 7.0 or later
- [Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/overview?tabs=bicep).

## Overview

The Bicep templates create two billable [Azure AI Search](https://learn.microsoft.com/azure/search/search-create-service-portal) services (Basic tier) in different regions. *You can't use the free tier for this sample.*

The primary search service (westus2) handles indexing and query workloads under normal conditions. The secondary search service (westus3) serves as a failover copy. Azure Front Door monitors both regions with health probes and automatically routes traffic to the secondary region if the primary becomes unavailable.

### Data synchronization options

This sample provides two methods to keep search indexes synchronized across regions:

#### Option 1: Scheduled indexers (default)

Uses Azure AI Search [indexers](https://learn.microsoft.com/azure/search/search-indexer-overview) to pull data from Azure Cosmos DB for NoSQL on a schedule. Both search services configure identical indexers that run every five minutes, pointing to the same Cosmos DB database. This is the simpler approach and works well when five-minute synchronization latency is acceptable.

**Pros:**

- Simple configuration
- No additional code required
- Built-in Azure AI Search feature

**Cons:**

- 5-minute minimum sync interval
- Slight delay in data availability

#### Option 2: Change feed (real-time)

Uses [Cosmos DB change feed](https://learn.microsoft.com/azure/cosmos-db/change-feed) with Azure Functions to push updates to search indexes in real-time. When documents change in Cosmos DB, Azure Functions are triggered immediately and push the updates to both search services. This provides near-instantaneous synchronization.

**Pros:**

- Real-time synchronization
- Near-zero latency
- Immediate data availability

**Cons:**

- More complex configuration
- Requires Azure Functions
- Additional code to maintain

## Run this sample

To run this sample, you must first complete some basic setup steps to prepare your Azure environment and deploy the resources.

1. Install the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) or another supported tool for Bicep deployment.

2. Clone or download this sample repository.

3. Extract contents if the download is a zip file. Make sure the files are read-write.

4. Sign in to your Azure account:

   ```powershell
   az login
   ```

5. Create a resource group to contain all of the resources:

   ```powershell
   az group create --name demoResourceGroup --location westus2
   ```

### Deploy with scheduled indexers (Option 1)

From the command line, run the deployment script with the default indexer synchronization:

```powershell
.\deploy.ps1 -ResourceGroupName "demoResourceGroup"
```

Or explicitly specify the indexer method:

```powershell
.\deploy.ps1 -ResourceGroupName "demoResourceGroup" -SyncMethod "indexer"
```

### Deploy with change feed (Option 2)

From the command line, run the deployment script with change feed synchronization:

```powershell
.\deploy.ps1 -ResourceGroupName "demoResourceGroup" -SyncMethod "changefeed"
```

### What gets deployed

The deployment script will:

1. Create Azure AI Search services in two regions (westus2 and westus3)
2. Deploy Azure Functions with automatic code deployment
3. Configure Azure Front Door with priority-based routing
4. Deploy Cosmos DB NoSQL (serverless) for data storage
5. Populate Cosmos DB with 50 sample product documents
6. Configure synchronization (indexers or change feed based on selection)
7. Configure the frontend with the Front Door URL
8. Save configuration for testing scripts

The deployment takes approximately 15-20 minutes to complete.

> Front Door may require an additional 15-30 minutes after provisioning to fully propagate to the global edge network.

### Test the deployment

Open `frontend/index.html` in your web browser to test search functionality. The frontend is pre-configured with the Front Door endpoint and will display which region served each request.

### Test automatic failover

Simulate a primary region failure by making the search service unavailable:

```powershell
.\test-failover.ps1
```

This script will:

1. Disable public network access on the primary search service (simulates regional outage)
2. Wait for Front Door health probes to detect the failure (~90 seconds)
3. Test routing distribution (15 requests)
4. Display a formatted status summary

**What happens:**

- The primary search service becomes network-isolated (private-only access)
- Function apps can no longer reach the primary search service
- Health checks fail because searches cannot be executed
- Front Door detects the unhealthy endpoint and routes 100% traffic to secondary region (westus3)

This simulates a real Azure AI Search regional failure, not just a function app failure.

### Test automatic failback

Restore the primary region by re-enabling the search service:

```powershell
.\test-failback.ps1
```

This script will:

1. Re-enable public network access on the primary search service
2. Purge the Front Door cache
3. Wait for health probes to detect recovery (~90 seconds)
4. Test routing distribution (20 requests)
5. Display a formatted status summary

You should see traffic automatically return to the primary region (westus2).

## Sample cleanup

This sample creates multiple Azure resources, several of which are billable. After completing this exercise, delete any resources you no longer need.

```powershell
.\cleanup.ps1
```

Alternatively, delete the resource group manually:

```powershell
az group delete --name demoResourceGroup --yes --no-wait
```

## Architecture

Azure Front Door provides global load balancing and automatic failover for the multi-region search deployment. Data is stored in Cosmos DB NoSQL and synchronized to both Azure AI Search services.

```
+---------------------+
|  Azure Front Door   |  Global endpoint with SSL termination
|  (Priority Routing) |  Health probes every 30s
+----------+----------+
           |
    +------+------+
    |             |
+---v--------+ +--v---------+
|  Primary   | | Secondary  |
|  westus2   | |  westus3   |
| Priority 1 | | Priority 2 |
+------------+ +------------+
| AI Search  | | AI Search  |
| Functions  | | Functions  |
| Storage    | | Storage    |
+-----+------+ +------+-----+
      |               |
      +-------+-------+
              |
      +-------v--------+
      |   Cosmos DB    |  Single data source
      |  NoSQL (50 docs)|  Serverless
      |   Primary Region|
      +----------------+
```

**Synchronization methods:**

- **Option 1 (Indexer):** Scheduled indexers pull from Cosmos DB every 5 minutes
- **Option 2 (Change Feed):** Azure Functions push changes in real-time via change feed

**Failover behavior:**

- Front Door routes to primary when healthy (Priority 1)
- After 3 failed health checks (~90 seconds), traffic switches to secondary
- Automatic failback when primary recovers
- SSL termination at the edge eliminates certificate issues
- Global edge network provides low latency

## Configuration

The deployment uses the following default parameters. To customize, edit [bicep/main.parameters.json](bicep/main.parameters.json).

| Parameter | Default Value | Description |
|-----------|--------------|-------------|
| `projectName` | bcdrtest | Base name for resources - **Must be 3-10 characters** (lowercase letters/numbers only). |
| `primaryRegion` | westus2 | Primary Azure region. Any valid Azure region name is supported. |
| `secondaryRegion` | westus3 | Secondary Azure region. Any valid Azure region name is supported. |
| `searchSku` | basic | Azure AI Search service tier |
| `syncMethod` | indexer | Synchronization method: `indexer` or `changefeed` |

> **[!] Important:** The `projectName` must be 10 characters or less to ensure generated resource names stay within Azure naming limits. Storage account names automatically use region abbreviations to accommodate longer region names.

### Front Door configuration

- **Routing method:** Priority-based (primary preferred)
- **Health probe interval:** 30 seconds
- **Health probe path:** `/api/health`
- **Failure threshold:** 3 consecutive failures (~90 seconds)
- **Protocol:** HTTPS-only with automatic HTTP->HTTPS redirect

### Cosmos DB configuration

- **API:** NoSQL
- **Consistency level:** Session
- **Billing mode:** Serverless
- **Database:** `productsdb`
- **Container:** `products` (50 sample documents)
- **Partition key:** `/id`

## API Reference

### Search API

Query the search index through the Front Door endpoint.

**Endpoint:** `https://<front-door-endpoint>/api/search`

**Method:** `GET`

**Query parameters:**

- `q` (required) - Search query string. Use `*` for all documents
- `top` (optional) - Number of results to return. Default: 10

**Response:**
```json
{
  "results": [
    {
      "id": "1",
      "name": "Product Name",
      "description": "Description",
      "category": "Category",
      "price": 99.99
    }
  ],
  "count": 8,
  "region": "westus2",
  "timestamp": "2026-01-30T12:00:00Z"
}
```

### Health Check API

Monitor the health status of each search service.

**Endpoint:** `https://<front-door-endpoint>/api/health`

**Method:** `GET`

**Response:**

```json
{
  "status": "healthy",
  "region": "westus2",
  "timestamp": "2026-01-30T12:00:00Z",
  "searchService": "available"
}
```

## Cost estimate

| Resource | SKU | Quantity | Est. Monthly Cost |
|----------|-----|----------|-------------------|
| Azure AI Search | Basic | 2 | $150 |
| Azure Functions | Basic (B1) | 2 | $26 |
| Azure Front Door | Standard | 1 | $35+ |
| Storage Accounts | Standard LRS | 3 | $3 |
| Cosmos DB NoSQL | Serverless | 1 | ~$5* |
| **Total** | | | **~$219+** |

Front Door costs vary based on data transfer and request volume. Cosmos DB serverless billing is based on Request Units (RUs) consumed and storage used. Delete resources when testing is complete to avoid ongoing charges.

> *Cosmos DB estimate based on minimal read/write operations for testing. Production workloads will vary.

## Resources

- [Azure AI Search documentation](https://learn.microsoft.com/azure/search/)
- [Azure Front Door documentation](https://learn.microsoft.com/azure/frontdoor/)
- [Azure Functions documentation](https://learn.microsoft.com/azure/azure-functions/)
- [BCDR for Azure AI Search](https://learn.microsoft.com/azure/search/search-performance-optimization#geo-redundancy)
- [Samples browser on Microsoft Learn](https://learn.microsoft.com/samples/browse/)

## Troubleshooting

### Front Door returns "Page not found"

**Cause:** Front Door edge network deployment not yet complete (common on first deployment).

**Solution:**

1. Wait 15-30 minutes after initial deployment
2. Access the endpoint multiple times to trigger deployment
3. Check deployment status:

   ```powershell
   az afd endpoint show \
     --endpoint-name <endpoint-name> \
     --profile-name <profile-name> \
     --resource-group <rg-name> \
     --query deploymentStatus
   ```

### Deployment fails with "service name already taken"

**Solution:** Edit `bicep/main.parameters.json` and change `projectName` to a unique value.

### Search returns no results

**Solution:** Wait 2-3 minutes after deployment for indexing to complete.

If indexes were not created during deployment, manually configure them:

```powershell
.\scripts\configure-search.ps1
```

### Search indexes not created during deployment

**Cause:** Deployment script may have failed to create indexes or indexers.

**Solution:** Run the manual configuration script:

```powershell
.\scripts\configure-search.ps1
```

This will create data sources, indexes, and indexers on both search services.

### Function code needs to be redeployed

Use `.\scripts\redeploy-functions.ps1` instead of the full `.\deploy.ps1` when:

- You edited function code in the `functions/` directory (for example, `SearchApi/run.csx`, `HealthCheck/run.csx`, or `CosmosDbTrigger/run.csx`) and want to push those changes without re-running the full infrastructure deployment
- The full `.\deploy.ps1` completed successfully but the function code deployment step failed or timed out
- You want faster iteration cycles when only code has changed (not infrastructure)

```powershell
.\scripts\redeploy-functions.ps1
```

This packages and deploys the latest function code to both the primary (westus2) and secondary (westus3) function apps. It does not modify any infrastructure resources.

### Front Door not routing correctly

**Diagnostic steps:**

1. Check origin health:

   ```powershell
   az afd origin list \
     --origin-group-name function-origin-group \
     --profile-name <profile-name> \
     --resource-group <rg-name>
   ```

2. Verify function apps are running in Azure Portal

3. Test health endpoint directly: `https://<function-app>.azurewebsites.net/api/health`

### Function code deployment issues

**Solution:**

1. Check function app logs in Azure Portal
2. Verify function app is running
3. Redeploy only the function code (faster than a full redeploy):

   ```powershell
   .\scripts\redeploy-functions.ps1
   ```

4. If infrastructure changes are also needed, re-run the full deployment:

   ```powershell
   .\deploy.ps1 -ResourceGroupName "<your-resource-group>"
   ```
