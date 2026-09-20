# Observability Lab — Plataforma Cloud-Native de Microsserviços & Observabilidade

Infraestrutura de observabilidade e orquestração cloud-native de nível empresarial para qualquer ecossistema de
microsserviços de alta concorrência, provisionada via **Terraform** em **K3s (Kubernetes)**, com **Portainer CE**,
**Traefik v3**, stack **LGTM** (Grafana, Mimir, Loki, Tempo, Alloy), **OpenTelemetry**, **SOPS + age** para segredos
e **GitOps com Flux CD e Docker Hub**.

---

## 🏛️ Visão Geral da Arquitetura

```text
                          Clientes (Web / Mobile / Tailscale Peers)
                                             │
                                  HTTP (80) / HTTPS (443)
                                    via Tailscale Mesh
                                             │
                                             ▼
                                  ┌────────────────────┐
                                  │     Traefik v3     │
                                  │ Ingress Controller │
                                  └──────────┬─────────┘
                                             │ HTTP / Routing
                     ┌───────────────────────┼───────────────────────┐
                     │                       │                       │
                     ▼                       ▼                       ▼
            ┌─────────────────┐    ┌─────────────────┐    ┌──────────────────┐
            │   Portainer CE  │    │   FastAPI BFF   │    │     Grafana      │
            │  Gestão do K3s  │    │  (API Gateway)  │    │  Dashboards LGTM │
            └─────────────────┘    └─────────┬───────┘    └──────────────────┘
                                             │
                       ┌─────────────────────┴─────────────────────┐
                       │ (gRPC Síncrono)                           │ (AMQP Assíncrono)
                       ▼                                           ▼
         ┌───────────────────────────┐               ┌───────────────────────────┐
         │    Serviços Síncronos     │               │      Message Broker       │
         │         (Golang)          │               │         RabbitMQ          │
         │  • Auth Service   (:50051)│               └─────────────┬─────────────┘
         │  • User Service   (:50052)│                             │
         │  • Event Service  (:50053)│                             ▼ Consumo
         └─────────────┬─────────────┘               ┌───────────────────────────┐
                       │                             │   Serviços Assíncronos    │
                       ▼                             │  • Orders Service         │
         ┌───────────────────────────┐               │  • Payment Service        │
         │   Persistência Poliglota  │               │  • Notification Service   │
         │ PostgreSQL / Mongo / ES   │               └─────────────┬─────────────┘
         └───────────────────────────┘                             │
                       │                                           │
                       └───────────── OpenTelemetry SDK ───────────┘
                                             │
                                      (OTLP gRPC :4317)
                                             │
                                             ▼
                               ┌───────────────────────────┐
                               │  Grafana Alloy DaemonSet  │
                               │  Coleta Unificada de OTel │
                               └─────────────┬─────────────┘
                                             │
                     ┌───────────────────────┼───────────────────────┐
                     │ (Metrics)             │ (Logs)                │ (Traces)
                     ▼                       ▼                       ▼
                   Mimir                   Loki                    Tempo
```

---

## 🛠️ Componentes da Stack

| Componente | Versão | Função | Rota Host / Porta |
|---|---|---|---|
| **Portainer CE** | `2.27` | Gerenciamento visual do K3s, Pods, Volumes e Logs | `http://<tailscale-host>/portainer/` |
| **Grafana** | `11.5` | Visualização unificada (Métricas, Logs, Traces) | `http://<tailscale-host>/grafana/` |
| **Traefik v3** | `v3.7` | Ingress Controller, Load Balancer e Proxy Reverso | `http://<tailscale-host>/traefik/dashboard/` |
| **Grafana Mimir** | `2.15` | TSDB de métricas escalável compatível com PromQL | Interno (`mimir.observability:8080`) |
| **Grafana Loki** | `3.7` | Ingestão e agregação de logs com LogQL | Interno (`loki.observability:3100`) |
| **Grafana Tempo** | `2.6` | Armazenamento e consulta de Distributed Traces | Interno (`tempo.observability:3200`) |
| **Grafana Alloy** | `v1.7` | DaemonSet coletor OTel (Receives OTLP, scrapes Pod logs) | Interno (`alloy.observability:4317`) |
| **Flux CD** | `v2` | GitOps Controller reconciliando o repositório Git | Interno (`flux-system`) |

> **Acesso via Tailscale:** Substitua `<tailscale-host>` pelo seu hostname MagicDNS (ex: `creedx66.tail096995.ts.net`).

---

## 📚 Guias Essenciais (`docs/`)

- 🚀 **[Fluxo de Dados e Arquitetura Completa](docs/data-flow-and-architecture.md)** — Como as requisições, eventos assíncronos e a telemetria trafegam.
- 🧪 **[Como Testar Localmente](docs/local-development-and-testing.md)** — Port-forwarding, curl, logs e depuração de Pods no terminal.
- 🧩 **[Como Subir um Microsserviço Integrado & GitOps CD](docs/microservice-integration-guide.md)** — Instrumentação com OTel SDK (Go/Python), scaffold com `add-microservice.sh` e pipeline CI/CD GitOps com Flux CD.
- 🔐 **[Gestão de Secrets com SOPS e age](docs/sops-secrets-management.md)** — Criptografia de segredos versionados com segurança no Git.
- 📖 **[Guia Operacional de Bootstrap K3s](docs/k3s-migration-guide.md)** — Instruções de inicialização do cluster via scripts e Terraform.

---

## 📁 Estrutura do Repositório

```text
monitor_lab/
├── terraform/                          # Infraestrutura como Código (IaC)
│   ├── providers.tf                    # Provedores Kubernetes e Helm
│   ├── variables.tf                    # Variáveis parametrizáveis
│   ├── main.tf                         # Namespaces, Traefik, Portainer, LGTM, Alloy e Flux
│   └── outputs.tf                      # URLs de acesso direto aos dashboards
│
├── k8s/                                # Manifestos Kubernetes estruturados (GitOps)
│   ├── system/                         # ResourceQuotas e governança de cluster
│   ├── ingress/                        # Traefik IngressRoutes e Middlewares
│   ├── observability/                  # ConfigMaps e StatefulSets (Mimir, Loki, Tempo, Alloy)
│   ├── portainer/                      # RBAC e regras de acesso do Portainer CE
│   ├── apps/                           # Deployments de microsserviços com OTel
│   │   └── _template/                  # Template canônico de deployment
│   ├── data/                           # Bases de dados e mensageria (Postgres, RabbitMQ, Mongo)
│   ├── gitops/                         # Reconciliação contínua e segredos (Flux CD + SOPS)
│   └── kustomization.yaml              # Manifesto raiz orquestrador do Flux CD
│
├── templates/                          # Templates de CI/CD para repositórios externos
│   └── microservice-ci-cd.yml          # Pipeline GitHub Actions (Build, Push & GitOps Trigger)
│
├── secrets/                            # Segredos criptografados com SOPS
│   ├── .sops.yaml                      # Regras de encriptação
│   ├── README.md                       # Guia rápido de uso do SOPS
│   └── templates/                      # Templates de segredos anonimizados
│
├── scripts/                            # Scripts de automação do servidor
│   ├── add-microservice.sh             # Scaffold automático de novo microsserviço no K3s
│   ├── mount-hdd.sh                    # Formatação e montagem do HDD de 1TB
│   ├── bootstrap-tools.sh              # Instalação de kubectl, helm, terraform, age, sops
│   ├── install-k3s.sh                  # Instalação e configuração do K3s
│   └── sops-keygen.sh                  # Geração de par de chaves age
│
├── .github/workflows/                  # CI/CD no GitHub Actions
│   ├── ci.yml                          # Validação contínua do K8s (Kustomize) e linters
│   └── terraform-validate.yml          # Lint e validação contínua do Terraform
│
└── docs/                               # Documentação centralizada
```

---

## 🚀 Comandos Rápidos de Verificação do Cluster

```bash
# Verificar status do nó
kubectl get nodes -o wide

# Visualizar todos os pods rodando
kubectl get pods -A

# Visualizar logs em tempo real
kubectl logs -n observability daemonset/alloy -f
kubectl logs -n ingress deployment/traefik -f
```
