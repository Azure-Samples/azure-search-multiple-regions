# Multi-region deployment of Azure Cognitive Search for business continuity

The pattern demonstrated in this code sample can help you meet your business continuity and disaster recovery requirements.

The sample uses [Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/overview?tabs=bicep) to deploy the following resources on Azure:

+ Two Azure Cognitive Search resources in different geographic regions
+ An Azure Cosmos DB resource and sample database, used for testing failover behaviors
+ Search Traffic manager for request redirection

## Prerequisites

+ [Azure subscription](https://azure.microsoft.com/free/)
+ [Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/overview?tabs=bicep)
+ [Azure Cognitive Search](https://learn.microsoft.com/azure/search/search-create-service-portal): two or more, same tier and configuration, in different regions. You can't use the free tier for this scenario.
+ [Azure Cosmos DB](https://learn.microsoft.com/azure/cosmos-db/try-free?tabs=nosql) (any tier, including free)
+ [Azure Traffic Manager](https://learn.microsoft.com/azure/traffic-manager/)

## Sample set up

TBD

## Run the sample

TBD

## Sample clean up

This sample creates multiple Azure resources, several of which are billable. After completing this exercise, delete any resources you no longer need.

1. Sign in to the Azure portal.

1. To delete all of the resources, find and delete the resource group created by the sample code. All of the resources are contained in one group.

## Resources

+ [Azure Cognitive Search documentation](https://learn.microsoft.com/azure/search/)
+ [Samples browser on Microsoft Learn](https://learn.microsoft.com/samples/browse/)
+ [Training](https://learn.microsoft.com/training/)