// Azure Front Door module for multi-region failover
@description('Name of the Front Door profile')
param frontDoorName string

@description('Hostname of the primary function app')
param primaryFunctionHostname string

@description('Hostname of the secondary function app')
param secondaryFunctionHostname string

// Front Door Profile
resource frontDoorProfile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: frontDoorName
  location: 'global'
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
}

// Origin Group with priority-based routing
resource originGroup 'Microsoft.Cdn/profiles/originGroups@2023-05-01' = {
  parent: frontDoorProfile
  name: 'function-origin-group'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/api/health'
      probeRequestType: 'GET'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 30
    }
    sessionAffinityState: 'Disabled'
  }
}

// Primary Origin (Priority 1)
resource primaryOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2023-05-01' = {
  parent: originGroup
  name: 'primary-function'
  properties: {
    hostName: primaryFunctionHostname
    httpPort: 80
    httpsPort: 443
    originHostHeader: primaryFunctionHostname
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
  }
}

// Secondary Origin (Priority 2)
resource secondaryOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2023-05-01' = {
  parent: originGroup
  name: 'secondary-function'
  properties: {
    hostName: secondaryFunctionHostname
    httpPort: 80
    httpsPort: 443
    originHostHeader: secondaryFunctionHostname
    priority: 2
    weight: 1000
    enabledState: 'Enabled'
  }
}

// Front Door Endpoint
resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2023-05-01' = {
  parent: frontDoorProfile
  name: '${frontDoorName}-endpoint'
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

// Route for /api/* traffic
resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2023-05-01' = {
  parent: endpoint
  name: 'api-route'
  properties: {
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/api/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
  }
  dependsOn: [
    primaryOrigin
    secondaryOrigin
  ]
}

// Outputs
output frontDoorEndpointHostname string = endpoint.properties.hostName
output frontDoorEndpointUrl string = 'https://${endpoint.properties.hostName}'
output frontDoorId string = frontDoorProfile.id
