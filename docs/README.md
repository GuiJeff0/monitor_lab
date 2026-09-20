# 📚 Central de Documentação — Observability Lab Platform

> **Plataforma de Infraestrutura, Observabilidade, Tracing Distribuído e DevOps**  
> Guia completo para gerenciar o cluster K3s, componentes da stack LGTM, Traefik, Portainer e integrar qualquer microsserviço com rastreamento distribuído (OpenTelemetry).

---

## 🏛️ 1. Arquitetura da Plataforma

| Documento | Descrição |
|---|---|
| [Fluxo de Dados e Arquitetura Completa](data-flow-and-architecture.md) | Fluxos síncronos, mensageria assíncrona, pipeline de telemetria OTel e topologia de storage (SSD vs HDD 1TB) |
| [Diagramas da Infraestrutura](architecture/infrastructure-diagrams.md) | Topologia de rede, coexistência de DNS, roteamento Traefik TLS e pipeline de telemetria OTel |

---

## 🚀 2. Guias de Integração & Operações DevOps

| Documento | Descrição |
|---|---|
| [Como Subir um Microsserviço Integrado com Tracing](microservice-integration-guide.md) | **Guia principal:** Instrumentação com OTel SDK (Go e Python), propagação W3C (`traceparent`), RabbitMQ e visualização no Tempo |
| [Como Testar Localmente](local-development-and-testing.md) | Port-forwarding com `kubectl`, testes com `curl`, logs e depuração de Pods no terminal |
| [Gestão de Secrets com SOPS e age](sops-secrets-management.md) | Criptografia assimétrica de segredos versionados com segurança no Git e decriptação via Flux CD |
| [Guia Operacional de Bootstrap K3s](k3s-migration-guide.md) | Inicialização do cluster, scripts de automação e provisionamento com Terraform |

---

## 📋 3. Padrões de Engenharia e Tracing Distribuído

| Documento | Descrição |
|---|---|
| [Padrão de Observabilidade](standards/observability-standard.md) | Os 3 pilares (Métricas Mimir, Logs Loki, Traces Tempo), OpenTelemetry SDK e alertas |
| [Padrão de Tracing Distribuído](standards/distributed-tracing-standard.md) | W3C Trace Context (`traceparent`), Correlation ID e propagação em HTTP, gRPC e AMQP |
| [Padrão de Desenvolvimento de APIs e Microsserviços](standards/api-development-standards.md) | Padrões de comunicação gRPC/HTTP e boas práticas para contratos de dados |
| [Guia de Boas Práticas e Resiliência](standards/best-practices.md) | Idempotência, Dead Letter Exchanges (DLX), Concorrência e Runbook Operacional |

---

## 🏗️ 4. Componentes da Infraestrutura

| Documento | Componente | Descrição |
|---|---|---|
| [Traefik v3](infrastructure/traefik.md) | Ingress Controller & API Gateway | Roteamento HTTP/HTTPS, terminação TLS, Service Discovery e middlewares |
| [Grafana](infrastructure/grafana.md) | Visualização | Provisionamento automático de datasources (Mimir, Loki, Tempo), dashboards e correlação |
| [Grafana Mimir](infrastructure/mimir.md) | Métricas (TSDB) | Ingestão OTLP e Prometheus Remote Write, PromQL de alta performance e retenção no HDD |
| [Grafana Loki](infrastructure/loki.md) | Logs Centralizados | Armazenamento estruturado com suporte a OTLP/LogQL e links diretos para traces |
| [Grafana Tempo](infrastructure/tempo.md) | Tracing Distribuído | Ingestão OTLP gRPC (:4317) / HTTP (:4318), TraceQL e Metrics Generator integrado |
| [Grafana Alloy](infrastructure/alloy.md) | Coletor de Telemetria | DaemonSet coletando logs de Pods K8s, métricas kubelet e recebendo dados OTLP |
