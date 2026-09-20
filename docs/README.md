# 📚 Documentação — Observability Lab: High-Concurrency Ticket Booking System

> **Índice Central de Documentação do Ecossistema**  
> Guia completo de arquitetura, padrões, infraestrutura, modelagem de banco de dados, frontend, microsserviços e operações DevOps para o laboratório de observabilidade e mensageria de alta concorrência.

---

## 🏛️ 1. Arquitetura e Diagramas

| Documento | Descrição |
|---|---|
| [Fluxo de Dados e Arquitetura Completa](data-flow-and-architecture.md) | Fluxos síncronos, assíncronos (RabbitMQ), pipeline de telemetria OTel e topologia de armazenamento |
| [Ticket Booking System Architecture](architecture/ticket_system_architecture.md) | Arquitetura geral, fluxos síncronos/assíncronos, concorrência, persistência poliglota e diagramas |
| [Diagramas da Infraestrutura](architecture/infrastructure-diagrams.md) | Topologia de rede, coexistência de DNS, roteamento Traefik TLS e pipeline de telemetria OTel |

---

## 🚀 2. Guias Operacionais & DevOps (K3s, CI/CD e GitOps)

| Documento | Descrição |
|---|---|
| [Como Testar Localmente](local-development-and-testing.md) | Port-forwarding, curl, logs e depuração de Pods no terminal |
| [Como Subir um Microsserviço Integrado](microservice-integration-guide.md) | Instrumentação com OTel SDK (Go e Python), manifestos K8s e Docker Hub |
| [Gestão de Secrets com SOPS e age](sops-secrets-management.md) | Criptografia assimétrica de segredos versionados com segurança no Git |
| [Guia Operacional de Bootstrap K3s](k3s-migration-guide.md) | Inicialização do cluster, scripts de automação e provisionamento Terraform |

---

## 🗄️ 3. Banco de Dados e Modelagem (ER)

| Documento | Descrição |
|---|---|
| [Diagramas de Banco de Dados e Relacionamentos](database/database-diagrams.md) | Modelagem ER de estádio por setores (PostgreSQL), schemas MongoDB e mapeamento Elasticsearch |

---

## 🌐 4. Front-End (`ticket-web`)

| Documento | Descrição |
|---|---|
| [Rotas, Telas e Funcionalidades](frontend/routes-and-features.md) | Mapeamento de rotas Next.js 15, wireframes do mapa de setores, checkout com timer e QR Code |
| [Diretrizes & Skills de Front-End](standards/frontend-skills.md) | Padrões de código, Next.js 15 App Router, TanStack Query, Zustand e OTel RUM |

---

## 📋 5. Padrões de Engenharia e Observabilidade

| Documento | Descrição |
|---|---|
| [Padrão de Observabilidade](standards/observability-standard.md) | Os 3 pilares (Métricas Mimir, Logs Loki, Traces Tempo), OpenTelemetry SDK e alertas |
| [Guia de Boas Práticas](standards/best-practices.md) | Concorrência, Transações ACID, Segurança, JWT, Testes e Runbook Operacional |
| [Padrão de Desenvolvimento de Microsserviços](standards/api-development-standards.md) | Clean Architecture para Python (FastAPI BFF) e Golang (gRPC), contratos e validações |
| [Padrão de Tracing Distribuído](standards/distributed-tracing-standard.md) | W3C Trace Context (`traceparent`), Correlation ID e propagação em HTTP, gRPC e AMQP |

---

## 🏗️ 6. Componentes de Infraestrutura

| Documento | Componente | Descrição |
|---|---|---|
| [Traefik v3](infrastructure/traefik.md) | Ingress Controller & API Gateway | Roteamento HTTP/HTTPS, terminação TLS local, Service Discovery e middlewares |
| [Grafana](infrastructure/grafana.md) | Visualização | Provisionamento automático de datasources (Mimir, Loki, Tempo), dashboards e correlação |
| [Grafana Mimir](infrastructure/mimir.md) | Métricas (TSDB) | Ingestão OTLP e Prometheus Remote Write, PromQL de alta performance e retenção no HDD |
| [Grafana Loki](infrastructure/loki.md) | Logs Centralizados | Armazenamento estruturado com suporte a OTLP/LogQL e links diretos para traces |
| [Grafana Tempo](infrastructure/tempo.md) | Tracing Distribuído | Ingestão OTLP gRPC (:4317) / HTTP (:4318), TraceQL e Metrics Generator integrado |
| [Grafana Alloy](infrastructure/alloy.md) | Coletor de Telemetria | DaemonSet coletando logs de Pods K8s, métricas kubelet e recebendo dados OTLP |

---

## 🚀 7. Ecossistema de Microsserviços (8 Serviços)

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
