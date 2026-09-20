# Observability Lab — Plataforma de Infraestrutura, Observabilidade & Microsserviços

> Plataforma cloud-native para orquestração, monitoramento contínuo, tracing distribuído e arquitetura orientada a eventos para o ecossistema de microsserviços de alta concorrência.

---

## Objetivo da Plataforma

Este repositório (`monitor_lab`) gerencia a **Infraestrutura como Código (IaC)**, o **Cluster Kubernetes (K3s)**, a **Stack de Observabilidade LGTM** e o pipeline de **GitOps & Secrets** para hospedar e monitorar os microsserviços do ecossistema:

- **Orquestração e IaC:** K3s provisionado e gerenciado via **Terraform**, separando namespaces (`ingress`, `observability`, `apps`, `data`, `portainer`, `flux-system`).
- **Gerenciamento Visual do Cluster:** **Portainer CE** integrado nativamente para visualização de Pods, Deployments, Volumes e Logs.
- **Roteamento & Ingress:** **Traefik v3** como Ingress Controller, API Gateway e Load Balancer com middlewares de controle de acesso (Tailscale Mesh).
- **Observabilidade Completa (LGTM Stack + OpenTelemetry):**
  - **Grafana Mimir:** TSDB escalável para métricas via PromQL e OTLP.
  - **Grafana Loki:** Ingestão e agregação estruturada de logs via LogQL e OTLP.
  - **Grafana Tempo:** Distributed Tracing ponta a ponta via TraceQL e OTLP gRPC/HTTP.
  - **Grafana Alloy:** DaemonSet coletor unificado de telemetria (OTLP Receiver, Pod logs, Node Exporter e cAdvisor).
  - **Grafana:** Dashboards unificados com correlação cruzada automática (Log ↔ Trace ↔ Métrica).
- **Gestão de Segredos & GitOps:**
  - **SOPS + age:** Criptografia assimétrica de segredos commitados com segurança no Git (`*.enc.yaml`).
  - **Flux CD:** Reconciliação contínua e decriptação automática de segredos em runtime.
  - **GitHub Actions & Docker Hub:** Pipelines de CI/CD para build, lint, teste e push automatizado de imagens.
- **Topologia de Armazenamento Inteligente:**
  - **NVMe SSD (`/dev/nvme0n1`, ~120GB):** Sistema operacional, binários do K3s e etcd leve.
  - **SATA HDD (`/dev/sda1`, 1TB, montado em `/mnt/dados`):** StorageClass padrão `local-hdd` para dados massivos (Mimir TSDB, Loki chunks, Tempo blocks e bancos de dados).

---

# Arquitetura Geral da Plataforma

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
                                             │
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

# Tecnologias Utilizadas

## Infraestrutura & Orquestração
- **K3s (Kubernetes):** Cluster lightweight de produção rodando containerd.
- **Terraform:** Provisionamento declarativo de namespaces, StorageClasses e Helm releases.
- **Portainer CE:** Interface web para gerenciamento de Pods, Deployments e Volumes.
- **Tailscale:** Rede VPN mesh segura com MagicDNS (`<node-name>.<tailnet>.ts.net`).
- **Traefik v3:** Ingress Controller com CRDs nativos (IngressRoute, Middlewares).
- **Flux CD:** Operador GitOps para reconciliação contínua do repositório Git.
- **SOPS + age:** Criptografia de secrets versionados em Git.

## Observabilidade (Grafana Stack + OTel)
- **OpenTelemetry SDK:** Instrumentação de aplicações em Go e Python (Métricas, Logs, Traces).
- **Grafana Mimir:** TSDB escalável com retenção no HDD (`local-hdd`).
- **Grafana Loki:** Agregador de logs estruturados com índices TSDB e retenção configurável.
- **Grafana Tempo:** Backend de tracing distribuído via TraceQL e geração de service-graphs.
- **Grafana Alloy:** DaemonSet coletor OTel, receptor OTLP, raspador de logs de Pods e métricas de sistema (Node Exporter e cAdvisor).
- **Grafana:** Dashboards com correlação cruzada total (Log ↔ Trace ↔ Métrica).

---

# Pipeline de Telemetria e Padrões de Integração

Todo microsserviço que se conecta a esta plataforma deve seguir as diretrizes documentadas em [`docs/microservice-integration-guide.md`](docs/microservice-integration-guide.md):

1. **W3C Trace Context:** Propagação contínua do header `traceparent` (e `baggage`) através de HTTP, gRPC (metadados) e RabbitMQ (headers da mensagem AMQP).
2. **Correlation ID:** Header `X-Correlation-ID` propagado em todas as camadas e injetado em:
   - Respostas HTTP públicas (`X-Correlation-ID`).
   - Logs estruturados em formato JSON (`correlation_id`).
   - Mensagens de erro para rastreabilidade de suporte.
3. **Structured Logs:** Logs estruturados contendo obrigatoriamente `trace_id`, `span_id`, `correlation_id` e `service.name`.
4. **Métricas RED:** *Rate* (Taxa de requisições), *Errors* (Taxa de erros) e *Duration* (Histograma de latência p50/p95/p99).

---

# Estrutura do Repositório Central

```text
monitor_lab/
├── terraform/                          # Infraestrutura como Código (IaC)
│   ├── providers.tf                    # Provedores Kubernetes e Helm
│   ├── variables.tf                    # Variáveis parametrizáveis (Tailscale, Storage)
│   ├── main.tf                         # Namespaces, Traefik v3, Portainer, LGTM, Alloy e Flux
│   └── outputs.tf                      # URLs de acesso direto aos dashboards
│
├── k8s/                                # Manifests Kubernetes (GitOps)
│   ├── ingress/                        # Traefik IngressRoutes e Middlewares
│   ├── observability/                  # ConfigMaps e StatefulSets (Mimir, Loki, Tempo, Alloy)
│   ├── apps/                           # Deployments de microsserviços com OTel
│   │   └── _template/                  # Template canônico de deployment
│   ├── kustomization.yaml              # Manifesto raiz gerenciado pelo Flux CD
│   └── gitops/flux-sync.yaml           # Sincronização automática com Flux CD
│
├── templates/                          # Templates de CI/CD para repositórios externos
│   └── microservice-ci-cd.yml          # Pipeline GitHub Actions (Build, Push & GitOps Trigger)
│
├── secrets/                            # Segredos criptografados com SOPS
│   ├── .sops.yaml                      # Regras de encriptação com chave age
│   ├── README.md                       # Guia de criptografia e decriptação
│   └── templates/                      # Templates anonimizados para novos serviços
│
├── scripts/                            # Scripts de automação do servidor
│   ├── add-microservice.sh             # Scaffold automático de novo microsserviço no K3s
│   ├── mount-hdd.sh                    # Formatação e montagem do HDD de 1TB
│   ├── bootstrap-tools.sh              # Instalação de kubectl, helm, terraform, age, sops
│   ├── install-k3s.sh                  # Instalação e configuração do K3s
│   └── sops-keygen.sh                  # Geração de par de chaves age
│
├── .github/workflows/                  # CI/CD no GitHub Actions
│   ├── ci-microservice.yml             # Build e push para Docker Hub
│   └── terraform-validate.yml          # Lint e validação contínua do Terraform
│
└── docs/                               # Documentação técnica centralizada
    ├── README.md                       # Índice geral da plataforma
    ├── data-flow-and-architecture.md   # Fluxos síncronos, assíncronos e telemetria
    ├── microservice-integration-guide.md # Guia de integração OTel SDK, Traces, Scaffold e GitOps CD
    ├── local-development-and-testing.md  # Port-forwarding, curl e depuração
    ├── sops-secrets-management.md      # Criptografia de segredos com SOPS e age
    ├── k3s-migration-guide.md          # Guia operacional de bootstrap K3s
    ├── standards/                      # Padrões de engenharia e telemetria
    └── infrastructure/                 # Documentação detalhada dos componentes de infra
```

---

# Roadmap de Implementação

## Fase 1 — Fundação de Infraestrutura, Observabilidade & GitOps
- [x] Cluster K3s com storage persistente no HDD de 1TB (`/mnt/dados`)
- [x] Provisionamento declarativo via Terraform
- [x] Traefik v3 Ingress Controller & Roteamento seguro via Tailscale
- [x] Portainer CE integrado para gestão visual do K3s
- [x] Stack Grafana (Grafana, Mimir, Loki, Tempo, Alloy DaemonSet)
- [x] Correlação Cruzada de Telemetria (Logs ↔ Traces ↔ Métricas)
- [x] Monitoramento da Máquina Host (Node Exporter) e Containers (cAdvisor)
- [x] Criptografia de Secrets com SOPS + age e automação GitOps com Flux CD

## Fase 2 — Message Broker & Persistência Poliglota (K3s)
- [ ] Subida do cluster RabbitMQ (com UI de Management) no namespace `data`
- [ ] Instâncias do PostgreSQL, MongoDB e Elasticsearch com PVCs no HDD
- [ ] Configuração de índices e migrações iniciais

## Fase 3 — API Gateway (FastAPI BFF) & Autenticação
- [ ] `fastapi-bff` com validação Pydantic, rate limit e cache Redis no namespace `apps`
- [ ] `auth-service` (Go/gRPC) com geração/validação de JWT e hash bcrypt
- [ ] Propagação de contexto HTTP ↔ gRPC com OTel SDK

## Fase 4 — Catálogo de Eventos & Busca Full-Text
- [ ] `event-service` (Go/gRPC) integrado ao MongoDB
- [ ] `search-sync-worker` (Go/AMQP) sincronizando eventos no Elasticsearch
- [ ] Caching de catálogo de eventos de alta frequência no Redis

## Fase 5 — Pipeline de Compra de Ingressos de Alta Concorrência
- [ ] `orders-service` (Go/AMQP/gRPC) com bloqueio pessimista (`SKIP LOCKED`) no PostgreSQL
- [ ] `payment-service` (Go/AMQP) simulando gateway de pagamento e resiliência
- [ ] `notification-service` (Go/AMQP) processando notificações e auditoria no MongoDB

## Fase 6 — Testes de Carga & Validação de Observabilidade
- [ ] Testes de carga massiva com k6 simulando disputa de ingressos (flash sale)
- [ ] Validação de Trace distribuído ponta a ponta (Cliente → BFF → gRPC → RabbitMQ → PostgreSQL)
- [ ] Dashboards RED completos no Grafana e alertas em tempo real