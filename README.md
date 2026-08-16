# Cloud-Native Observability Lab — Ticket Booking System

Production-grade, reusable observability infrastructure and high-concurrency ticket booking platform built with **Traefik v3**, the **Grafana Stack** (Mimir, Loki, Tempo, Alloy, Grafana), **RabbitMQ**, **PostgreSQL**, **MongoDB**, and **Elasticsearch**.

---

## 🏛️ Architecture Overview

```text
                                  Clientes (Web / Mobile)
                                             │
                                       HTTPS (TLS)
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

## 🛠️ Stack Components & Versions

| Component | Version | Role | Host Route / Port | Internal Access / Healthcheck |
|---|---|---|---|---|
| **Traefik** | `v3.7` | Reverse Proxy / API Gateway / Router | `http://monitor.lab:8080/dashboard/` (BasicAuth)<br>`https://monitor.lab/` | `traefik:8080` (`traefik healthcheck`) |
| **Grafana** | `13.1.1` | Unified Visualization & Dashboards | `https://monitor.lab/grafana` | `grafana:3000` (`curl http://localhost:3000/api/health`) |
| **Mimir** | `2.15.0` | Scalable Time-Series Metrics TSDB | `https://monitor.lab/mimir` | `mimir:8080` (`/bin/mimir -version`) |
| **Loki** | `3.7.4` | Structured Log Aggregator | `https://monitor.lab/loki` | `loki:3100` (`/usr/bin/loki --verify-config`) |
| **Grafana Alloy** | `v1.7.1` | Unified Telemetry Collector (Docker Logs) | Internal | `alloy:12345` (`/bin/alloy --version`) |
| **Tempo** | `2.6.1` | Distributed Tracing Backend | `https://monitor.lab/tempo` | `tempo:3200`<br>`tempo:4317` (gRPC OTLP)<br>`tempo:4318` (HTTP OTLP) |
| **AdGuard Home** | `v0.107.57` | Local DNS Server (Encrypted Upstream & DNS Rewrites) | `https://dns.monitor.lab/`<br>`192.168.0.7:53` | `adguard:3000` |

---

## 📚 Central de Documentação (`docs/`)

Toda a documentação técnica foi categorizada e organizada dentro da pasta [`docs/`](docs/README.md):

### 🏛️ [Arquitetura](docs/architecture/)
- [Ticket Booking System Architecture](docs/architecture/ticket_system_architecture.md)
- [Diagramas da Infraestrutura](docs/architecture/infrastructure-diagrams.md)

### 📋 [Padrões e Boas Práticas](docs/standards/)
- [Padrão de Observabilidade](docs/standards/observability-standard.md)
- [Guia de Boas Práticas](docs/standards/best-practices.md)
- [Padrão de Desenvolvimento de Microsserviços](docs/standards/api-development-standards.md)
- [Padrão de Tracing Distribuído & Correlation ID](docs/standards/distributed-tracing-standard.md)
- [Padrão de DNS Local](docs/standards/local-dns-standard.md)

### 🏗️ [Infraestrutura](docs/infrastructure/)
- [Traefik v3](docs/infrastructure/traefik.md)
- [Grafana](docs/infrastructure/grafana.md)
- [Grafana Mimir](docs/infrastructure/mimir.md)
- [Grafana Loki](docs/infrastructure/loki.md)
- [Grafana Tempo](docs/infrastructure/tempo.md)
- [Grafana Alloy](docs/infrastructure/alloy.md)

### 🚀 [Microsserviços](docs/microservices/)
- [FastAPI BFF](docs/microservices/fastapi-bff.md)
- [Auth Service](docs/microservices/auth-service.md)
- [User Service](docs/microservices/user-service.md)
- [Event Service](docs/microservices/event-service.md)
- [Orders Service](docs/microservices/orders-service.md)
- [Payment Service](docs/microservices/payment-service.md)
- [Notification Service](docs/microservices/notification-service.md)
- [Search Sync Worker](docs/microservices/search-sync-worker.md)

---

## 📁 Estrutura do Repositório

```text
observability-lab/
├── docker-compose.yml              # Orquestração de containers da infraestrutura
├── .env                            # Versões de imagens e variáveis de ambiente globais
├── AGENTS.md                       # Especificações e diretrizes mestres
├── README.md                       # Apresentação do repositório
│
├── traefik/                        # Configurações do Proxy Reverso
│   ├── traefik.yml
│   └── dynamic/
│
├── grafana/                        # Provisionamento e Dashboards
│   ├── provisioning/
│   │   └── datasources/
│   └── dashboards/
│
├── mimir/                          # Configurações do Grafana Mimir TSDB
│   └── mimir.yml
├── loki/                           # Configurações do Grafana Loki
│   └── config.yml
├── tempo/                          # Configurações do Grafana Tempo
│   └── tempo.yml
├── alloy/                          # Configurações do Grafana Alloy Collector
│   └── config.alloy
│
└── docs/                           # Documentação centralizada
    ├── README.md
    ├── architecture/
    ├── standards/
    ├── infrastructure/
    └── microservices/
```

---

## 🚀 Como Iniciar a Infraestrutura

```bash
# 1. Validar sintaxe do Docker Compose
docker compose config

# 2. Iniciar todos os serviços de infraestrutura
docker compose up -d

# 3. Verificar o status e health de todos os containers
docker compose ps
```
