targetScope = 'resourceGroup'

param clusterName string = 'gitopsakscluster'

resource aksCluster 'Microsoft.ContainerService/managedClusters@2022-01-02-preview' existing = {
  name: clusterName
}

resource fluxConfiguration 'Microsoft.KubernetesConfiguration/fluxConfigurations@2022-11-01' = {
  name: 'fluxConfig'
  scope: aksCluster
  properties: {
    gitRepository: {
      repositoryRef: {
        branch: 'master'
      }
      syncIntervalInSeconds: 3600
      timeoutInSeconds: int
      url: 'https://github.com/Azure/arc-cicd-demo-src'
    }
    namespace: 'demoapp'
    scope: 'cluster'
    sourceKind: 'GitRepository'
  }
}
