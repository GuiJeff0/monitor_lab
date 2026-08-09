# High-Concurrency Ticket Booking System — Architecture

> **Document:** System Architecture Diagram  
> **Role:** Senior Cloud Architect  
> **Goal:** Design a production-grade, high-concurrency ticket booking platform with polyglot persistence, mixed sync/async communication, and full observability.

---

## 1. Full System Architecture

```mermaid
flowchart TB
    subgraph Clients["Edge — Clients"]
        WebApp["🌐 Web App<br/>(React / Next.js)"]
        MobileApp["📱 Mobile App<br/>(React Native / Flutter)"]
    end

    subgraph Edge["Edge & Ingress Layer"]
        Traefik["Traefik v3<br/>TLS Termination<br/>Rate Limiting<br/>Load Balancing"]
    end

    subgraph BFF["API Gateway — BFF (Python)"]
        FastAPI["FastAPI<br/>Pydantic Validation<br/>Rate Limiting<br/>Auth Middleware<br/>OTel SDK"]
        RedisCache[("Redis<br/>Event Catalog Cache<br/>Session Store<br/>Rate Limit Counters")]
    end

    subgraph SyncServices["Synchronous Microservices — gRPC (Golang)"]
        AuthService["Auth Service<br/>JWT / OAuth2<br/>OTel SDK"]
        UserService["User Service<br/>Profile & Preferences<br/>OTel SDK"]
        EventService["Event Service<br/>Catalog & Search<br/>OTel SDK"]
    end

    subgraph AsyncBroker["Message Broker"]
        RabbitMQ[["RabbitMQ<br/>Persistent Queues<br/>DLX (Dead Letter Exchange)<br/>Publisher Confirms"]]
    end

    subgraph AsyncServices["Asynchronous Consumers — (Golang)"]
        OrderService["Orders Service<br/>Reservation & Locking<br/>OTel SDK"]
        PaymentService["Payment Service<br/>Payment Gateway Integration<br/>OTel SDK"]
        NotificationService["Notification Service<br/>Email / SMS / Push<br/>OTel SDK"]
        SearchSyncService["Search Sync Worker<br/>PostgreSQL → Elasticsearch<br/>OTel SDK"]
    end

    subgraph Persistence["Polyglot Persistence"]
        PostgreSQL[("PostgreSQL<br/>Users, Orders, Tickets<br/>Row-Level Locking<br/>ACID Transactions")]
        MongoDB[("MongoDB<br/>Event Catalog<br/>Audit Logs<br/>Flexible Documents")]
        Elasticsearch[("Elasticsearch<br/>Full-Text Search<br/>Event Discovery<br/>Faceted Filters")]
    end

    subgraph Observability["Observability Stack — Monitor Lab"]
        OTelSDK["OpenTelemetry SDK<br/>(Embedded in all services)"]
        Mimir[("Mimir<br/>Metrics")]
        Loki[("Loki<br/>Logs")]
        Tempo[("Tempo<br/>Traces")]
        Grafana["Grafana<br/>Dashboards"]
    end

    %% Client → Edge
    WebApp & MobileApp -->|HTTPS| Traefik

    %% Edge → BFF
    Traefik -->|Route: /api/*| FastAPI

    %% BFF Cache
    FastAPI <-->|Cache Hit/Miss| RedisCache

    %% Synchronous gRPC calls
    FastAPI -->|gRPC :50051| AuthService
    FastAPI -->|gRPC :50052| UserService
    FastAPI -->|gRPC :50053| EventService

    %% Async publish
    FastAPI -->|Publish: order.created| RabbitMQ

    %% Async consume
    RabbitMQ -->|Consume: order.created| OrderService
    RabbitMQ -->|Consume: payment.process| PaymentService
    RabbitMQ -->|Consume: notification.send| NotificationService
    RabbitMQ -->|Consume: event.updated| SearchSyncService

    %% Service → Publish (chaining)
    OrderService -->|Publish: payment.process| RabbitMQ
    PaymentService -->|Publish: notification.send| RabbitMQ

    %% Persistence
    AuthService & UserService -->|SQL| PostgreSQL
    OrderService -->|SQL + Row Lock| PostgreSQL
    PaymentService -->|SQL| PostgreSQL
    EventService -->|Read/Write| MongoDB
    EventService -->|FTS Query| Elasticsearch
    SearchSyncService -->|Index Sync| Elasticsearch
    NotificationService -->|Audit Log| MongoDB

    %% Observability
    OTelSDK -.->|OTLP Metrics| Mimir
    OTelSDK -.->|OTLP Logs| Loki
    OTelSDK -.->|OTLP Traces| Tempo
    Mimir & Loki & Tempo -.->|Datasource| Grafana
```

---

## 2. Synchronous Flow — gRPC Reads & Authentication

Low-latency operations that require an immediate response use **gRPC** for binary-serialized, schema-enforced communication between the FastAPI BFF and internal Golang microservices.

```mermaid
sequenceDiagram
    autonumber
    actor Client as Client (Web / Mobile)
    participant Traefik as Traefik (Edge)
    participant BFF as FastAPI BFF
    participant Redis as Redis Cache
    participant Auth as Auth Service (Go/gRPC)
    participant User as User Service (Go/gRPC)
    participant Event as Event Service (Go/gRPC)
    participant PG as PostgreSQL
    participant Mongo as MongoDB
    participant ES as Elasticsearch

    Note over Client,ES: === User Login Flow ===
    Client->>Traefik: POST /api/v1/auth/login (JSON)
    Traefik->>BFF: Forward (TLS terminated)
    BFF->>BFF: Pydantic validates payload
    BFF->>Auth: gRPC LoginRequest(email, password)
    Auth->>PG: SELECT * FROM users WHERE email = $1
    PG-->>Auth: User row (hashed password)
    Auth->>Auth: bcrypt.Compare → Generate JWT
    Auth-->>BFF: gRPC LoginResponse(access_token, refresh_token)
    BFF-->>Client: 200 OK { tokens }

    Note over Client,ES: === Browse Events (Today / This Week) ===
    Client->>Traefik: GET /api/v1/events?filter=this_week
    Traefik->>BFF: Forward
    BFF->>Redis: GET events:catalog:this_week
    alt Cache HIT
        Redis-->>BFF: Cached event list (JSON)
        BFF-->>Client: 200 OK { events[] }
    else Cache MISS
        Redis-->>BFF: null
        BFF->>Event: gRPC ListEvents(filter=THIS_WEEK)
        Event->>Mongo: db.events.find({ date: { $gte: today, $lte: endOfWeek } })
        Mongo-->>Event: Event documents[]
        Event-->>BFF: gRPC EventListResponse
        BFF->>Redis: SET events:catalog:this_week (TTL 60s)
        BFF-->>Client: 200 OK { events[] }
    end

    Note over Client,ES: === Full-Text Search ===
    Client->>Traefik: GET /api/v1/events/search?q=rock+concert
    Traefik->>BFF: Forward
    BFF->>Event: gRPC SearchEvents(query="rock concert")
    Event->>ES: POST /events/_search { "query": { "multi_match": ... } }
    ES-->>Event: Search hits[]
    Event-->>BFF: gRPC SearchResponse
    BFF-->>Client: 200 OK { results[] }
```

---

## 3. Asynchronous Flow — High-Concurrency Ticket Purchase

The ticket purchase is the **hottest path** in the system. To absorb burst traffic without blocking the client, the BFF publishes an event to RabbitMQ and returns `202 Accepted` immediately. Downstream consumers process at their own pace.

```mermaid
sequenceDiagram
    autonumber
    actor Client as Client
    participant BFF as FastAPI BFF
    participant RMQ as RabbitMQ
    participant Orders as Orders Service (Go)
    participant PG as PostgreSQL
    participant Payments as Payment Service (Go)
    participant Gateway as Payment Gateway (Stripe/etc)
    participant Notif as Notification Service (Go)
    participant Mongo as MongoDB

    Note over Client,Mongo: === Ticket Purchase (Async Pipeline) ===

    Client->>BFF: POST /api/v1/orders { event_id, seat_ids[], payment_method }
    BFF->>BFF: Pydantic validation + JWT auth check
    BFF->>RMQ: Publish "order.created"<br/>{ order_id, user_id, event_id, seat_ids[], payment_method }<br/>(persistent, publisher-confirm)
    BFF-->>Client: 202 Accepted { order_id, status: "processing" }

    Note over RMQ,Mongo: === Stage 1: Reservation with Row-Level Locking ===
    RMQ->>Orders: Consume "order.created"
    Orders->>PG: BEGIN TRANSACTION
    Orders->>PG: SELECT * FROM seats<br/>WHERE id IN (seat_ids)<br/>AND status = 'available'<br/>FOR UPDATE SKIP LOCKED
    alt Seats Available
        Orders->>PG: UPDATE seats SET status = 'reserved',<br/>reserved_by = user_id,<br/>reserved_until = NOW() + '10 min'
        Orders->>PG: INSERT INTO orders (id, user_id, status)<br/>VALUES (order_id, user_id, 'reserved')
        Orders->>PG: COMMIT
        Orders->>RMQ: Publish "payment.process"<br/>{ order_id, amount, payment_method }
    else Seats Unavailable (Race Condition Prevented)
        Orders->>PG: ROLLBACK
        Orders->>RMQ: Publish "notification.send"<br/>{ user_id, type: "order_failed", reason: "sold_out" }
    end

    Note over RMQ,Mongo: === Stage 2: Payment Processing ===
    RMQ->>Payments: Consume "payment.process"
    Payments->>Gateway: POST /v1/charges { amount, token }
    alt Payment Successful
        Gateway-->>Payments: 200 { charge_id }
        Payments->>PG: UPDATE orders SET status = 'confirmed'<br/>UPDATE seats SET status = 'sold'
        Payments->>RMQ: Publish "notification.send"<br/>{ user_id, type: "order_confirmed", order_id }
    else Payment Failed
        Gateway-->>Payments: 402 { error }
        Payments->>PG: UPDATE orders SET status = 'payment_failed'<br/>UPDATE seats SET status = 'available'
        Payments->>RMQ: Publish "notification.send"<br/>{ user_id, type: "payment_failed" }
    end

    Note over RMQ,Mongo: === Stage 3: User Notification ===
    RMQ->>Notif: Consume "notification.send"
    Notif->>Notif: Send Email / SMS / Push
    Notif->>Mongo: db.audit_logs.insert({ event, timestamp, payload })

    Note over Client,Mongo: === Client Polls for Status ===
    Client->>BFF: GET /api/v1/orders/{order_id}/status
    BFF->>Orders: gRPC GetOrderStatus(order_id)
    Orders->>PG: SELECT status FROM orders WHERE id = $1
    PG-->>Orders: { status: "confirmed" }
    Orders-->>BFF: gRPC OrderStatusResponse
    BFF-->>Client: 200 OK { status: "confirmed", ticket_url: "..." }
```

---

## 4. Polyglot Persistence Strategy

Each database is chosen for its strengths in a specific domain:

```mermaid
flowchart LR
    subgraph Transactional["PostgreSQL — Source of Truth"]
        direction TB
        UsersTable["users<br/>id | email | password_hash | role"]
        OrdersTable["orders<br/>id | user_id | event_id | status | total"]
        SeatsTable["seats<br/>id | event_id | section | row | number | status | reserved_by | reserved_until"]
        PaymentsTable["payments<br/>id | order_id | charge_id | amount | status"]
    end

    subgraph Document["MongoDB — Flexible & Fast Reads"]
        direction TB
        EventsColl["events<br/>{title, description, venue, date,<br/>categories[], pricing[], images[],<br/>capacity, metadata{}}"]
        AuditColl["audit_logs<br/>{service, action, user_id,<br/>payload{}, timestamp,<br/>trace_id, span_id}"]
    end

    subgraph Search["Elasticsearch — Full-Text Discovery"]
        direction TB
        EventsIndex["events index<br/>title (analyzed), description (analyzed),<br/>venue, categories, date,<br/>geo_point, price_range"]
    end

    Transactional --- |"ACID Guarantees<br/>Row-Level Locking<br/>Foreign Keys"| UsersTable
    Document --- |"Schema Flexibility<br/>Nested Documents<br/>High Write Throughput"| EventsColl
    Search --- |"Full-Text Search<br/>Faceted Filters<br/>Geo Queries<br/>Autocomplete"| EventsIndex
```

---

## 5. Data Synchronization Pipeline

Keeping Elasticsearch in sync with the source data via RabbitMQ event-driven updates:

```mermaid
flowchart LR
    subgraph Source["Source of Truth"]
        PG[("PostgreSQL<br/>(Orders, Seats)")]
        Mongo[("MongoDB<br/>(Event Catalog)")]
    end

    subgraph Broker["Event Bus"]
        RMQ[["RabbitMQ"]]
    end

    subgraph Worker["Sync Workers (Golang)"]
        SyncWorker["Search Sync Worker<br/>- Transforms documents<br/>- Handles retries<br/>- Idempotent upserts"]
    end

    subgraph Target["Search Index"]
        ES[("Elasticsearch")]
    end

    Mongo -->|"event.created<br/>event.updated<br/>event.deleted"| RMQ
    PG -->|"seats.status_changed<br/>(available count update)"| RMQ
    RMQ -->|Consume| SyncWorker
    SyncWorker -->|"PUT /events/_doc/{id}<br/>(Upsert)"| ES
```

---

## 6. Observability Pipeline (Monitor Lab Integration)

Every service is instrumented with the **OpenTelemetry SDK**, exporting telemetry directly via OTLP to the centralized Monitor Lab:

```mermaid
flowchart TB
    subgraph Services["Instrumented Services"]
        direction LR
        S1["FastAPI BFF<br/>(OTel Python SDK)"]
        S2["Auth Service<br/>(OTel Go SDK)"]
        S3["Orders Service<br/>(OTel Go SDK)"]
        S4["Payment Service<br/>(OTel Go SDK)"]
        S5["Event Service<br/>(OTel Go SDK)"]
    end

    subgraph Infra["Infrastructure Telemetry"]
        Alloy["Grafana Alloy<br/>(Docker container logs<br/>+ infra metrics scraping)"]
    end

    subgraph MonitorLab["Monitor Lab (Centralized)"]
        Mimir[("Mimir<br/>OTLP Metrics<br/>PromQL")]
        Loki[("Loki<br/>OTLP Logs<br/>LogQL")]
        Tempo[("Tempo<br/>OTLP Traces<br/>TraceQL")]
        Grafana["Grafana<br/>Unified Dashboards"]
    end

    S1 & S2 & S3 & S4 & S5 -->|"OTLP gRPC :4317<br/>(Traces)"| Tempo
    S1 & S2 & S3 & S4 & S5 -->|"OTLP HTTP<br/>(Metrics)"| Mimir
    S1 & S2 & S3 & S4 & S5 -->|"OTLP HTTP<br/>(Structured Logs)"| Loki

    Alloy -->|"Scrape /metrics<br/>(Traefik, RabbitMQ, PG, Mongo, ES)"| Mimir
    Alloy -->|"Docker Logs<br/>(Container stdout/stderr)"| Loki

    Mimir -->|Datasource| Grafana
    Loki -->|Datasource| Grafana
    Tempo -->|Datasource| Grafana

    Grafana -->|"Log → Trace<br/>(trace_id correlation)"| Tempo
    Grafana -->|"Trace → Metrics<br/>(service map)"| Mimir
```

---

## 7. Service Map & Port Allocation

```text
┌──────────────────────────────────────────────────────────────────────────────────┐
│                              EXTERNAL PORTS (HOST)                               │
├──────────┬──────────────────────────────────┬────────────────────────────────────┤
│ Port     │ Service                          │ Protocol / Purpose                 │
├──────────┼──────────────────────────────────┼────────────────────────────────────┤
│ :80      │ Traefik (web)                    │ HTTP → Redirect HTTPS              │
│ :443     │ Traefik (websecure)              │ HTTPS (TLS Termination)            │
│ :8080    │ Traefik Dashboard                │ HTTP (Dev only)                    │
│ :15672   │ RabbitMQ Management UI           │ HTTP (Dev only)                    │
└──────────┴──────────────────────────────────┴────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────────┐
│                         INTERNAL DOCKER NETWORK                                  │
├──────────────────┬──────────┬───────────────────────────────────────────────────┤
│ Service          │ Port     │ Protocol / Notes                                   │
├──────────────────┼──────────┼───────────────────────────────────────────────────┤
│ fastapi-bff      │ 8000     │ HTTP (Uvicorn)                                     │
│ auth-service     │ 50051    │ gRPC (Protobuf)                                    │
│ user-service     │ 50052    │ gRPC (Protobuf)                                    │
│ event-service    │ 50053    │ gRPC (Protobuf)                                    │
│ orders-service   │ 50054    │ gRPC (Protobuf) + RabbitMQ Consumer                │
│ payment-service  │ 50055    │ gRPC (Protobuf) + RabbitMQ Consumer                │
│ notif-service    │ 50056    │ gRPC (Protobuf) + RabbitMQ Consumer                │
│ rabbitmq         │ 5672     │ AMQP 0.9.1 (Message Broker)                        │
│ redis            │ 6379     │ RESP (Cache / Rate Limit)                           │
│ postgresql       │ 5432     │ PostgreSQL Wire Protocol                            │
│ mongodb          │ 27017    │ MongoDB Wire Protocol                               │
│ elasticsearch    │ 9200     │ HTTP (REST API)                                     │
│ mimir            │ 8080     │ OTLP / Prometheus Remote Write                      │
│ loki             │ 3100     │ OTLP / Loki Push API                                │
│ tempo            │ 3200     │ HTTP API / 4317 gRPC OTLP / 4318 HTTP OTLP          │
│ grafana          │ 3000     │ HTTP (Dashboards)                                   │
│ alloy            │ 12345    │ HTTP (Self-metrics + Config UI)                      │
└──────────────────┴──────────┴───────────────────────────────────────────────────┘
```

---

## 8. Key Architectural Decisions

### Why gRPC for Reads?
- **Binary serialization** (Protobuf) is ~10x faster than JSON for structured payloads.
- **Strict contracts** via `.proto` files enforce API compatibility between Python (BFF) and Go (services).
- **HTTP/2 multiplexing** allows concurrent requests on a single TCP connection.

### Why RabbitMQ for Writes?
- **Persistent queues** guarantee no message loss even if consumers crash.
- **Dead Letter Exchanges (DLX)** capture failed messages for retry and inspection.
- **Publisher confirms** ensure the BFF knows the message was durably stored before returning `202`.
- **Decouples throughput**: The BFF can accept 10,000 orders/sec while consumers process at 1,000/sec without backpressure.

### Why Row-Level Locking (`FOR UPDATE SKIP LOCKED`)?
- Prevents **double-booking** race conditions when 500 users try to reserve the same seat simultaneously.
- `SKIP LOCKED` ensures non-contending rows are processed immediately, avoiding global lock contention.

### Why Redis at the BFF?
- Event catalogs are **read-heavy** and change infrequently — a 60-second TTL cache absorbs 95%+ of read traffic.
- Rate limiting counters with sliding window prevent abuse without adding latency to every request.

### Why Polyglot Persistence?
| Database | Strength | Use Case |
|---|---|---|
| **PostgreSQL** | ACID, row-level locking, referential integrity | Users, orders, seats, payments |
| **MongoDB** | Flexible schema, nested documents, high write throughput | Event catalog, audit logs |
| **Elasticsearch** | Full-text search, faceted filters, geo queries | Event discovery, autocomplete |
