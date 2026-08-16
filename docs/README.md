# 📚 Documentação — Observability Lab: High-Concurrency Ticket Booking System

> **Índice Central de Documentação do Ecossistema**  
> Guia completo de arquitetura, padrões, infraestrutura, modelagem de banco de dados, frontend e microsserviços para o laboratório de observabilidade e mensageria de alta concorrência.

---

## 🏛️ 1. Arquitetura e Diagramas

| Documento | Descrição |
|---|---|
| [Ticket Booking System Architecture](architecture/ticket_system_architecture.md) | Arquitetura geral, fluxos síncronos/assíncronos, concorrência, persistência poliglota e 7 diagramas Mermaid |
| [Diagramas da Infraestrutura](architecture/infrastructure-diagrams.md) | Topologia de rede, coexistência de DNS, roteamento Traefik TLS e pipeline de telemetria OTel |

---

## 🗄️ 2. Banco de Dados e Modelagem (ER)

| Documento | Descrição |
|---|---|
| [Diagramas de Banco de Dados e Relacionamentos](database/database-diagrams.md) | Modelagem ER completa de estádio por setores (PostgreSQL), schemas MongoDB, mapeamento Elasticsearch, sincronização cross-database e máquinas de estados |

---

## 🌐 3. Front-End (`ticket-web`)

| Documento | Descrição |
|---|---|
| [Rotas, Telas e Funcionalidades](frontend/routes-and-features.md) | Mapeamento completo de rotas Next.js 15, wireframes do mapa de setores do estádio, checkout com timer regressivo de 10 min, QR Code de ingresso e integração OTel RUM |
| [Diretrizes & Skills de Front-End](standards/frontend-skills.md) | Padrões de código, Next.js 15 App Router, TanStack Query, Zustand, injeção de Trace Context no navegador e Core Web Vitals |

---

## 📋 4. Padrões de Engenharia e Observabilidade

| Documento | Descrição |
|---|---|
| [Padrão de Observabilidade](standards/observability-standard.md) | Os 3 pilares (Métricas Mimir, Logs Loki, Traces Tempo), OpenTelemetry SDK, correlação cruzada e alertas |
| [Guia de Boas Práticas](standards/best-practices.md) | Docker, Concorrência, Transações ACID, Segurança, JWT, Testes e Operational Runbook |
| [Padrão de Desenvolvimento de Microsserviços](standards/api-development-standards.md) | Padrões Clean Architecture para Python (FastAPI BFF) e Golang (gRPC), contratos e validações |
| [Padrão de Tracing Distribuído](standards/distributed-tracing-standard.md) | W3C Trace Context (`traceparent`), Correlation ID (`X-Correlation-ID`) e propagação em HTTP, gRPC e AMQP |
| [Padrão de DNS Local](standards/local-dns-standard.md) | AdGuard Home, resolução `*.monitor.lab`, certificados TLS locais e integração com `systemd-resolved` |

---

## 🏗️ 5. Componentes de Infraestrutura

| Documento | Componente | Descrição |
|---|---|---|
| [Traefik v3](infrastructure/traefik.md) | Reverse Proxy & API Gateway | Roteamento HTTP/HTTPS, terminação TLS local, Service Discovery e middlewares |
| [Grafana](infrastructure/grafana.md) | Visualização | Provisionamento automático de datasources (Mimir, Loki, Tempo), dashboards RED e correlação cruzada |
| [Grafana Mimir](infrastructure/mimir.md) | Métricas (TSDB) | Ingestão OTLP e Prometheus Remote Write, PromQL de alta performance e retenção local |
| [Grafana Loki](infrastructure/loki.md) | Logs Centralizados | Armazenamento estruturado com suporte a OTLP/LogQL, derived fields e links diretos para traces |
| [Grafana Tempo](infrastructure/tempo.md) | Tracing Distribuído | Ingestão OTLP gRPC (:4317) / HTTP (:4318), TraceQL e Metrics Generator integrado ao Mimir |
| [Grafana Alloy](infrastructure/alloy.md) | Coletor de Telemetria | Descoberta dinâmica de containers Docker, coleta de logs stdout e scraping de métricas de infraestrutura |

---

## 🚀 6. Ecossistema de Microsserviços (8 Serviços)

| Documento | Serviço | Stack / Protocolo | Responsabilidades Principais |
|---|---|---|---|
| [FastAPI BFF](microservices/fastapi-bff.md) | `fastapi-bff` | Python 3.13+ / FastAPI / HTTP | API Gateway, validação Pydantic v2, rate limit, cache Redis, gRPC client e publish assíncrono |
| [Auth Service](microservices/auth-service.md) | `auth-service` | Golang / gRPC (:50051) | Autenticação, emissão e validação de JWT, hash de credenciais (bcrypt) e PostgreSQL |
| [User Service](microservices/user-service.md) | `user-service` | Golang / gRPC (:50052) | Gestão de perfis de usuário, endereços e preferências no PostgreSQL |
| [Event Service](microservices/event-service.md) | `event-service` | Golang / gRPC (:50053) | Catálogo de eventos, apresentações, integração MongoDB e busca full-text no Elasticsearch |
| [Orders Service](microservices/orders-service.md) | `orders-service` | Golang / gRPC (:50054) + AMQP | Reserva atômica de assentos (`FOR UPDATE SKIP LOCKED`), expiração de reserva e PostgreSQL |
| [Payment Service](microservices/payment-service.md) | `payment-service` | Golang / gRPC (:50055) + AMQP | Processamento de transações, integração com gateways de pagamento e idempotência |
| [Notification Service](microservices/notification-service.md) | `notification-service` | Golang / AMQP | Envio assíncrono multicanal (Email, SMS, Push) e logs de auditoria no MongoDB |
| [Search Sync Worker](microservices/search-sync-worker.md) | `search-sync-worker` | Golang / AMQP | Sincronização em tempo real de eventos e assentos do RabbitMQ para o Elasticsearch |

---

## 🗺️ Estrutura Organizada de Pastas

```text
docs/
├── README.md                            ← Índice Geral
│
├── architecture/                        ← Arquitetura Geral e Topologia
│   ├── ticket_system_architecture.md
│   └── infrastructure-diagrams.md
│
├── database/                            ← Modelagem e Diagramas ER
│   └── database-diagrams.md
│
├── frontend/                            ← Especificações do Front-End (ticket-web)
│   └── routes-and-features.md
│
├── standards/                           ← Padrões de Engenharia e Telemetria
│   ├── frontend-skills.md
│   ├── observability-standard.md
│   ├── best-practices.md
│   ├── api-development-standards.md
│   ├── distributed-tracing-standard.md
│   └── local-dns-standard.md
│
├── infrastructure/                      ← Documentação dos Componentes de Infra
│   ├── traefik.md
│   ├── grafana.md
│   ├── mimir.md
│   ├── loki.md
│   ├── tempo.md
│   └── alloy.md
│
└── microservices/                       ← Documentação dos 8 Microsserviços
    ├── fastapi-bff.md
    ├── auth-service.md
    ├── user-service.md
    ├── event-service.md
    ├── orders-service.md
    ├── payment-service.md
    ├── notification-service.md
    └── search-sync-worker.md
```
