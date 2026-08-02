# Arquitetura e Diagramas da Infraestrutura

> **Documento:** Guia Visual da Infraestrutura  
> **Objetivo:** Explicar a arquitetura completa do **Observability Lab** utilizando diagramas em Mermaid e fluxogramas detalhados.

---

## 1. Visão Geral da Arquitetura da Infraestrutura

Este diagrama ilustra todos os componentes da plataforma de observabilidade, suas redes, portas expostas e como eles se relacionam.

```mermaid
flowchart TD
    subgraph Cliente["Cliente / Desenvolvedor"]
        User["Navegador / HTTP Client"]
    end

    subgraph ResoluçaoDNS["Camada de Resolução DNS"]
        SysResolved["systemd-resolved (127.0.0.53:53)"]
        AdGuard["AdGuard Home (192.168.0.7:53)"]
        DoH["Upstream DoH (Cloudflare / Quad9)"]
    end

    subgraph Gateway["Gateway & Proxy Reverso"]
        Traefik["Traefik v3 (Portas 80 / 8080)"]
    end

    subgraph Observabilidade["Plataforma de Observabilidade (Docker Network)"]
        Grafana["Grafana (Visualização)"]
        Prometheus["Prometheus (Métricas)"]
        Loki["Loki (Logs)"]
        Tempo["Tempo (Traces Distribuídos)"]
        Alloy["Grafana Alloy (Coletor Unificado)"]
        Promtail["Promtail (Shipper de Logs)"]
    end

    subgraph Apps["Futuros Microsserviços (APIs)"]
        UsersAPI["users-api (FastAPI)"]
        OrdersAPI["orders-api (FastAPI)"]
    end

    %% Conexões DNS
    User -->|1. Consulta monitor.lab| SysResolved
    SysResolved -->|Upstream local| AdGuard
    AdGuard -->|Domínio Interno| Traefik
    AdGuard -->|Consulta Externa| DoH

    %% Conexões HTTP
    User -->|2. Requisição HTTP :80| Traefik
    Traefik -->|/grafana| Grafana
    Traefik -->|/prometheus| Prometheus
    Traefik -->|/loki| Loki
    Traefik -->|/tempo| Tempo
    Traefik -->|dns.monitor.lab| AdGuard
    Traefik -->|/api/v1/users| UsersAPI
    Traefik -->|/api/v1/orders| OrdersAPI

    %% Telemetria das APIs
    UsersAPI -->|Logs Stdout| Promtail
    UsersAPI -->|Logs Stdout| Alloy
    UsersAPI -->|OTLP Traces :4317| Tempo
    UsersAPI -->|Scrape /metrics| Prometheus

    %% Integração de Dados
    Promtail -->|Push Logs| Loki
    Alloy -->|Push Logs| Loki
    Grafana -->|Datasource| Prometheus
    Grafana -->|Datasource| Loki
    Grafana -->|Datasource| Tempo
```

---

## 2. Fluxo da Camada de DNS e Coexistência

Diagrama detalhado mostrando como o `systemd-resolved` e o `AdGuard Home` coexistem sem conflito na porta 53:

```mermaid
sequenceDiagram
    autonumber
    actor User as Desenvolvedor / App
    participant SR as systemd-resolved (127.0.0.53:53)
    participant AG as AdGuard Home (192.168.0.7:53)
    participant Upstream as Cloudflare / Quad9 (DoH)
    participant Traefik as Traefik Gateway (192.168.0.7:80)

    User->>SR: Consulta DNS ("monitor.lab")
    SR->>AG: Encaminha consulta para 192.168.0.7:53
    alt É domínio local (monitor.lab / *.monitor.lab)
        AG-->>SR: Responde IP Local: 192.168.0.7 (DNS Rewrite)
        SR-->>User: Retorna 192.168.0.7
        User->>Traefik: Conecta em http://monitor.lab/grafana
    else É domínio público (google.com)
        AG->>Upstream: Consulta via DNS-over-HTTPS (DoH Criptografado)
        Upstream-->>AG: Retorna IP Público
        AG-->>SR: Retorna IP Público
        SR-->>User: Retorna IP Público
    end
```

---

## 3. Fluxo de Roteamento do Proxy Reverso (Traefik v3)

Como o **Traefik** recebe as requisições na porta `80` (redirecionando para HTTPS `443` com terminação TLS) e encaminha internamente na rede Docker `observability-net`:

```mermaid
graph LR
    subgraph Entrada["Entrypoints Externa"]
        E80["HTTP :80 (web -> Redirect HTTPS)"]
        E443["HTTPS :443 (websecure - TLS Terminated)"]
        E8080["HTTP :8080 (traefik)"]
    end

    subgraph Routers["Routers (Regras de Entrada TLS)"]
        R_Grafana["Host: monitor.lab & Path: /grafana (TLS)"]
        R_Prom["Host: monitor.lab & Path: /prometheus (TLS)"]
        R_Loki["Host: monitor.lab & Path: /loki (TLS)"]
        R_Tempo["Host: monitor.lab & Path: /tempo (TLS)"]
        R_DNS["Host: dns.monitor.lab (TLS)"]
        R_Dash["Host: monitor.lab:8080 & Path: /dashboard"]
    end

    subgraph Containers["Containers Backend (Rede Interna)"]
        C_Grafana["grafana:3000"]
        C_Prom["prometheus:9090"]
        C_Loki["loki:3100"]
        C_Tempo["tempo:3200"]
        C_DNS["adguard:3000"]
        C_Dash["api@internal"]
    end

    E80 -->|Redirect 301| E443
    E443 --> R_Grafana --> C_Grafana
    E443 --> R_Prom --> C_Prom
    E443 --> R_Loki --> C_Loki
    E443 --> R_Tempo --> C_Tempo
    E443 --> R_DNS --> C_DNS
    E8080 --> R_Dash --> C_Dash
```

---

## 4. Pipeline dos 3 Pilares da Observabilidade

Como os **Logs**, **Métricas** e **Traces** fluem das aplicações até o Grafana:

```mermaid
flowchart LR
    subgraph Aplicaçao["Aplicação (FastAPI / Microservice)"]
        AppLog["Logs JSON (Stdout/Stderr)"]
        AppMetric["Endpoint /metrics (PromQL)"]
        AppTrace["OpenTelemetry Tracer (OTLP)"]
    end

    subgraph Coleta["Coleta & Ingestão"]
        Alloy["Grafana Alloy / Promtail"]
        Prometheus["Prometheus (Scraper)"]
        Tempo["Grafana Tempo (OTLP Engine)"]
    end

    subgraph Armazenamento["Armazenamento"]
        LokiDB[("Loki (TSDB Logs)")]
        PromDB[("Prometheus TSDB")]
        TempoDB[("Tempo Blocks Storage")]
    end

    subgraph Painel["Visualização"]
        Grafana["Grafana Unified Dashboard"]
    end

    %% Pipeline Logs
    AppLog -->|Docker Logs Driver| Alloy -->|Loki Push API| LokiDB -->|LogQL| Grafana

    %% Pipeline Métricas
    AppMetric <---|Scrape Intervinar 15s| Prometheus -->|Time-Series| PromDB -->|PromQL| Grafana

    %% Pipeline Traces
    AppTrace -->|gRPC :4317 / HTTP :4318| Tempo -->|Trace Blocks| TempoDB -->|TraceQL| Grafana
```

---

## 5. Correlação Cruzada no Grafana (Cross-Telemetry Correlation)

Como as três pilares da observabilidade se conectam dentro da interface do Grafana:

```mermaid
stateDiagram-v2
    [*] --> LogQuery: Busca Log no Loki (LogQL)
    LogQuery --> TraceLink: Encontra "trace_id" no JSON Log
    TraceLink --> TempoView: Clica no link e abre o Trace no Tempo
    TempoView --> SpanDetails: Examina o Span e a Latência de cada microsserviço
    TempoView --> MetricCorrelation: Visualiza Métricas (Taxa de Erros / Latência via Prometheus)
    MetricCorrelation --> [*]
```

---

## 6. Propagação de Contexto (W3C Trace Context & Correlation ID)

Como uma requisição distribuída mantém o rastreamento entre múltiplos microsserviços:

```mermaid
sequenceDiagram
    autonumber
    actor Client as Cliente / Frontend
    participant Traefik as Traefik Gateway
    participant Users as Users API (FastAPI)
    participant Orders as Orders API (FastAPI)
    participant OTEL as OpenTelemetry / Tempo

    Client->>Traefik: GET /api/v1/users (Header: X-Correlation-ID: 550e8400...)
    Note over Traefik: Preserva X-Correlation-ID e gera/preserva W3C traceparent
    Traefik->>Users: Forward Request<br/>(traceparent: 00-4bf92f...-00f067...-01)<br/>(X-Correlation-ID: 550e8400...)
    
    Note over Users: Inicia Child Span no OTel<br/>Log JSON {trace_id, span_id, correlation_id}
    
    Users->>Orders: HTTP GET /api/v1/orders<br/>(traceparent: 00-4bf92f...-11a088...-01)<br/>(X-Correlation-ID: 550e8400...)
    
    Note over Orders: Inicia Sub-Child Span<br/>Log JSON {trace_id, span_id, correlation_id}
    
    Orders-->>Users: 200 OK (X-Correlation-ID: 550e8400...)
    Users-->>Traefik: 200 OK (X-Correlation-ID: 550e8400..., X-Trace-ID: 4bf92f...)
    Traefik-->>Client: 200 OK (X-Correlation-ID: 550e8400..., X-Trace-ID: 4bf92f...)
    
    Users->>OTEL: Export Spans via OTLP :4317
    Orders->>OTEL: Export Spans via OTLP :4317
```

---

## 7. Mapeamento de Portas e Serviços

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                              PORTAS HOST                                │
├───────────┬───────────────────────────────┬─────────────────────────────┤
│ Porta     │ Serviço                       │ Acesso                      │
├───────────┼───────────────────────────────┼─────────────────────────────┤
│ :53       │ AdGuard Home (DNS TCP/UDP)    │ 192.168.0.7:53 (Rede LAN)   │
│ :80       │ Traefik Gateway               │ http://monitor.lab/         │
│ :3053     │ AdGuard Home Setup Direct     │ http://localhost:3053/      │
│ :8080     │ Traefik API & Dashboard       │ http://monitor.lab:8080/    │
└───────────┴───────────────────────────────┴─────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                         REDES INTERNAS DOCKER                           │
├───────────┬───────────────────────────────┬─────────────────────────────┤
│ Container │ Rede                          │ Porta Interna               │
├───────────┼───────────────────────────────┼─────────────────────────────┤
│ traefik   │ observability-net             │ 80 / 8080                   │
│ grafana   │ observability-net             │ 3000                        │
│ prometheus│ observability-net             │ 9090                        │
│ loki      │ observability-net             │ 3100                        │
│ tempo     │ observability-net             │ 3200 / 4317 (gRPC) / 4318   │
│ alloy     │ observability-net             │ 12345                       │
│ promtail  │ observability-net             │ 9080                        │
│ adguard   │ observability-net             │ 3000 (web) / 53 (dns)       │
└───────────┴───────────────────────────────┴─────────────────────────────┘
```
