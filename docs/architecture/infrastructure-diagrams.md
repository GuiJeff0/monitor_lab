# Arquitetura e Diagramas da Infraestrutura — Ticket Booking Lab

> **Documento:** Guia Visual da Infraestrutura e Ecossistema  
> **Objetivo:** Mapear todos os fluxos de rede, DNS, telemetria, roteamento e mensageria utilizando diagramas Mermaid.

---

## 1. Visão Geral da Topologia de Rede e Infraestrutura

```mermaid
flowchart TD
    subgraph Clients["Clientes & Desenvolvedores"]
        Browser["Navegador / App Mobile / k6 Test Client"]
    end

    subgraph DNSLayer["Camada de Resolução DNS"]
        SysResolved["systemd-resolved (127.0.0.53:53)"]
        AdGuard["AdGuard Home (192.168.0.7:53)"]
        DoH["Upstream DoH (Cloudflare / Quad9)"]
    end

    subgraph EdgeLayer["Ingress & Gateway"]
        Traefik["Traefik v3 Proxy (:80 -> :443 TLS, :8080 Dashboard)"]
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

    %% Conexões DNS & HTTP
    Browser --> SysResolved --> AdGuard --> Traefik
    AdGuard --> DoH
    Browser -->|HTTPS| Traefik
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

## 2. Fluxo da Camada de DNS (Coexistência na Porta 53)

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Desenvolvedor / App
    participant SR as systemd-resolved (127.0.0.53:53)
    participant AG as AdGuard Home (192.168.0.7:53)
    participant Upstream as Cloudflare / Quad9 (DoH)
    participant Traefik as Traefik Gateway (192.168.0.7:443)

    Dev->>SR: Consulta DNS ("monitor.lab")
    SR->>AG: Encaminha consulta para 192.168.0.7:53
    alt É domínio do laboratório (*.monitor.lab)
        AG-->>SR: Resposta Local: 192.168.0.7 (DNS Rewrite)
        SR-->>Dev: Retorna 192.168.0.7
        Dev->>Traefik: Conecta via HTTPS com certificado mkcert
    else É domínio público (ex: github.com)
        AG->>Upstream: Consulta via DNS-over-HTTPS (Criptografado)
        Upstream-->>AG: Resposta IP Público
        AG-->>SR: Retorna IP Público
        SR-->>Dev: Retorna IP Público
    end
```

---

## 3. Roteamento do Traefik v3 (TLS & Middlewares)

```mermaid
graph LR
    subgraph Entrada["Entrypoints"]
        E80["HTTP :80 (web -> Redirect 301)"]
        E443["HTTPS :443 (websecure - TLS Terminated)"]
        E8080["HTTP :8080 (traefik dashboard)"]
    end

    subgraph Routers["Routers TLS"]
        R_API["Host: monitor.lab & PathPrefix: /api"]
        R_Grafana["Host: monitor.lab & PathPrefix: /grafana"]
        R_Mimir["Host: monitor.lab & PathPrefix: /mimir"]
        R_Loki["Host: monitor.lab & PathPrefix: /loki"]
        R_Tempo["Host: monitor.lab & PathPrefix: /tempo"]
        R_DNS["Host: dns.monitor.lab"]
    end

    subgraph Services["Backends na Rede observability-net"]
        C_BFF["fastapi-bff:8000"]
        C_Grafana["grafana:3000"]
        C_Mimir["mimir:8080"]
        C_Loki["loki:3100"]
        C_Tempo["tempo:3200"]
        C_AdGuard["adguard:3000"]
    end

    E80 -->|Redirect| E443
    E443 --> R_API --> C_BFF
    E443 --> R_Grafana --> C_Grafana
    E443 --> R_Mimir --> C_Mimir
    E443 --> R_Loki --> C_Loki
    E443 --> R_Tempo --> C_Tempo
    E443 --> R_DNS --> C_AdGuard
```

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
