targetScope = 'resourceGroup'

param clusterName string = 'gitopsakscluster'

resource aksCluster 'Microsoft.ContainerService/managedClusters@2022-01-02-preview' existing = {
  name: clusterName
}

resource namespaceCreation 'Microsoft.KubernetesConfiguration/fluxConfigurations@2022-11-01' = {
  name: 'demoappnamespaces'
  scope: aksCluster
  properties: {
    gitRepository: {
      repositoryRef: {
        branch: 'master'
      }
      syncIntervalInSeconds: 3600
      url: 'https://github.com/Azure/arc-cicd-demo-gitops.git'
    }
    kustomizations: {
          'namespaces': {
            path : 'arc-cicd-cluster/manifests'
            dependsOn: []
            timeoutInSeconds: 600
            syncIntervalInSeconds: 600
          }
    }
    scope: 'cluster'
    sourceKind: 'GitRepository'
  }
}

resource appDeployment 'Microsoft.KubernetesConfiguration/fluxConfigurations@2022-11-01' = {
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
          'voteappdev': {
            path : 'azure-vote/manifests/azure-vote/kustomize/base'
            dependsOn: []
            timeoutInSeconds: 600
            syncIntervalInSeconds: 600
          }
    }
    namespace: 'dev'
    scope: 'cluster'
    sourceKind: 'GitRepository'
  }
}
