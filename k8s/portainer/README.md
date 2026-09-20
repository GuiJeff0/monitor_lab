# Gestão Visual do Cluster (`k8s/portainer`)

Este diretório gerencia o controle de acesso e permissões da interface web Portainer CE para visualização de workloads do Kubernetes.

## Arquivos

- **`portainer-rbac.yaml`**: Define a conta de serviço (`portainer-sa-clusteradmin`) e a `ClusterRole` restrita (`portainer-restricted`).
  - **Permitido:** Leitura (`get`, `list`, `watch`) de Pods, Deployments, StatefulSets, DaemonSets, Services, ConfigMaps, HPAs, Jobs, Nós, StorageClasses, Métricas e Secrets (necessário para o Helm listar e inspecionar releases como Traefik, Grafana e Alloy).
  - **Bloqueado:** Totalmente sem permissões de escrita/modificação/deleção (`create`, `update`, `patch`, `delete`) em Secrets e infraestrutura crítica.
