# Multi-region deployment of Azure Cognitive Search for business continuity

The pattern demonstrated in this code sample can help you meet your business continuity and disaster recovery requirements for Azure Cognitive Search workloads.

The sample uses [Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/overview?tabs=bicep) to deploy the following resources on Azure:

+ Two [Azure Cognitive Search](https://learn.microsoft.com/azure/search/search-create-service-portal) resources, same tier and configuration, in different regions. You can't use the free tier for this scenario.
+ [Azure Cosmos DB](https://learn.microsoft.com/azure/cosmos-db/try-free?tabs=nosql) (any tier, including free, in any region). The script creates and loads a sample database used for testing failover behaviors during indexing.
+ [Azure Traffic Manager](https://learn.microsoft.com/azure/traffic-manager/) for request redirection.

## Prerequisites

+ [Azure subscription](https://azure.microsoft.com/free/)
+ Permission to create and access resources in Azure

## Sample set up

1. Install the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
1. Clone or download this sample repository.
1. Extract contents if the download is a zip file. Make sure the files are read-write.

## Run the sample

### Cosmos DB Indexer Sync

Import data from Cosmos DB NoSQL automatically to multiple search services using [indexers](https://learn.microsoft.com/azure/search/search-howto-index-cosmosdb). This allows multiple instances of applications backed by separate search services to stay in sync. This sample uses a [pull-based sync architecture](https://learn.microsoft.com/azure/search/search-what-is-data-import#pulling-data-into-an-index).

![Cosmos DB Indexer Sync Architecture](./media/IndexerSyncArchitecture.png)

1. Create a new resource group in your Azure subscription.
1. Navigate to the `bicep` directory in the sample
1. Run the following CLI command:
`az deployment group create --resource-group <your-resource-group> --template-file cosmosdb-indexer-sync.bicep --mode Incremental --parameters @cosmosdb-indexer-sync.parameters.json
`
1. Two instances of a search application are deployed, automatically syncing to a [Cosmos DB Account](https://learn.microsoft.com/azure/cosmos-db/resource-model) using indexers.
1. Edit the bicep file or parameters file to change attributes of this application, such as the primary or secondary regions it is deployed in.

### Comsos DB Change Feed Sync

Import data from Cosmos DB NoSQL automatically to multiple search services using [change feed and Azure Functions](https://learn.microsoft.com/azure/cosmos-db/nosql/change-feed-functions). This allows multiple instances of applications backed by separate search services to receive Cosmos DB changes quickly and stay in sync. This sample uses a [push-based sync architecture](https://learn.microsoft.com/azure/search/search-what-is-data-import#pushing-data-to-an-index).

![Cosmos DB Change Feed Sync Architecture](./media/ChangeFeedSyncArchitecture.png)

1. Create a new resource group in your Azure subscription.
1. Navigate to the `bicep` directory in the sample
1. Run the following CLI command:
`az deployment group create --resource-group <your-resource-group> --template-file cosmosdb-changefeed-sync.bicep --mode Incremental --parameters @cosmosdb-changefeed-sync.parameters.json
`
1. Two instances of a search application are deployed, automatically syncing to a [Cosmos DB Account](https://learn.microsoft.com/azure/cosmos-db/resource-model) using [change feed](https://learn.microsoft.com/azure/cosmos-db/nosql/change-feed-functions).
1. Edit the bicep file or parameters file to change attributes of this application, such as the primary or secondary regions it is deployed in.

### Traffic Manager

Use [Azure Traffic Manager](https://learn.microsoft.com/azure/traffic-manager/) to automatically fail over between search services if one encounters an issue.

![Traffic Manager Architecture](./media/TrafficManagerArchitecture.png)

1. Create a new resource group in your Azure subscription
1. Navigate to the `bicep` directory in the sample
1. Run the following CLI command:
`az deployment group create --resource-group <your-resource-group> --template-file search-trafficmanager.bicep --mode Incremental --parameters @search-trafficmanager.parameters.json
`
1. Two instances of a search application are deployed behind a Traffic Manager Profile.
1. Edit the bicep file or parameters file to change attributes of this application, such as the primary or secondary regions it is deployed in.

## Sample clean up

This sample creates multiple Azure resources, several of which are billable. After completing this exercise, delete any resources you no longer need.

1. Sign in to the Azure portal.

1. To delete all of the resources, find and delete the resource group created by the sample code. All of the resources are contained in one group.

## Resources

+ [Azure Cognitive Search documentation](https://learn.microsoft.com/azure/search/)
+ [Samples browser on Microsoft Learn](https://learn.microsoft.com/samples/browse/)
+ [Training](https://learn.microsoft.com/training/)