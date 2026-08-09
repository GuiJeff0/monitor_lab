# Cloud-Native Observability Infrastructure Lab

Production-grade, reusable observability infrastructure built with **Traefik v3** and the **Grafana Stack** (Mimir, Loki, Tempo, Grafana) with direct **OpenTelemetry SDK** integration and **Grafana Alloy** for infrastructure container logs.

This repository contains **only the shared infrastructure**. Future microservices (e.g., `users-api`, `orders-api`, `notification-api`) connect to this shared platform without modifying the underlying infrastructure.

---

## 🏛️ Architecture Overview

```text
                               ┌──────────────────────────────────┐
                               │           HTTP Client            │
                               └────────────────┬─────────────────┘
                                                │ :80 / :8080
                                                ▼
                               ┌──────────────────────────────────┐
                               │           Traefik v3             │
                               │   (Reverse Proxy & API Gateway)  │
                               └────────────────┬─────────────────┘
                                                │
          ┌──────────────────┬───────────────────┼───────────────────┬──────────────────┐
          │                  │                   │                   │                  │
     /grafana             /mimir               /loki               /tempo            /api/*
          │                  │                   │                   │              (future)
          ▼                  ▼                   ▼                   ▼                  │
   ┌─────────────┐    ┌─────────────┐     ┌─────────────┐     ┌─────────────┐           │
   │   Grafana   │    │    Mimir    │     │    Loki     │     │    Tempo    │           │
   │    :3000    │    │    :8080    │     │    :3100    │     │    :3200    │           │
   └──────┬──────┘    └──────▲──────┘     └──────▲──────┘     └──────▲──────┘           │
          │                  │                   │                   │                  │
          │ Datasources      │ OTLP / Push       │ OTLP / Push       │ OTLP             │
          │ (Auto-provision) │                   │                   │ (4317/4318)      │
          └──────────────────┼───────────────────┼───────────────────┼──────────────────┘
                             │                   │                   │
                             │            ┌──────┴──────┐            │
                             │            │    Alloy    │            │
                             │            │(Docker Logs)│            │
                             │            └─────────────┘            │
                             │                                       │
                      ┌──────┴───────────────────────────────────────┴─────────────────┐
                      │             Microservices (FastAPI + OpenTelemetry SDK)        │
                      │     Metrics -> Mimir  |  Logs -> Loki  |  Traces -> Tempo      │
                      └────────────────────────────────────────────────────────────────┘
```

---

## 🛠️ Stack Components & Versions

| Component | Version | Role | Host Route / Port | Internal Access / Healthcheck |
|---|---|---|---|---|
| **Traefik** | `v3.7` | Reverse Proxy / API Gateway / Router | `http://monitor.lab:8080/dashboard/` (Dashboard)<br>`https://monitor.lab/` | `traefik:8080` (`traefik healthcheck`) |
| **Grafana** | `13.1.1` | Unified Visualization & Dashboards | `https://monitor.lab/grafana` | `grafana:3000` (`curl http://localhost:3000/api/health`) |
| **Mimir** | `2.15.0` | Scalable Time-Series Metrics Database | `https://monitor.lab/mimir` | `mimir:8080` (`wget http://localhost:8080/ready`) |
| **Loki** | `3.7.4` | High-Performance Log Aggregator | `https://monitor.lab/loki` | `loki:3100` (`/usr/bin/loki --verify-config`) |
| **Grafana Alloy** | `v1.7.1` | Unified Telemetry Collector (Docker Logs) | Internal | `alloy:12345` |
| **Tempo** | `2.6.1` | Distributed Tracing Backend | `https://monitor.lab/tempo` | `tempo:3200`<br>`tempo:4317` (gRPC)<br>`tempo:4318` (HTTP) |
| **AdGuard Home** | `v0.107.57` | Local DNS Server (Encrypted Upstream & DNS Rewrites) | `https://dns.monitor.lab/`<br>`192.168.0.7:53` | `adguard:3000` |

---

## 📁 Directory Structure

```text
observability-lab/
├── docker-compose.yml              # Main orchestration specification
├── .env                            # Centralized environment variables
├── README.md                       # Comprehensive infrastructure documentation
├── Infrastructure Diagrams.md      # Full architecture & flow diagrams (Mermaid)
├── Local DNS Standard.md           # Local DNS architecture & setup guide
├── Distributed Tracing Standard.md # Distributed tracing & correlation rules
├── API Development Standards.md    # Microservices standards & guidelines
├── traefik/                        # Traefik configuration
│   ├── traefik.yml                 # Static Traefik config (entrypoints :80, :443, :8080)
│   ├── dynamic/                    # Dynamic rules, routers, and TLS options (tls.yml)
│   └── certificates/               # Wildcard TLS certs (*.monitor.lab) & rootCA.pem
│
├── grafana/                        # Grafana automated provisioning
│   ├── provisioning/
│   │   ├── dashboards/             # Auto-load dashboard providers
│   │   │   └── dashboards.yml
│   │   └── datasources/            # Auto-provision Mimir, Loki, Tempo
│   │       └── datasources.yml
│   └── dashboards/                 # Drop JSON dashboard definitions here
│
├── mimir/                          # Grafana Mimir configuration
│   └── mimir.yml                   # TSDB storage, monolithic single-process config
│
├── loki/                           # Loki configuration
│   └── config.yml                  # TSDB storage, schema v13, local filesystem
│
├── alloy/                          # Grafana Alloy configuration
│   └── config.alloy                # River syntax for Docker log discovery & Loki push
│
└── tempo/                          # Tempo configuration
    └── tempo.yml                   # OTLP receivers (gRPC/HTTP), WAL, metrics generator -> Mimir
```

---

## 🚀 Quick Start

### Prerequisites

- [Docker Engine](https://docs.docker.com/engine/install/) (v24.0+)
- [Docker Compose](https://docs.docker.com/compose/install/) (v2.20+)
- [mkcert](https://github.com/FiloSottile/mkcert) (for generating trusted local CA & TLS certificates)

### Launching the Infrastructure

1. Clone the repository and navigate to the directory:
   ```bash
   cd monitor_lab
   ```

2. Start the observability stack in detached mode:
   ```bash
   docker compose up -d
   ```

3. Verify container health status:
   ```bash
   docker compose ps
   ```

All 7 containers (`traefik`, `grafana`, `mimir`, `loki`, `alloy`, `tempo`, `adguard`) should show as `running` or `healthy`.

---

## 🌐 Accessing Services

| Service | Access URL | Protocol / Port | Credentials (Default) |
|---|---|---|---|
| **Traefik Dashboard** | [http://monitor.lab:8080/dashboard/](http://monitor.lab:8080/dashboard/) | HTTP / 8080 | None (Dev mode) |
| **Grafana** | [https://monitor.lab/grafana/](https://monitor.lab/grafana/) | HTTPS / 443 (auto-redirect) | User: `admin` / Password: `admin` |
| **Mimir Health** | [https://monitor.lab/mimir/ready](https://monitor.lab/mimir/ready) | HTTPS / 443 (auto-redirect) | None |
| **Loki Health** | [https://monitor.lab/loki/ready](https://monitor.lab/loki/ready) | HTTPS / 443 (auto-redirect) | None |
| **Tempo Health** | [https://monitor.lab/tempo/ready](https://monitor.lab/tempo/ready) | HTTPS / 443 (auto-redirect) | None |
| **AdGuard Home** | [https://dns.monitor.lab/](https://dns.monitor.lab/) | HTTPS / 443 (auto-redirect) | Setup Wizard / Admin |

---

## 🔌 Connecting Future Microservices

All application services (e.g., FastAPI, Node.js, Go) should attach to the shared Docker network (`observability-net`).

### 1. Network Configuration in Microservice `docker-compose.yml`

```yaml
networks:
  observability-net:
    external: true
    name: observability-net

services:
  users-api:
    image: users-api:latest
    networks:
      - observability-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.users-api.rule=PathPrefix(`/api/v1/users`)"
      - "traefik.http.routers.users-api.entrypoints=web"
      - "traefik.http.services.users-api.loadbalancer.server.port=8000"
    environment:
      - OTEL_SERVICE_NAME=users-api
      - OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://tempo:4317
      - OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=http://mimir:8080/otlp/v1/metrics
      - OTEL_EXPORTER_OTLP_LOGS_ENDPOINT=http://loki:3100/otlp/v1/logs
```

### 2. Telemetry Integration Points

- **Logs**: OpenTelemetry SDK exports logs directly to `loki:3100` via OTLP. In addition, `alloy` discovers container stdout/stderr logs and streams them to Loki.
- **Metrics**: OpenTelemetry SDK pushes metrics directly to `mimir:8080/otlp/v1/metrics` or via Prometheus Remote Write.
- **Traces**: OpenTelemetry SDK sends traces to `tempo:4317` (gRPC) or `tempo:4318` (HTTP).

---

## 🔍 Grafana Pre-Configured Telemetry Correlator

Grafana is provisioned with cross-telemetry correlation rules out of the box:

1. **Log → Trace Correlation**: Loki log lines containing `"traceID":"..."` automatically display a clickable link directly opening the trace in **Tempo**.
2. **Trace → Log Correlation**: Viewing a trace in Tempo provides a direct action button to view corresponding container logs in **Loki** filtered by service and timeframe.
3. **Trace → Metrics Correlation**: Service map node graph in Tempo uses **Mimir** metrics for span rate and latency calculations.

---

## 🧹 Maintenance & Cleanup

### Stop Services
```bash
docker compose down
```

### Stop Services & Remove Persistent Volumes (Data Reset)
```bash
docker compose down -v
```

---

## 📜 License

MIT License. Designed for reusable Cloud-Native microservice architecture labs.
