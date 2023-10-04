targetScope = 'subscription'

param rgName string
param clusterName string
param akslaWorkspaceName string
param vnetName string
param subnetName string
param appGatewayName string
param rtAppGWSubnetName string
param aksuseraccessprincipalId string
param aksadminaccessprincipalId string
param aksIdentityName string
param kubernetesVersion string
param rtAKSName string
param location string = deployment().location
param availabilityZones array
param enableAutoScaling bool
param autoScalingProfile object

@allowed([
  'azure'
  'kubenet'
])
param networkPlugin string = 'azure'

var akskubenetpodcidr = '172.17.0.0/24'
var ipdelimiters = [
  '.'
  '/'
]
param acrName string //User to provide each time
param keyvaultName string //user to provide each time

var privateDNSZoneAKSSuffixes = {
  AzureCloud: '.azmk8s.io'
  AzureUSGovernment: '.cx.aks.containerservice.azure.us'
  AzureChinaCloud: '.cx.prod.service.azk8s.cn'
  AzureGermanCloud: '' //TODO: what is the correct value here?
}

var privateDNSZoneAKSName = 'privatelink.${toLower(location)}${privateDNSZoneAKSSuffixes[environment().name]}'

module rg 'modules/resource-group/rg.bicep' = {
  name: rgName
  params: {
    rgName: rgName
    location: location
  }
}

resource aksIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  scope: resourceGroup(rg.name)
  name: aksIdentityName
}

module aksPodIdentityRole 'modules/Identity/role.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'aksPodIdentityRole'
  params: {
    principalId: aksIdentity.properties.principalId
    roleGuid: 'f1a07417-d97a-45cb-824c-7a7467783830' //Managed Identity Operator
  }
}

resource pvtdnsAKSZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: privateDNSZoneAKSName
  scope: resourceGroup(rg.name)
}

module aksPolicy 'modules/policy/policy.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'aksPolicy'
  params: {}
}

module akslaworkspace 'modules/laworkspace/la.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'akslaworkspace'
  params: {
    location: location
    workspaceName: akslaWorkspaceName
  }
}

resource aksSubnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing = {
  scope: resourceGroup(rg.name)
  name: '${vnetName}/${subnetName}'
}

resource appGateway 'Microsoft.Network/applicationGateways@2021-02-01' existing = {
  scope: resourceGroup(rg.name)
  name: appGatewayName
}

resource aksCluster 'Microsoft.ContainerService/managedClusters@2022-03-02-preview' = {
  name: clusterName
  scope: resourceGroup(rg.name)
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aksIdentity.id}': {}
    }
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    nodeResourceGroup: '${clusterName}-aksInfraRG'
    podIdentityProfile: networkPlugin == 'azure' ?{
      enabled: true
    }:{
      enabled: true
      allowNetworkPluginKubenet: true
    }
    dnsPrefix: '${clusterName}aks'
    agentPoolProfiles: [
      {
        enableAutoScaling: enableAutoScaling
        name: 'defaultpool'
        availabilityZones: !empty(availabilityZones) ? availabilityZones : null
        mode: 'System'
        enableEncryptionAtHost: true
        count: 3
        minCount: enableAutoScaling ? 1 : null
        maxCount: enableAutoScaling ? 3 : null
        vmSize: 'Standard_D4d_v5'
        osDiskSizeGB: 30
        type: 'VirtualMachineScaleSets'
        vnetSubnetID: aksSubnet.id
      }
    ]
    autoScalerProfile: enableAutoScaling ? autoScalingProfile : null
    networkProfile: networkPlugin == 'azure' ? {
      networkPlugin: 'azure'
      outboundType: 'userDefinedRouting'
      dockerBridgeCidr: '172.16.1.1/30'
      dnsServiceIP: '192.168.100.10'
      serviceCidr: '192.168.100.0/24'
      networkPolicy: 'calico'
    }:{
      networkPlugin: 'kubenet'
      outboundType: 'userDefinedRouting'
      dockerBridgeCidr: '172.16.1.1/30'
      dnsServiceIP: '192.168.100.10'
      serviceCidr: '192.168.100.0/24'
      networkPolicy: 'calico'
      podCidr: '172.17.0.0/16'
    }
    enableRBAC: true
    aadProfile: {
      adminGroupObjectIDs: [
        aksadminaccessprincipalId
      ]
      enableAzureRBAC: true
      managed: true
      tenantID: subscription().tenantId
    }
    addonProfiles: {
      omsagent: {
        config: {
          logAnalyticsWorkspaceResourceID: akslaworkspace.id
        }
        enabled: true
      }
      azurepolicy: {
        enabled: true
      }
      ingressApplicationGateway: {
        enabled: true
        config: {
          applicationGatewayId: appGateway.id
          effectiveApplicationGatewayId: appGateway.id
        }
      }
      azureKeyvaultSecretsProvider: {
        enabled: true
      }
    }
  }
  dependsOn: [
    aksPvtDNSContrib
    aksPvtNetworkContrib
    aksPodIdentityRole
    aksRouteTableRole
    aksPolicy
  ]
}

resource fluxExtension 'Microsoft.KubernetesConfiguration/extensions@2022-11-01' = {
  name: 'flux'
  properties: {
    extensionType: 'Microsoft.KubernetesConfiguration/extensions'
  }
  plan: {
    name: 'flux'
    publisher: 'fluxcd'
    product: 'flux'
  }
  dependsOn: [
    aksCluster
  ]
}

module aksRouteTableRole 'modules/Identity/rtrole.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'aksRouteTableRole'
  params: {
    principalId: aksIdentity.properties.principalId
    roleGuid: '4d97b98b-1d4f-4787-a291-c67834d212e7' //Network Contributor
    rtName: rtAKSName
  }
}

module acraksaccess 'modules/Identity/acrrole.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'acraksaccess'
  params: {
    principalId: aksCluster.properties.identityProfile.kubeletidentity.objectId
    roleGuid: '7f951dda-4ed3-4680-a7ca-43fe172d538d' //AcrPull
    acrName: acrName
  }
}

module aksPvtNetworkContrib 'modules/Identity/networkcontributorrole.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'aksPvtNetworkContrib'
  params: {
    principalId: aksIdentity.properties.principalId
    roleGuid: '4d97b98b-1d4f-4787-a291-c67834d212e7' //Network Contributor
    vnetName: vnetName
  }
}

module aksPvtDNSContrib 'modules/Identity/pvtdnscontribrole.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'aksPvtDNSContrib'
  params: {
    location: location
    principalId: aksIdentity.properties.principalId
    roleGuid: 'b12aa53e-6015-4669-85d0-8515ebb3ae7f' //Private DNS Zone Contributor
    pvtdnsAKSZoneName: privateDNSZoneAKSName
  }
}

module aksuseraccess 'modules/Identity/role.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'aksuseraccess'
  params: {
    principalId: aksuseraccessprincipalId
    roleGuid: '4abbcc35-e782-43d8-92c5-2d3f1bd2253f' //Azure Kubernetes Service Cluster User Role
  }
}

module aksadminaccess 'modules/Identity/role.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'aksadminaccess'
  params: {
    principalId: aksadminaccessprincipalId
    roleGuid: '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8' //Azure Kubernetes Service Cluster Admin Role
  }
}

module appGatewayContributerRole 'modules/Identity/appgtwyingressroles.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'appGatewayContributerRole'
  params: {
    principalId: aksCluster.properties.addonProfiles.ingressApplicationGateway.identity.objectId
    roleGuid: 'b24988ac-6180-42a0-ab88-20f7382dd24c' //Contributor
    applicationGatewayName: appGateway.name
  }
}

module appGatewayReaderRole 'modules/Identity/role.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'appGatewayReaderRole'
  params: {
    principalId: aksCluster.properties.addonProfiles.ingressApplicationGateway.identity.objectId
    roleGuid: 'acdd72a7-3385-48ef-bd42-f606fba81ae7' //Reader
  }
}

module keyvaultAccessPolicy 'modules/keyvault/keyvault.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'akskeyvaultaddonaccesspolicy'
  params: {
    keyvaultManagedIdentityObjectId: aksCluster.properties.addonProfiles.azureKeyvaultSecretsProvider.identity.objectId
    vaultName: keyvaultName
    aksuseraccessprincipalId: aksuseraccessprincipalId
  }
}

resource rtAppGW 'Microsoft.Network/routeTables@2021-02-01' existing = {
  scope: resourceGroup(rgName)
  name: rtAppGWSubnetName
}

module appgwroutetableroutes 'modules/vnet/routetableroutes.bicep' = [for i in range(0, 3): if (networkPlugin == 'kubenet') {
  scope: resourceGroup(rg.name)
  name: 'aks-vmss-appgw-pod-node-${i}'
  params: {
    routetableName: rtAppGW.name
    routeName: 'aks-vmss-appgw-pod-node-${i}'
    properties: {
      nextHopType: 'VirtualAppliance'
      nextHopIpAddress: '${split(aksSubnet.properties.addressPrefix, ipdelimiters)[0]}.${split(aksSubnet.properties.addressPrefix, ipdelimiters)[1]}.${int(split(aksSubnet.properties.addressPrefix, ipdelimiters)[2])}.${int(split(aksSubnet.properties.addressPrefix, ipdelimiters)[3]) + i + 4}'
      addressPrefix: '${split(akskubenetpodcidr, ipdelimiters)[0]}.${split(akskubenetpodcidr, ipdelimiters)[1]}.${int(split(akskubenetpodcidr, ipdelimiters)[2]) + i}.${split(akskubenetpodcidr, ipdelimiters)[3]}/${split(akskubenetpodcidr, ipdelimiters)[4]}'
    }
  }
}]

//  Telemetry Deployment
@description('Enable usage and telemetry feedback to Microsoft.')
param enableTelemetry bool = true
var telemetryId = 'a4c036ff-1c94-4378-862a-8e090a88da82-${location}'
resource telemetrydeployment 'Microsoft.Resources/deployments@2021-04-01' = if (enableTelemetry) {
  name: telemetryId
  location: location
  properties: {
    mode: 'Incremental'
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
      contentVersion: '1.0.0.0'
      resources: {}
    }
  }
}
