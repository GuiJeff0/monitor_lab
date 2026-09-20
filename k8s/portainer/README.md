# Gestão Visual do Cluster (`k8s/portainer`)

Este diretório gerencia o controle de acesso e permissões da interface web Portainer CE para visualização de workloads do Kubernetes.

## Arquivos

- **`portainer-rbac.yaml`**: Define a conta de serviço (`portainer-sa-clusteradmin`) e a `ClusterRole` restrita (`portainer-restricted`).
  - **Permitido:** Leitura de Pods, Deployments, StatefulSets, DaemonSets, Services, ConfigMaps, HPAs, Jobs, Nós, StorageClasses e Métricas.
  - **Bloqueado:** Totalmente sem permissão sobre `secrets` em qualquer namespace (protegendo chaves do SOPS e senhas de banco contra extração na UI).
