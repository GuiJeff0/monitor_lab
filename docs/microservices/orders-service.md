# Orders Service

## 1. Visão Geral e Estratégia de Concorrência

O **Orders Service** é o microsserviço mais crítico no ecossistema de vendas sob alta concorrência (flash sales) do Ticket Booking System. Desenvolvido em **Golang 1.23+**, opera consumindo mensagens assíncronas do RabbitMQ e expondo consultas de status via **gRPC** (:50054).

Sua principal responsabilidade é gerenciar o ciclo de vida do pedido e **garantir a reserva atômica de assentos** no PostgreSQL 16 sem permitir overbooking. Para isso, utiliza transações otimizadas de banco de dados e controle de concorrência pessimista (Pessimistic Locking) utilizando o poderoso comando `SELECT ... FOR UPDATE SKIP LOCKED` do PostgreSQL. Se os assentos são reservados com sucesso, ele agenda a expiração via TTL e publica um evento para o serviço de pagamentos.

## 2. Diagrama de Estados do Pedido

O ciclo de vida de um pedido é gerenciado como uma máquina de estados:

```mermaid
stateDiagram-v2
    [*] --> CREATED : Recebe de RabbitMQ
    
    CREATED --> RESERVED : Reserva Assentos (FOR UPDATE SKIP LOCKED)
    CREATED --> CANCELLED : Assentos Esgotados / Ocupados
    
    RESERVED --> PAYMENT_PROCESSING : Envia p/ Payment Service
    
    PAYMENT_PROCESSING --> CONFIRMED : Pagamento Aprovado
    PAYMENT_PROCESSING --> CANCELLED : Falha no Pagamento
    
    RESERVED --> EXPIRED : Timeout (10 min) / TTL Excedido
    PAYMENT_PROCESSING --> EXPIRED : Timeout (10 min)
    
    CONFIRMED --> [*]
    CANCELLED --> [*]
    EXPIRED --> [*]
```

## 3. Mecanismo de Locking no PostgreSQL

Em situações de flash sales (alta concorrência massiva no exato segundo), muitas transações tentam reservar os mesmos assentos simultaneamente. Abordagens ingênuas geram falhas, deadlocks ou overhead alto (Optimistic Locking).

O **Orders Service** adota o modelo `FOR UPDATE SKIP LOCKED`.

### Como Funciona:
Ao processar uma reserva, a query seleciona os assentos requeridos:

```sql
BEGIN;

-- 1. Tenta bloquear linhas (assentos) disponíveis desejadas
WITH reserved_seats AS (
    SELECT id
    FROM seats
    WHERE event_id = $1
      AND sector_id = $2
      AND status = 'AVAILABLE'
    LIMIT $3
    FOR UPDATE SKIP LOCKED
)
-- 2. Atualiza o status atrelado a este pedido (se encontrou o número exato)
UPDATE seats
SET status = 'RESERVED',
    order_id = $4,
    updated_at = NOW()
WHERE id IN (SELECT id FROM reserved_seats)
RETURNING id;

COMMIT;
```

**Por que `SKIP LOCKED`?**
Se duas goroutines/workers tentam reservar assentos no mesmo setor, a que chega primeiro bloqueia as linhas. A segunda transação *não fica em espera (block)* aguardando a liberação do lock da primeira. Ela *ignora (skips)* as linhas bloqueadas e busca as próximas disponíveis, melhorando brutalmente o throughput do banco de dados e eliminando esperas em filas de lock do PostgreSQL. Se não houver ingressos suficientes retornados pela CTE, a aplicação executa um `ROLLBACK`.

## 4. Integração RabbitMQ

- **Filas de Consumo:**
  - `order.created.queue`: Fila primária vinculada à Exchange `orders.topic` (Routing Key: `order.created`).
- **QoS (Prefetch Count):** Configurado para limitar concorrência e evitar sobrecarga na pool de conexões do DB.
- **Publisher Confirms:** Usado ao publicar mensagens para `payment.process`.
- **DLX (Dead Letter Exchange):** Configuradas `order.created.dlq` para mensagens não processáveis após N retries.
- **Expiração de Pedidos:** Utilizamos RabbitMQ TTL ou um cron de cleanup no banco para mover pedidos de `RESERVED` para `EXPIRED` após 10 minutos e liberar o assento de volta para `AVAILABLE`.

## 5. Protobuf Definition (`orders.proto`)

Usado estritamente para o BFF ou clientes gRPC consultarem o status do pedido de forma rápida.

```protobuf
syntax = "proto3";

package orders.v1;

option go_package = "github.com/observability-lab/orders-service/pkg/pb;ordersv1";

service OrdersService {
  rpc GetOrderStatus (GetOrderStatusRequest) returns (GetOrderStatusResponse);
}

message GetOrderStatusRequest {
  string order_id = 1;
}

message GetOrderStatusResponse {
  string order_id = 1;
  string status = 2; // CREATED, RESERVED, PAYMENT_PROCESSING, CONFIRMED, CANCELLED, EXPIRED
  double total_amount = 3;
}
```

## 6. Modelo de Dados PostgreSQL

```mermaid
erDiagram
    ORDERS {
        uuid id PK
        uuid user_id
        uuid event_id
        string status
        decimal total_amount
        timestamp created_at
        timestamp expires_at
    }
    ORDER_ITEMS {
        uuid id PK
        uuid order_id FK
        uuid sector_id
        int quantity
        decimal unit_price
    }
    SEATS {
        uuid id PK
        uuid event_id
        uuid sector_id
        string status "AVAILABLE, RESERVED, SOLD"
        uuid order_id FK
    }

    ORDERS ||--o{ ORDER_ITEMS : contains
    ORDERS ||--o{ SEATS : "reserves"
```

## 7. Estrutura de Diretórios Go

```text
orders-service/
├── cmd/
│   └── worker/
│       └── main.go              # Entrypoint do worker AMQP e gRPC
├── config/
│   └── config.go
├── internal/
│   ├── consumer/
│   │   └── amqp_consumer.go     # Recebe 'order.created'
│   ├── handler/
│   │   └── grpc_handler.go      # Responde 'GetOrderStatus'
│   ├── service/
│   │   └── order_service.go     # Lógica do Skip Locked e TTL
│   ├── repository/
│   │   ├── db.go                # Conexão pgxpool
│   │   └── query.sql.go         # Código gerado via sqlc
│   ├── publisher/
│   │   └── amqp_publisher.go    # Dispara 'payment.process'
│   └── sql/
│       ├── schema.sql           # DDL Migrations
│       └── queries.sql          # Queries raw para sqlc (incluindo SKIP LOCKED)
├── pkg/
│   └── pb/                      # Protobuf generated
├── docker-compose.yml
├── Dockerfile
├── go.mod
└── go.sum
```

## 8. Variáveis de Ambiente

```env
APP_ENV=production
GRPC_PORT=50054

# Postgres
DATABASE_URL=postgres://root:password@postgres:5432/orders_db?pool_max_conns=50

# RabbitMQ
RABBITMQ_URL=amqp://guest:guest@rabbitmq:5672/
RABBITMQ_EXCHANGE=orders.topic

# Observability OTel
OTEL_SERVICE_NAME=orders-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy:4317
OTEL_TRACES_SAMPLER=always_on
```

## 9. Dockerfile e Observabilidade OTel

### Propagação de Contexto AMQP headers ↔ OTel Span

Ao consumir do RabbitMQ, é vital extrair o `traceparent` injetado pelo BFF via headers AMQP para unir o Trace de ponta a ponta.

```go
// Exemplo no consumer RabbitMQ
import "go.opentelemetry.io/otel/propagation"

func processMessage(msg amqp.Delivery) {
    // Extrai o W3C Trace Context dos headers da mensagem
    propagator := propagation.TraceContext{}
    ctx := propagator.Extract(context.Background(), AMQPHeadersCarrier(msg.Headers))

    // Inicia span encadeado
    tracer := otel.Tracer("amqp-consumer")
    ctx, span := tracer.Start(ctx, "ProcessOrderCreated")
    defer span.End()
    
    // ... executa regra de negócio passando o `ctx` ...
}
```

O `pgxpool` também deve ser instrumentado (`otelpgx`) para rastrear a duração exata do `SKIP LOCKED`.

### Dockerfile

```dockerfile
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /go/bin/worker ./cmd/worker/main.go

FROM gcr.io/distroless/static-debian12
COPY --from=builder /go/bin/worker /worker
EXPOSE 50054
USER nonroot:nonroot
ENTRYPOINT ["/worker"]
```

## 10. Checklist de Produção

- [ ] Lock Concorrente usando `FOR UPDATE SKIP LOCKED` implementado e testado.
- [ ] Transações ACID bem isoladas no pgxpool (Commit apenas em sucesso).
- [ ] Tratamento de Timeout / TTL com rollback da reserva.
- [ ] RabbitMQ Prefetch Count e AMQP context propagation configurados.
- [ ] OTel `trace_id` injetado nos logs em caso de erro na reserva.
- [ ] Métricas RED exportadas (contadores de falhas por falta de assento vs falhas sistêmicas).
- [ ] Queries preparadas utilizando `sqlc` para segurança (PreparedStatement).
- [ ] Retries exponenciais na publicação em `payment.process`.
