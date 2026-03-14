// Traffic Manager module
@description('Name of the Traffic Manager profile')
param trafficManagerName string

@description('Name of the primary endpoint')
param primaryEndpointName string

@description('Name of the secondary endpoint')
param secondaryEndpointName string

@description('Resource ID of the primary function app')
param primaryFunctionAppId string

@description('Resource ID of the secondary function app')
param secondaryFunctionAppId string

// Traffic Manager Profile
resource trafficManagerProfile 'Microsoft.Network/trafficManagerProfiles@2022-04-01' = {
  name: trafficManagerName
  location: 'global'
  properties: {
    profileStatus: 'Enabled'
    trafficRoutingMethod: 'Priority'
    dnsConfig: {
      relativeName: trafficManagerName
      ttl: 30
    }
    monitorConfig: {
      protocol: 'HTTPS'
      port: 443
      path: '/api/health'
      intervalInSeconds: 30
      toleratedNumberOfFailures: 3
      timeoutInSeconds: 10
    }
    endpoints: [
      {
        name: primaryEndpointName
        type: 'Microsoft.Network/trafficManagerProfiles/azureEndpoints'
        properties: {
          targetResourceId: primaryFunctionAppId
          endpointStatus: 'Enabled'
          priority: 1
          weight: 1
        }
      }
      {
        name: secondaryEndpointName
        type: 'Microsoft.Network/trafficManagerProfiles/azureEndpoints'
        properties: {
          targetResourceId: secondaryFunctionAppId
          endpointStatus: 'Enabled'
          priority: 2
          weight: 1
        }
      }
    ]
  }
}

// Outputs
output trafficManagerId string = trafficManagerProfile.id
output trafficManagerDns string = trafficManagerProfile.properties.dnsConfig.fqdn
