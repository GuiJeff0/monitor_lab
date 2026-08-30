# Arquitetura e Diagramas da Infraestrutura — Ticket Booking Lab

> **Documento:** Guia Visual da Infraestrutura e Ecossistema  
> **Objetivo:** Mapear todos os fluxos de rede, DNS, telemetria, roteamento e mensageria utilizando diagramas Mermaid.

---

## 1. Visão Geral da Topologia de Rede e Infraestrutura

```mermaid
flowchart TD
    subgraph Clients["Clientes & Desenvolvedores (Rede Tailscale)"]
        Browser["Navegador / App Mobile / k6 Test Client"]
    end

    subgraph VPNLayer["Rede Mesh Segura"]
        Tailscale["Tailscale VPN (WireGuard E2E Encryption)
        Host: <node-name>.<tailnet>.ts.net (100.x.y.z)"]
    end

    subgraph EdgeLayer["Ingress & Gateway"]
        Traefik["Traefik v3 Proxy (:80 HTTP / :443 HTTPS / :8080 Dashboard)"]
    end

    subgraph BFFLayer["Camada BFF"]
        BFF["FastAPI BFF (API Gateway)"]
        RedisCache[("Redis Cache & Limits")]
    end

    subgraph SyncServices["Microsserviços Síncronos (Golang / gRPC)"]
        Auth["Auth Service (:50051)"]
        User["User Service (:50052)"]
        Event["Event Service (:50053)"]
    end

    subgraph AsyncBroker["Message Broker"]
        RabbitMQ[["RabbitMQ (AMQP 5672 / UI 15672)"]]
    end

    subgraph AsyncServices["Workers & Serviços Assíncronos (Golang)"]
        Orders["Orders Service (:50054 + AMQP)"]
        Payment["Payment Service (:50055 + AMQP)"]
        Notification["Notification Service (AMQP)"]
        SyncWorker["Search Sync Worker (AMQP)"]
    end

    subgraph PolyglotDB["Persistência Poliglota"]
        Postgres[("PostgreSQL 16")]
        Mongo[("MongoDB 7")]
        Elastic[("Elasticsearch 8")]
    end

    subgraph ObservabilityStack["Plataforma de Observabilidade"]
        Mimir[("Grafana Mimir (Metrics)")]
        Loki[("Grafana Loki (Logs)")]
        Tempo[("Grafana Tempo (Traces)")]
        Alloy["Grafana Alloy (Collector)"]
        Grafana["Grafana Unified Dashboards"]
    end

    %% Conexões de Rede
    Browser -->|WireGuard Tunnel| Tailscale --> Traefik
    Traefik -->|/api/v1/*| BFF
    Traefik -->|/grafana| Grafana
    Traefik -->|/mimir| Mimir
    Traefik -->|/loki| Loki
    Traefik -->|/tempo| Tempo

    %% BFF Connections
    BFF <--> RedisCache
    BFF -->|gRPC| Auth & User & Event
    BFF -->|order.created| RabbitMQ

    %% Broker Connections
    RabbitMQ --> Orders & Payment & Notification & SyncWorker

    %% Persistence Connections
    Auth & User & Orders & Payment --> Postgres
    Event & Notification --> Mongo
    Event & SyncWorker --> Elastic

    %% Observability OTLP
    BFF & Auth & User & Event & Orders & Payment & Notification & SyncWorker -.->|OTLP Metrics| Mimir
    BFF & Auth & User & Event & Orders & Payment & Notification & SyncWorker -.->|OTLP Logs| Loki
    BFF & Auth & User & Event & Orders & Payment & Notification & SyncWorker -.->|OTLP Traces| Tempo

    Alloy -.->|Docker Logs| Loki
    Alloy -.->|Scrape Metrics| Mimir
    Tempo -.->|Metrics Generator Remote Write| Mimir
    Grafana -.-> Mimir & Loki & Tempo
```

---

## 2. Fluxo de Acesso Remoto e Criptografia via Tailscale

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Desenvolvedor / Navegador
    participant TS as Tailscale MagicDNS / VPN (100.x.y.z)
    participant Traefik as Traefik Gateway (:80 / :8080)
    participant Grafana as Grafana Dashboard (:3000)

    Dev->>TS: Acessa "http://<node-name>.<tailnet>.ts.net/grafana"
    Note over Dev,TS: Túnel ponto a ponto criptografado (WireGuard)
    TS->>Traefik: Repassa requisição HTTP na porta 80
    Traefik->>Grafana: Roteia PathPrefix(`/grafana`) para porta 3000
    Grafana-->>Traefik: Resposta HTML / Dashboard
    Traefik-->>Dev: Retorna conteúdo através do túnel Tailscale
```

---

## 3. Roteamento do Traefik v3 (PathPrefix & Middlewares)

```mermaid
graph LR
    subgraph Entrada["Entrypoints"]
        E80["HTTP :80 (web)"]
        E443["HTTPS :443 (websecure)"]
        E8080["HTTP :8080 (traefik dashboard)"]
    end

    subgraph Routers["Routers PathPrefix"]
        R_API["PathPrefix: /api/v1"]
        R_Grafana["PathPrefix: /grafana"]
        R_Mimir["PathPrefix: /mimir"]
        R_Loki["PathPrefix: /loki"]
        R_Tempo["PathPrefix: /tempo"]
        R_Dash["PathPrefix: /dashboard"]
    end

    subgraph Services["Backends na Rede observability-net"]
        C_BFF["fastapi-bff:8000"]
        C_Grafana["grafana:3000"]
        C_Mimir["mimir:8080"]
        C_Loki["loki:3100"]
        C_Tempo["tempo:3200"]
        C_Traefik["traefik:internal"]
    end

    E80 --> R_API --> C_BFF
    E80 --> R_Grafana --> C_Grafana
    E80 --> R_Mimir --> C_Mimir
    E80 --> R_Loki --> C_Loki
    E80 --> R_Tempo --> C_Tempo
    E443 -.-> R_Grafana
    E8080 --> R_Dash --> C_Traefik

---

## 4. Pipeline dos 3 Pilares da Observabilidade com OpenTelemetry

```mermaid
flowchart LR
    subgraph Services["Aplicações (Python BFF & Go Microservices)"]
        OTelLog["OTel Logger (JSON Stdout/OTLP)"]
        OTelMeter["OTel Meter (RED Metrics)"]
        OTelTracer["OTel Tracer (W3C Spans)"]
    end

    subgraph Ingestion["Camada de Ingestão e Armazenamento"]
        Alloy["Grafana Alloy (Container Logs & Scraping)"]
        MimirDB[("Grafana Mimir TSDB")]
        LokiDB[("Grafana Loki")]
        TempoDB[("Grafana Tempo")]
    end

    subgraph UI["Visualização"]
        Grafana["Grafana Unified Dashboard"]
    end

    OTelLog -->|Direct OTLP| LokiDB
    OTelLog -->|Docker Socket| Alloy -->|Push API| LokiDB
    OTelMeter -->|OTLP HTTP / Push| MimirDB
    OTelTracer -->|OTLP gRPC :4317| TempoDB
    TempoDB -->|Remote Write| MimirDB

    MimirDB -->|PromQL| Grafana
    LokiDB -->|LogQL| Grafana
    TempoDB -->|TraceQL| Grafana
```
