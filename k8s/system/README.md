# Sistema e Governança do Cluster (`k8s/system`)

Este diretório gerencia políticas de governança, limites de recursos e prevenção contra exaustão de memória/CPU em todo o cluster Kubernetes.

## Arquivos

- **`resource-quotas.yaml`**: Define `ResourceQuota` e `LimitRange` para os namespaces:
  - `apps`: Limita CPU (2 req / 4 lim), RAM (2Gi req / 4Gi lim), máximo de 20 pods.
  - `observability`: Limita CPU (2 req / 4 lim), RAM (3Gi req / 6Gi lim), máximo de 10 pods.
  - `data`: Limita CPU (3 req / 6 lim), RAM (4Gi req / 8Gi lim), máximo de 15 pods.
  - `LimitRanges`: Injeta limites e requisições padrão em containers que omitirem tais configurações, garantindo admissão segura no cluster.
