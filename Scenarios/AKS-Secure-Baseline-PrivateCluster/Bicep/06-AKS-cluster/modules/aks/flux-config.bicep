targetScope = 'resourceGroup'

param clusterName string = 'gitopsakscluster'

resource aksCluster 'Microsoft.ContainerService/managedClusters@2022-01-02-preview' existing = {
  name: clusterName
}

resource fluxConfiguration 'Microsoft.KubernetesConfiguration/fluxConfigurations@2022-11-01' = {
  name: 'demoapp'
  scope: aksCluster
  properties: {
    gitRepository: {
      repositoryRef: {
        branch: 'master'
      }
      syncIntervalInSeconds: 3600
      url: 'https://github.com/Azure/arc-cicd-demo-src.git'
    }
    kustomizations: {
          'voteapp': {
            name : 'vote'
            path : 'azure-vote/manifests/azure-vote/kustomize/base'
            dependsOn: []
            timeoutInSeconds: 600
            syncIntervalInSeconds: 600
          }
    }
    namespace: 'demoapp'
    scope: 'cluster'
    sourceKind: 'GitRepository'
  }
}
