# Cloud-Native Observability Infrastructure Lab

Production-grade, reusable observability infrastructure built with **Traefik v3** and the **Grafana LGTM Stack** (Loki, Grafana, Tempo, Prometheus) supplemented with **Grafana Alloy** and **Promtail**.

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
    /grafana           /prometheus            /loki               /tempo            /api/*
         │                  │                   │                   │              (future)
         ▼                  ▼                   ▼                   ▼                  │
  ┌─────────────┐    ┌─────────────┐     ┌─────────────┐     ┌─────────────┐           │
  │   Grafana   │    │ Prometheus  │     │    Loki     │     │    Tempo    │           │
  │    :3000    │    │    :9090    │     │    :3100    │     │    :3200    │           │
  └──────┬──────┘    └──────▲──────┘     └──────▲──────┘     └──────▲──────┘           │
         │                  │                   │                   │                  │
         │ Datasources      │ Scraping          │ Push              │ OTLP             │
         │ (Auto-provision) │                   │                   │ (4317/4318)      │
         └──────────────────┼───────────────────┼───────────────────┼──────────────────┘
                            │                   │                   │
                     ┌──────┴──────┐     ┌──────┴──────┐            │
                     │ Traefik     │     │ Alloy /     │            │
                     │ Metrics     │     │ Promtail    │            │
                     └─────────────┘     └─────────────┘            │
                                                                    │
                     ┌──────────────────────────────────────────────┴─────────────────┐
                     │           Future Microservices (FastAPI, etc.)                │
                     │   Logs -> Loki  |  Metrics -> Prometheus  |  Traces -> Tempo   │
                     └────────────────────────────────────────────────────────────────┘
```

---

## 🛠️ Stack Components & Versions

| Component | Version | Role | Host Route / Port | Internal Access |
|---|---|---|---|---|
| **Traefik** | `v3.7` | Reverse Proxy / API Gateway / Router | `http://localhost:8080` (Dashboard)<br>`http://localhost/` | `traefik:8080` |
| **Grafana** | `13.1.1` | Unified Visualization & Dashboards | `http://localhost/grafana` | `grafana:3000` |
| **Prometheus** | `v3.5.5` (LTS) | Time-Series Metrics Database | `http://localhost/prometheus` | `prometheus:9090` |
| **Loki** | `3.7.4` | High-Performance Log Aggregator | `http://localhost/loki` | `loki:3100` |
| **Grafana Alloy** | `v1.7.1` | Unified Telemetry Collector | Internal | `alloy:12345` |
| **Promtail** | `3.0.0` | Legacy Docker Log Shipper | Internal | `promtail:9080` |
| **Tempo** | `3.0.0` | Distributed Tracing Backend | `http://localhost/tempo` | `tempo:3200`<br>`tempo:4317` (gRPC)<br>`tempo:4318` (HTTP) |

---

## 📁 Directory Structure

```text
observability-lab/
├── docker-compose.yml              # Main orchestration specification
├── .env                            # Centralized environment variables
├── README.md                       # Comprehensive infrastructure documentation
│
├── traefik/                        # Traefik configuration
│   ├── traefik.yml                 # Static Traefik config (entrypoints, metrics, providers)
│   ├── dynamic/                    # Dynamic rules, routers, and custom middlewares
│   └── certificates/               # Future TLS certificates storage
│
├── grafana/                        # Grafana automated provisioning
│   ├── provisioning/
│   │   ├── dashboards/             # Auto-load dashboard providers
│   │   │   └── dashboards.yml
│   │   └── datasources/            # Auto-provision Prometheus, Loki, Tempo
│   │       └── datasources.yml
│   └── dashboards/                 # Drop JSON dashboard definitions here
│
├── prometheus/                     # Prometheus configuration
│   └── prometheus.yml              # Scrape jobs & remote write receivers
│
├── loki/                           # Loki configuration
│   └── config.yml                  # TSDB storage, schema v13, local filesystem
│
├── alloy/                          # Grafana Alloy configuration
│   └── config.alloy                # River syntax for Docker log discovery & Loki push
│
├── promtail/                       # Promtail configuration (legacy shipper)
│   └── config.yml                  # Container log scraping rules
│
└── tempo/                          # Tempo configuration
    └── tempo.yml                   # OTLP receivers (gRPC/HTTP), WAL, metrics generator
```

---

## 🚀 Quick Start

### Prerequisites

- [Docker Engine](https://docs.docker.com/engine/install/) (v24.0+)
- [Docker Compose](https://docs.docker.com/compose/install/) (v2.20+)

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

All 7 containers (`traefik`, `grafana`, `prometheus`, `loki`, `alloy`, `promtail`, `tempo`) should show as `running` or `healthy`.

---

## 🌐 Accessing Services

| Service | Access URL | Credentials (Default) |
|---|---|---|
| **Traefik Dashboard** | [http://localhost:8080](http://localhost:8080) | None (Dev mode) |
| **Grafana** | [http://localhost/grafana](http://localhost/grafana) | User: `admin` / Password: `admin` |
| **Prometheus UI** | [http://localhost/prometheus](http://localhost/prometheus) | None |
| **Loki Health** | [http://localhost/loki/ready](http://localhost/loki/ready) | None |
| **Tempo Health** | [http://localhost/tempo/ready](http://localhost/tempo/ready) | None |

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
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo:4317
      - OTEL_SERVICE_NAME=users-api
```

### 2. Telemetry Integration Points

- **Logs**: Output JSON logs to standard stdout/stderr. `alloy` and `promtail` automatically discover the container and stream logs to Loki.
- **Metrics**: Expose a `/metrics` endpoint (Prometheus format) on port `8000`. Add a scrape job in `prometheus/prometheus.yml`:
  ```yaml
  - job_name: 'users-api'
    static_configs:
      - targets: ['users-api:8000']
  ```
- **Traces**: Configure OpenTelemetry SDK to send traces to `tempo:4317` (gRPC) or `tempo:4318` (HTTP).

---

## 🔍 Grafana Pre-Configured Telemetry Correlator

Grafana is provisioned with cross-telemetry correlation rules out of the box:

1. **Log → Trace Correlation**: Loki log lines containing `"traceID":"..."` automatically display a clickable link directly opening the trace in **Tempo**.
2. **Trace → Log Correlation**: Viewing a trace in Tempo provides a direct action button to view corresponding container logs in **Loki** filtered by service and timeframe.
3. **Trace → Metrics Correlation**: Service map node graph in Tempo uses **Prometheus** metrics for span rate and latency calculations.

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
