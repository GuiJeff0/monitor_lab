# Observability Lab — High-Concurrency Ticket Booking System

> Um laboratório completo para estudo e implementação prática de **Observabilidade**, **Monitoramento**, **Arquitetura Orientada a Eventos** e **Microsserviços de Alta Concorrência** utilizando tecnologias modernas de produção.

---

## Objetivo

Este projeto fornece uma infraestrutura completa e padrões arquiteturais para desenvolver, orquestrar e monitorar o ecossistema do **Ticket Booking System** (Sistema de Vendas de Ingressos de Alta Concorrência):

- **Observabilidade Completa:** Métricas (Mimir), Logs Centralizados (Loki), Tracing Distribuído (Tempo) e Dashboards unificados (Grafana).
- **Ingresso e Roteamento:** Traefik v3 como Reverse Proxy, API Gateway, roteamento TLS e Service Discovery.
- **BFF (Backend for Frontend):** FastAPI em Python gerenciando validações, autenticação, rate limiting e cache distribuído com Redis.
- **Microsserviços de Alta Performance:** Microsserviços internos em Golang com comunicação síncrona de ultrabaixa latência via **gRPC** (Protobuf).
- **Mensageria Assíncrona & Resiliência:** RabbitMQ absorvendo picos extremos de tráfego de compras de ingressos, controle de Dead Letter Exchange (DLX) e Publisher Confirms.
- **Persistência Poliglota:**
  - **PostgreSQL:** ACID, integridade transacional e controle de concorrência com *Row-Level Locking* (`FOR UPDATE SKIP LOCKED`).
  - **MongoDB:** Catálogo de eventos e trilhas de auditoria flexíveis.
  - **Elasticsearch:** Busca textual e filtros facetados em tempo real sincronizados via workers assíncronos.
- **Instrumentação OpenTelemetry (OTel SDK):** Exportação direta OTLP para logs, métricas e traces com propagação de contexto W3C e Correlation ID.

As aplicações são desenvolvidas em **repositórios independentes** simulando um ambiente enterprise cloud-native.

---

# Arquitetura Geral

```text
                          Clientes (Web / Mobile / Tailscale Peers)
                                             │
                                  HTTP (80) / HTTPS (443)
                                    via Tailscale Mesh
                                             │
                                             ▼
                                  ┌────────────────────┐
                                  │     Traefik v3     │
                                  │   Reverse Proxy    │
                                  └──────────┬─────────┘
                                             │ HTTP
                                             ▼
                                  ┌────────────────────┐      ┌──────────────┐
                                  │    FastAPI BFF     │◄────►│    Redis     │
                                  │   (API Gateway)    │      │ Cache/Limits │
                                  └────┬───────────┬───┘      └──────────────┘
                                       │           │
                 ┌─────────────────────┘           └──────────────────────┐
                 │ (Síncrono - gRPC)                                      │ (Assíncrono - AMQP)
                 ▼                                                        ▼
   ┌───────────────────────────┐                            ┌───────────────────────────┐
   │    Serviços Síncronos     │                            │     Message Broker        │
   │         (Golang)          │                            │        RabbitMQ           │
   │                           │                            └─────────────┬─────────────┘
   │  • Auth Service   (:50051)│                                          │
   │  • User Service   (:50052)│                                          │ Consumo
   │  • Event Service  (:50053)│                                          ▼
   └─────────────┬─────────────┘                            ┌───────────────────────────┐
                 │                                          │    Serviços Assíncronos   │
                 │                                          │         (Golang)          │
                 │                                          │                           │
                 │                                          │  • Orders Service         │
                 │                                          │  • Payment Service        │
                 │                                          │  • Notification Service   │
                 │                                          │  • Search Sync Worker     │
                 │                                          └─────────────┬─────────────┘
                 ▼                                                        ▼
   ┌────────────────────────────────────────────────────────────────────────────────────┐
   │                               PERSISTÊNCIA POLIGLOTA                               │
   ├──────────────────────────┬─────────────────────────────┬───────────────────────────┤
   │        PostgreSQL        │           MongoDB           │       Elasticsearch       │
   │ (Users, Orders, Tickets) │  (Event Catalog, Audit Logs)│  (Event Search & Filters) │
   └──────────────────────────┴─────────────────────────────┴───────────────────────────┘
                 │                                                        │
                 └──────────────────── OpenTelemetry SDK ────────────────┘
                                  │              │              │
                            (OTLP Metrics)  (OTLP Logs)   (OTLP Traces)
                                  │              │              │
                                  ▼              ▼              ▼
                                Mimir          Loki           Tempo
                                  │              │              │
                                  └──────────────┼──────────────┘
                                                 │
                                                 ▼
                                              Grafana
```

---

# Tecnologias

## Infraestrutura & Plataforma
- **Docker & Docker Compose:** Orquestração de containers, bind mounts com `DATA_DIR` e redes dedicadas.
- **Topologia de Armazenamento do Servidor (`creedx66`):**
  - **SSD NVMe (`/dev/nvme0n1`, ~120GB, montado em `/`):** Exclusivo para Sistema Operacional, binários do APT e configs. **Protegido contra I/O pesado.**
  - **HDD SATA (`/dev/sda1`, 1TB, montado em `/mnt/dados/`):** Repositório de dados persistentes massivos e volumes de containers (Mimir TSDB, Loki logs, Tempo traces, Postgres, MongoDB, Elasticsearch).
  - **Variável `DATA_DIR`:** Controla o destino da persistência (`./data` no ambiente local de dev, `/mnt/dados/observability` no servidor `creedx66`).
- **Tailscale:** Rede VPN mesh segura com WireGuard e MagicDNS (`<node-name>.<tailnet>.ts.net`).
- **Traefik v3:** Reverse Proxy, API Gateway, roteamento por PathPrefix e Service Discovery.
- **RabbitMQ:** Broker AMQP para absorção de carga e mensageria assíncrona.
- **Redis:** Caching de alto desempenho e rate limiting.

## Observabilidade (Grafana Stack + OTel)
- **OpenTelemetry SDK:** Instrumentação de aplicações em Python e Go (Metrics, Logs, Traces).
- **Grafana Mimir:** TSDB para métricas em larga escala (compatível com PromQL e OTLP).
- **Grafana Loki:** Armazenamento e consulta estruturada de logs via LogQL e OTLP.
- **Grafana Tempo:** Backend de tracing distribuído via TraceQL e OTLP gRPC/HTTP.
- **Grafana Alloy:** Coleta unificada de logs de containers e métricas de infraestrutura.
- **Grafana:** Visualização unificada com correlação cruzada (Log ↔ Trace ↔ Metric).

## Armazenamento de Dados (Persistência Poliglota)
- **PostgreSQL 16:** Transações ACID e controle de concorrência pessimista (`FOR UPDATE SKIP LOCKED`).
- **MongoDB 7:** Catálogo de eventos semiesquematizado e logs de auditoria.
- **Elasticsearch 8:** Mecanismo de busca textual e agregação de eventos em tempo real.

## Aplicações & Microsserviços
- **FastAPI (Python 3.13+):** BFF / API Gateway com Pydantic v2 e HTTPX.
- **Golang (1.23+):** Microsserviços internos de altíssima performance utilizando gRPC e RabbitMQ client.

---

# Ecossistema de Microsserviços

Cada microsserviço possui repositório próprio e ciclo de vida independente:

| Serviço | Stack / Protocolo | Responsabilidades Principais | Armazenamento / Broker |
|---|---|---|---|
| **fastapi-bff** | Python / FastAPI / HTTP | API Gateway, validação Pydantic, rate limit, cache, roteamento | Redis |
| **auth-service** | Golang / gRPC (:50051) | Autenticação, geração e validação de JWT, hashing de credenciais | PostgreSQL |
| **user-service** | Golang / gRPC (:50052) | Gestão de perfis, endereços, preferências e dados de usuários | PostgreSQL |
| **event-service** | Golang / gRPC (:50053) | Catálogo de eventos, detalhes de apresentações e busca full-text | MongoDB / Elasticsearch |
| **orders-service** | Golang / gRPC (:50054) + AMQP | Reserva atômica de assentos, ciclo de vida do pedido, row locking | PostgreSQL |
| **payment-service** | Golang / gRPC (:50055) + AMQP | Processamento de transações, integração com gateways de pagamento | PostgreSQL |
| **notification-service** | Golang / AMQP | Envio assíncrono de notificações (Email, SMS, Push), auditoria | MongoDB |
| **search-sync-worker** | Golang / AMQP | Sincronização e indexação de dados do PostgreSQL/MongoDB no Elasticsearch | Elasticsearch |

---

# Fluxos da Requisição

## 1. Fluxo Síncrono (Leituras e Autenticação)
```text
Cliente ──► Traefik ──► FastAPI BFF ──► [Redis Cache?]
                             │ (Miss)
                             ▼ (gRPC)
                Auth / User / Event Service (Go)
                             ▼
                 PostgreSQL / MongoDB / Elasticsearch
```

## 2. Fluxo Assíncrono (Compra de Ingressos de Alta Concorrência)
```text
Cliente ──► Traefik ──► FastAPI BFF ──► RabbitMQ ("order.created") ──► 202 Accepted (Imediato)
                                              │
                                              ▼ Consome
                                       Orders Service (Go)
                                              │ SELECT ... FOR UPDATE SKIP LOCKED
                                              ├─► Sucesso ──► RabbitMQ ("payment.process")
                                              │                     │
                                              │                     ▼ Consome
                                              │              Payment Service (Go)
                                              │                     │
                                              │                     ├─► Confirma Pedido
                                              │                     └─► RabbitMQ ("notification.send")
                                              │                               │
                                              │                               ▼ Consome
                                              │                     Notification Service (Go)
                                              └─► Conflito/Esgotado ──► Notifica Falha
```

---

# Pipeline de Observabilidade e Padrões de Telemetria

Toda a telemetria gerada nos serviços segue os padrões rigorosos de observabilidade:

1. **W3C Trace Context:** Propagação contínua do header `traceparent` (e `baggage`) através de HTTP, gRPC (metadados de contexto) e RabbitMQ (headers da mensagem AMQP).
2. **Correlation ID:** Header `X-Correlation-ID` propagado em todas as camadas e injetado em:
   - Respostas HTTP públicas (`X-Correlation-ID`).
   - Logs estruturados em formato JSON (`correlation_id`).
   - Mensagens de erro para rastreabilidade de suporte.
3. **Structured Logs:** Logs estruturados contendo obrigatoriamente `trace_id`, `span_id`, `correlation_id` e `service.name`.
4. **Métricas RED:** *Rate* (Taxa de requisições/mensagens), *Errors* (Taxa de erros) e *Duration* (Histograma de latência p50/p95/p99) para gRPC, HTTP e RabbitMQ.

---

# Estrutura do Repositório Central

```text
monitor_lab/
├── terraform/                          # Infraestrutura como Código (IaC)
│   ├── providers.tf                    # Provedores Kubernetes e Helm
│   ├── variables.tf                    # Variáveis parametrizáveis
│   ├── main.tf                         # Namespaces, Traefik v3, Portainer, LGTM, Alloy e Flux
│   └── outputs.tf                      # URLs de acesso direto aos dashboards
│
├── k8s/                                # Manifests Kubernetes (GitOps)
│   ├── ingress/                        # Traefik IngressRoutes e Middlewares
│   ├── observability/                  # ConfigMaps e StatefulSets (Mimir, Loki, Tempo, Alloy)
│   ├── apps/fastapi-bff/               # Deployments de microsserviços com OTel
│   └── gitops/flux-sync.yaml           # Sincronização automática com Flux CD
│
├── secrets/                            # Segredos criptografados com SOPS
│   ├── .sops.yaml                      # Regras de encriptação
│   ├── README.md                       # Guia rápido de uso do SOPS
│   └── templates/                      # Templates de segredos anonimizados
│
├── scripts/                            # Scripts de automação do servidor
│   ├── mount-hdd.sh                    # Formatação e montagem do HDD de 1TB
│   ├── bootstrap-tools.sh              # Instalação de kubectl, helm, terraform, age, sops
│   ├── install-k3s.sh                  # Instalação e configuração do K3s
│   └── sops-keygen.sh                  # Geração de par de chaves age
│
├── .github/workflows/                  # CI/CD no GitHub Actions
│   ├── ci-microservice.yml             # Build e push para Docker Hub
│   └── terraform-validate.yml          # Lint e validação contínua do Terraform
│
└── docs/                               # Documentação centralizada
    ├── README.md                       # Índice geral da plataforma
    ├── data-flow-and-architecture.md   # Fluxos síncronos, assíncronos e telemetria
    ├── microservice-integration-guide.md # Guia de integração OTel SDK, Traces e Deploy
    ├── local-development-and-testing.md  # Port-forwarding, curl e depuração
    ├── sops-secrets-management.md      # Criptografia de segredos com SOPS e age
    ├── k3s-migration-guide.md          # Guia operacional de bootstrap K3s
    ├── standards/                      # Padrões de engenharia e telemetria
    └── infrastructure/                 # Documentação detalhada dos componentes de infra
```


---

# Roadmap de Implementação

## Fase 1 — Fundação de Infraestrutura & Observabilidade
- [x] Docker Compose e Redes Isoladas
- [x] Traefik v3 Reverse Proxy & Roteamento via Tailscale
- [x] Stack Grafana (Grafana, Mimir, Loki, Tempo, Alloy)
- [x] Correlação Cruzada de Telemetria (Logs ↔ Traces ↔ Métricas)
- [x] Monitoramento de Recursos da Máquina Host (Node Exporter) e Containers (cAdvisor) via Alloy

## Fase 2 — Message Broker & Persistência Poliglota
- [ ] Subida do cluster RabbitMQ (com UI de Management)
- [ ] Instâncias do PostgreSQL, MongoDB e Elasticsearch
- [ ] Configuração de índices e migrações iniciais

## Fase 3 — API Gateway (FastAPI BFF) & Autenticação
- [ ] `fastapi-bff` com validação Pydantic, rate limit e cache Redis
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