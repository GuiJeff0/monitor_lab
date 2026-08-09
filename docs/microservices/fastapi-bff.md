# FastAPI BFF (Backend for Frontend / API Gateway)

> **Documentação de Arquitetura e Engenharia**  
> **Status:** Draft | **Versão:** 1.0.0

## 1. Visão Geral e Fronteiras de Domínio

O **FastAPI BFF** atua como o API Gateway e único ponto de entrada para requisições HTTP públicas provenientes do Traefik. Construído com Python 3.13+ e FastAPI, este serviço é desenhado para altíssimo throughput e baixa latência de I/O.

Sua principal responsabilidade é abstrair a complexidade do ecossistema de microsserviços, oferecendo uma API REST coesa para clientes (Web/Mobile) enquanto se comunica internamente via **gRPC** (síncrono) e **RabbitMQ** (assíncrono).

### Principais Responsabilidades:
1. **Validação Estrita:** Sanitização e validação de payloads de entrada utilizando Pydantic v2.
2. **Rate Limiting:** Proteção contra abusos implementada no nível de middleware com contadores no Redis (limite por IP e/ou JWT sub).
3. **Caching Agressivo:** Cache distribuído no Redis para endpoints de alta leitura, como o catálogo de eventos (TTL 60s).
4. **Proxy Síncrono (gRPC):** Chamadas eficientes via gRPC para `auth-service`, `user-service` e `event-service`.
5. **Comunicação Assíncrona (RabbitMQ):** Ingestão de carga de compra de tickets publicando eventos `order.created` de forma assíncrona com Publisher Confirms, retornando HTTP 202 Accepted em milissegundos.
6. **Telemetria e Contexto:** Geração ou propagação do `X-Correlation-ID` e inicialização de W3C Trace Context (`traceparent`).

---

## 2. Arquitetura em Camadas

A arquitetura segue um fluxo unidirecional e orientado a interfaces/clientes de infraestrutura.

```mermaid
flowchart TD
    Client[Client HTTP] --> Traefik[Traefik Proxy]
    Traefik --> Router[FastAPI Routers]
    
    subgraph FastAPI BFF App
        Router --> Middleware[Middlewares: OTel, RateLimit, Auth, Correlation]
        Middleware --> Controller[Controllers / Endpoints]
        
        Controller --> Pydantic[Pydantic Validators]
        
        Controller --> gRPCClient[gRPC Clients]
        Controller --> RedisClient[Redis Cache & RateLimit]
        Controller --> RMQClient[RabbitMQ Publisher]
    end
    
    gRPCClient -- ":50051" --> Auth[Auth Service]
    gRPCClient -- ":50052" --> User[User Service]
    gRPCClient -- ":50053" --> Event[Event Service]
    
    RedisClient -- "TCP :6379" --> Redis[(Redis)]
    RMQClient -- "AMQP :5672" --> RabbitMQ((RabbitMQ Exchange))
```

---

## 3. Endpoints REST da API

### `GET /health` e `GET /ready`
Endpoints de liveness e readiness para orquestração.
```json
{
  "status": "ok",
  "dependencies": {
    "redis": "up",
    "rabbitmq": "up",
    "grpc_auth": "up"
  }
}
```

### `POST /v1/auth/login`
Delega para o `auth-service` via gRPC.
**Request:**
```json
{
  "email": "user@example.com",
  "password": "securepassword123"
}
```
**Response (200 OK):**
```json
{
  "access_token": "eyJhbG...",
  "refresh_token": "def456...",
  "token_type": "Bearer"
}
```

### `GET /v1/events`
Obtém o catálogo. Verifica Cache Redis; se *miss*, busca no `event-service` (gRPC).
**Response (200 OK):**
```json
{
  "events": [
    {
      "id": "evt_123",
      "name": "Tech Conference 2026",
      "available_tickets": 5000
    }
  ]
}
```

### `POST /v1/orders`
Endpoint de alta concorrência. Valida payload, publica no RabbitMQ e retorna *Accepted*.
**Request:**
```json
{
  "event_id": "evt_123",
  "ticket_type": "VIP",
  "quantity": 2
}
```
**Response (202 Accepted):**
```json
{
  "message": "Order processing initiated",
  "correlation_id": "req-9876-abc"
}
```

---

## 4. Integração gRPC

O BFF utiliza `grpcio` e canais assíncronos (`grpc.aio.insecure_channel`) para se comunicar.
* **Context Propagation:** Interceptors customizados injetam metadados OTel (`traceparent`) e `X-Correlation-ID` em todas as chamadas gRPC de saída.
* **Connection Pooling:** Os canais gRPC são mantidos abertos ao longo do ciclo de vida da aplicação (iniciados no evento de startup do FastAPI).

---

## 5. Integração RabbitMQ

Utilizando a biblioteca `aio_pika`, o serviço mantém conexões multiplexadas (channels) com o RabbitMQ.
* **Exchange:** `orders.exchange` (Topic ou Direct).
* **Routing Key:** `order.created`.
* **Publisher Confirms:** Obrigatório para garantir que a mensagem não foi perdida antes de retornar HTTP 202.
* **Trace Context:** Headers AMQP são populados com contexto de tracing para continuação do span no serviço consumidor (`orders-service`).

---

## 6. Estrutura de Diretórios

```text
fastapi-bff/
├── src/
│   ├── main.py                 # FastAPI app init, middlewares
│   ├── api/
│   │   ├── routers/            # Endpoints (auth.py, events.py, orders.py)
│   │   └── dependencies.py     # Dependências de Injeção (get_db, get_redis)
│   ├── schemas/                # Modelos Pydantic v2
│   ├── clients/
│   │   ├── grpc/               # Stubs e conexões para serviços Go
│   │   ├── rabbitmq.py         # Configuração aio_pika
│   │   └── redis.py            # Configuração redis-py
│   ├── core/
│   │   ├── config.py           # Pydantic BaseSettings
│   │   ├── security.py         # Utils de JWT extraction
│   │   └── exceptions.py       # Tratadores de erro globais
│   └── telemetry/
│       ├── setup.py            # OTel SDK init
│       └── middlewares.py      # Correlation ID injection
├── tests/
├── protos/                     # Definições .proto sincronizadas
├── Dockerfile
├── requirements.txt
└── .env
```

---

## 7. Variáveis de Ambiente (.env)

```env
APP_ENV=production
LOG_LEVEL=info

# Redis
REDIS_URL=redis://redis:6379/0

# RabbitMQ
RABBITMQ_URL=amqp://guest:guest@rabbitmq:5672/

# gRPC Targets
AUTH_SERVICE_ADDR=auth-service:50051
USER_SERVICE_ADDR=user-service:50052
EVENT_SERVICE_ADDR=event-service:50053

# OpenTelemetry
OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy:4317
OTEL_SERVICE_NAME=fastapi-bff
```

---

## 8. Dockerfile e Traefik Labels

**Dockerfile (Resumo):**
```dockerfile
FROM python:3.13-slim
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY src/ /app/src/
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
```

**Traefik Labels (docker-compose):**
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.bff.rule=Host(`monitor.lab`) && PathPrefix(`/v1`)"
  - "traefik.http.routers.bff.entrypoints=websecure"
  - "traefik.http.routers.bff.tls=true"
  - "traefik.http.services.bff.loadbalancer.server.port=8000"
```

---

## 9. Observabilidade OTel SDK

O BFF integra fortemente a stack Grafana:
* **Métricas RED:** Coletadas automaticamente no HTTP via `opentelemetry-instrumentation-fastapi`. Expõe `/metrics` ou envia via OTLP gRPC.
* **Logs JSON Estruturados:** Usando `structlog`, injetando de forma transparente `trace_id`, `span_id` e `correlation_id` do contextvar.
* **Traces para Tempo:** Envia spans via OTLP ao Alloy. Interceptors gRPC garantem continuação para os microsserviços Go.

---

## 10. Testes e Checklist de Produção

* **Testes:** Uso intensivo de `pytest`, `pytest-asyncio` e `httpx` para testes de integração. Mocks explícitos para gRPC Channels e RabbitMQ Exchanges usando `unittest.mock`.
* **Checklist de Produção:**
  - [ ] Rate limits aplicados em todos os endpoints públicos.
  - [ ] Timeouts estritos para gRPC calls (max 2000ms).
  - [ ] Pydantic `extra = 'forbid'` ativado nos schemas sensíveis.
  - [ ] Circuit Breaker configurado para chamadas síncronas.

---

## 11. Diagrama de Sequência de uma Requisição (Assíncrona)

```mermaid
sequenceDiagram
    autonumber
    actor Client
    participant Traefik
    participant BFF as FastAPI BFF
    participant Redis as Redis Cache
    participant RMQ as RabbitMQ
    participant OrderSvc as Orders Service (Go)
    participant OTel as Alloy/Tempo

    Client->>Traefik: POST /v1/orders
    Traefik->>BFF: Fwd HTTP
    BFF->>OTel: Inicia Span (Trace ID gerado)
    BFF->>Redis: Check Rate Limit (IP)
    Redis-->>BFF: OK
    BFF->>RMQ: Publica "order.created" (Headers: Traceparent, CorrelationID)
    RMQ-->>BFF: ACK (Publisher Confirm)
    BFF-->>Traefik: 202 Accepted (X-Correlation-ID)
    Traefik-->>Client: 202 Accepted
    
    RMQ->>OrderSvc: Consome Mensagem
    OrderSvc->>OTel: Continua Span (Child of BFF)
```
