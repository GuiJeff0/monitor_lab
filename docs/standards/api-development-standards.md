# API & Microservices Development Standards

> **Versão:** 2.0  
> **Objetivo:** Definir padrões arquiteturais, convenções de código, contratos de comunicação (REST e gRPC), mensageria (AMQP/RabbitMQ) e requisitos de observabilidade para todos os microsserviços do **Ticket Booking System**.

---

# 1. Visão Geral

Todos os microsserviços do ecossistema devem seguir rigorosamente os princípios de **Clean Architecture**, isolamento de domínios (Domain-Driven Boundaries), observabilidade nativa e comunicação de alto desempenho.

### Princípios Fundamentais:
1. **Contratos Estritos:** Schemas Pydantic v2 para HTTP/REST e `.proto` (Protobuf v3) para gRPC.
2. **Separação de Protocolos:**
   - **Síncrono Externo:** HTTP/HTTPS via FastAPI BFF.
   - **Síncrono Interno:** gRPC (HTTP/2) com Protobuf entre serviços Golang.
   - **Assíncrono Interno:** Mensageria AMQP via RabbitMQ para operações de alta concorrência ou não-bloqueantes.
3. **Observabilidade Unificada:** OTel SDK obrigatório em todos os serviços (Métricas no Mimir, Logs no Loki, Traces no Tempo).
4. **Resiliência e Idempotência:** Publisher Confirms, Dead Letter Exchanges (DLX), Chaves de Idempotência e Bloqueio Otimista/Pessimista.

---

# 2. Stacks Tecnológicas Padrão

## 2.1 Backend for Frontend (FastAPI BFF)
- **Linguagem:** Python 3.13+
- **Framework:** FastAPI / Uvicorn
- **Validação & Tipagem:** Pydantic v2
- **Clientes:** `grpcio` (gRPC), `aio-pika` (RabbitMQ), `redis-py` (Cache & Rate Limit), `httpx` (HTTP Async)
- **Observabilidade:** `opentelemetry-api`, `opentelemetry-sdk`, `opentelemetry-instrumentation-fastapi`

## 2.2 Microsserviços Internos de Alta Concorrência (Golang)
- **Linguagem:** Golang 1.23+
- **Comunicação Síncrona:** `google.golang.org/grpc` + `google.golang.org/protobuf`
- **Mensageria:** `github.com/rabbitmq/amqp091-go`
- **Persistência Relacional:** `github.com/jackc/pgx/v5` ou `sqlc` (PostgreSQL 16)
- **Persistência NoSQL:** `go.mongodb.org/mongo-driver/v2` (MongoDB 7)
- **Busca Textual:** `github.com/elastic/go-elasticsearch/v8` (Elasticsearch 8)
- **Observabilidade:** `go.opentelemetry.io/otel` (Tracer, Meter, Logger), Interceptors gRPC e middleware OTel

---

# 3. Estruturas de Projeto Padronizadas

## 3.1 Estrutura Python / FastAPI (BFF)
```text
fastapi-bff/
├── app/
│   ├── api/
│   │   └── v1/
│   │       ├── auth_router.py
│   │       ├── events_router.py
│   │       └── orders_router.py
│   ├── core/
│   │   ├── config.py             # Pydantic Settings
│   │   ├── security.py           # JWT & Auth
│   │   └── exceptions.py         # Exception Handlers
│   ├── grpc_clients/             # Stubs e Wrappers gRPC
│   │   ├── auth_client.py
│   │   ├── user_client.py
│   │   └── event_client.py
│   ├── messaging/                # RabbitMQ Producers
│   │   └── rabbitmq_publisher.py
│   ├── middleware/
│   │   ├── correlation_id.py     # X-Correlation-ID
│   │   └── rate_limit.py         # Redis Token Bucket
│   ├── schemas/                  # Pydantic Request/Response Models
│   ├── telemetry/                # Configuração OpenTelemetry SDK
│   └── main.py
├── tests/
├── Dockerfile
├── pyproject.toml
└── README.md
```

## 3.2 Estrutura Golang (Standard Clean Architecture)
```text
<service-name>/
├── cmd/
│   └── server/
│       └── main.go               # Entrypoint, injeção de dependência e shutdown gracioso
├── internal/
│   ├── domain/                   # Entidades e Interfaces de Repositório/Service
│   │   ├── models.go
│   │   └── repository.go
│   ├── handler/                  # Adaptadores de Entrada
│   │   ├── grpc/                 # Handlers gRPC gerados a partir do proto
│   │   └── amqp/                 # Consumidores de filas RabbitMQ
│   ├── usecase/                  # Regras de Negócio e Orquestração
│   │   └── service.go
│   ├── repository/               # Acesso a Dados (Postgres/Mongo/ES)
│   │   └── postgres_repo.go
│   └── telemetry/                # OTel Tracer, Meter e Structured Logger
├── proto/                        # Definições Protobuf
│   └── <service>.proto
├── migrations/                   # Scripts SQL (Alembic / Goose / Golang-migrate)
├── Dockerfile
├── go.mod
├── go.sum
└── README.md
```

---

# 4. Padrões de Comunicação

## 4.1 gRPC (Síncrono)
1. **Contratos Centralizados:** Todos os arquivos `.proto` devem definir tipos semânticos claros e convenções de nomenclatura `PascalCase` para Mensagens e `CamelCase` para campos.
2. **Propagação de Contexto:** Interceptors gRPC devem obrigatoriamente injetar e extrair metadados W3C (`traceparent`) e Correlation ID (`x-correlation-id`).
3. **Deadlines & Timeouts:** Todo client gRPC deve definir um deadline explícito (ex: 500ms a 2s) via `context.WithTimeout`.
4. **Tratamento de Códigos gRPC:**
   - `codes.NotFound` para recursos inexistentes.
   - `codes.InvalidArgument` para validação falha.
   - `codes.AlreadyExists` para conflitos.
   - `codes.ResourceExhausted` para esgotamento de assentos ou rate limit.

## 4.2 RabbitMQ / AMQP (Assíncrono)
1. **Exchanges e Routing Keys:**
   - Exchanges do tipo `topic` ou `direct` com persistência (`durable: true`).
   - Padrão de Routing Key: `<entidade>.<ação>` (ex: `order.created`, `payment.process`, `notification.send`).
2. **Publisher Confirms:** O produtor (ex: FastAPI BFF) deve aguardar a confirmação do broker antes de retornar `202 Accepted`.
3. **Headers AMQP para Telemetria:**
   - `traceparent`: String W3C Trace Context.
   - `X-Correlation-ID`: UUID v4 do fluxo.
4. **Dead Letter Exchange (DLX):** Todas as filas de missão crítica devem ter política DLX configurada para redirecionar mensagens rejeitadas após N retentativas.

---

# 5. Padrões de Persistência Poliglota

| Banco | Papel no Ecossistema | Padrão Obrigatório |
|---|---|---|
| **PostgreSQL 16** | Usuários, Pedidos, Ingressos | Transações ACID, Índices em chaves de busca, Concorrência com `SELECT ... FOR UPDATE SKIP LOCKED` |
| **MongoDB 7** | Catálogo de Eventos, Auditoria | Documentos versionados, Índices compostos por data/categoria, TTL indexes em logs temporários |
| **Elasticsearch 8** | Busca Full-Text e Agregações | Mapeamentos explícitos com analyzers customizados, indexação assíncrona orientada a eventos |
| **Redis** | Cache e Rate Limiting | Chaves padronizadas (`prefix:entity:id`), TTL obrigatório em todos os caches (ex: 60s) |

---

# 6. Observabilidade & Logging Estruturado

Cada requisição e mensagem processada **deve** gerar:

```json
{
  "timestamp": "2026-08-09T10:00:00.123Z",
  "level": "INFO",
  "service": "orders-service",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
  "event": "seat.reserved",
  "order_id": "ord_992182",
  "seats_count": 2,
  "duration_ms": 14.2
}
```

### Regras:
- **Nunca use** `print()` ou `fmt.Println()`.
- Utilize sempre structured logging (`slog` em Go ou `structlog`/OTel logging em Python).
- O `trace_id` e `span_id` devem ser linkados automaticamente no Grafana (Log ↔ Trace).

---

# 7. Checklist de Qualidade e Produção

Antes de considerar um serviço pronto:
- [ ] Contratos de API / Protobuf versionados
- [ ] Validações de payload rigorosas
- [ ] OpenTelemetry configurado (OTLP exportando para Mimir, Loki, Tempo)
- [ ] Propagação de W3C `traceparent` e `X-Correlation-ID` validada
- [ ] Healthcheck `/health` (liveness) e `/ready` (readiness) implementados
- [ ] Dockerfile multi-stage com execução non-root
- [ ] Cobertura de testes automatizados > 80% (unitários e de integração)
- [ ] Sem secrets hardcoded no código (tudo externalizado em variáveis de ambiente)
