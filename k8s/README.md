# Manifestos Kubernetes (K3s GitOps)

Este diretório contém todos os manifestos declarativos do cluster Kubernetes (K3s), organizados de forma
modular por camadas funcionais e orquestrados pelo Kustomize e Flux CD v2.

---

## 1. Estrutura Modular

```text
k8s/
├── system/             # Limites de governança e quotas de recursos (ResourceQuotas)
├── ingress/            # Roteamento de borda Traefik (IngressRoutes, Middlewares)
├── observability/      # Stack LGTM (Alloy, Loki, Mimir, Tempo, NetworkPolicies, Secrets)
├── portainer/          # RBAC e permissões de cluster para a UI do Portainer CE
├── apps/               # Deployments e microsserviços de negócio instrumentados com OTel
│   └── _template/      # Scaffold de referência para novos microsserviços
├── data/               # Bases de dados e mensageria (PostgreSQL, RabbitMQ, Redis, Mongo)
├── gitops/             # Sincronização contínua com Flux CD e decriptação SOPS
└── kustomization.yaml  # Orquestrador raiz que agrega todos os módulos acima
```

---

## 2. Detalhes de Cada Módulo

| Módulo | Namespace Alvo | Descrição |
|---|---|---|
| [`system/`](system/README.md) | `apps`, `observability` | Quotas de CPU/memória para prevenir saturação do nó K3s. |
| [`ingress/`](ingress/README.md) | `ingress`, `observability`, `portainer`, `apps` | IngressRoutes, middlewares de segurança e allowlist Tailscale. |
| [`observability/`](observability/README.md) | `observability` | Coleta e armazenamento unificado de telemetria LGTM e OTel. |
| [`portainer/`](portainer/README.md) | `portainer` | ClusterRole e ClusterRoleBinding do Portainer para métricas do cluster. |
| [`apps/`](apps/README.md) | `apps` | Cargas de trabalho de negócio com injeção de credenciais e OTel. |
| [`data/`](data/README.md) | `data` | Persistência poliglota e mensageria no HDD persistente (`/mnt/dados`). |
| [`gitops/`](gitops/README.md) | `flux-system` | Reconciliação contínua e decriptação segura de segredos via SOPS/age. |

---

## 3. Validação e Teste Local

Antes de commitar alterações nos manifestos, execute a validação da árvore Kustomize:

```bash
# Validar se a compilação de todos os módulos Kustomize é bem-sucedida
kubectl kustomize k8s/ > /dev/null

# Aplicar em modo dry-run no cluster
kubectl kustomize k8s/ | kubectl apply --dry-run=client -f -
```
