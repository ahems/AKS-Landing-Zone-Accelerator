targetScope = 'resourceGroup'

param clusterName string = 'gitopsakscluster'

resource aksCluster 'Microsoft.ContainerService/managedClusters@2022-01-02-preview' existing = {
  name: clusterName
}

resource fluxExtension 'Microsoft.KubernetesConfiguration/extensions@2022-11-01' = {
  name: 'flux'
  scope: aksCluster
  properties: {
    extensionType: 'Microsoft.KubernetesConfiguration/extensions'
    configurationSettings: {
      operatorInstanceName: 'flux'
      operatorNamespace: 'flux'
      operatorParams: '--git-readonly=true --git-path=clusters/aks --git-branch=main --git-url=<your-git-url>'
    }
  }
  plan: {
    name: 'flux'
    publisher: 'fluxcd'
    product: 'flux'
  }
}
