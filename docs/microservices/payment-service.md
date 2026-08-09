# Payment Service

## 1. Visão Geral e Padrão de Idempotência

O **Payment Service** atua como integrador entre o Ticket Booking System e os provedores externos de meios de pagamento (Gateways como Stripe, MercadoPago ou um Mock interno).
Desenvolvido em **Golang 1.23+**, este microsserviço assíncrono consome mensagens do RabbitMQ (`payment.process`) e gerencia a transação financeira. 

Uma vez que redes podem falhar e mensagens AMQP podem ser entregues mais de uma vez (At-Least-Once delivery), a operação de pagamento deve ser rigorosamente **Idempotente**. Ou seja, uma cobrança associada a um pedido não pode ocorrer duas vezes. O serviço armazena uma chave de idempotência (`idempotency_key`, frequentemente atrelada ao `order_id` e a uma tentativa) no PostgreSQL 16 e implementa resiliência robusta de retries e timeouts ao chamar gateways externos.

## 2. Fluxo de Pagamento (Sequence Diagram)

```mermaid
sequenceDiagram
    participant RMQ as RabbitMQ
    participant P_Svc as Payment Service
    participant PG as PostgreSQL
    participant GTW as Payment Gateway
    participant RMQ_Notif as RabbitMQ (Notification)

    RMQ->>P_Svc: Consume: payment.process (order_id)
    
    P_Svc->>PG: BEGIN; SELECT ... FOR UPDATE (Check Idempotency)
    alt Already Processed
        PG-->>P_Svc: Retorna Status Existente
        P_Svc-->>RMQ: ACK Message (Skip)
    else New Payment
        P_Svc->>PG: INSERT STATUS = PROCESSING
        PG-->>P_Svc: COMMIT;
        
        P_Svc->>GTW: Call Gateway API (Timeout 5s, Retry 3x)
        alt Gateway Success
            GTW-->>P_Svc: HTTP 200 OK (charge_id)
            P_Svc->>PG: UPDATE status = SUCCESS, save charge_id
            P_Svc->>RMQ_Notif: Publish: notification.send (Success)
        else Gateway Failed
            GTW-->>P_Svc: HTTP 4xx/5xx Decline
            P_Svc->>PG: UPDATE status = FAILED
            P_Svc->>RMQ_Notif: Publish: notification.send (Fail)
        end
        
        P_Svc->>RMQ: Publish: order.payment_status (Para Orders Service)
        P_Svc-->>RMQ: ACK Message (payment.process)
    end
```

## 3. Integração RabbitMQ

- **Filas e Consumo:** Consome a fila `payment.process.queue` vinculada à Exchange `payments.topic`.
- **Publicação:** 
  - Para notificações: `notification.send` na Exchange `notifications.topic`.
  - Para retroalimentação do status do pedido: `order.payment_status` (o `Orders Service` consumirá para mover de RESERVED para CONFIRMED ou CANCELLED).
- **Dead Letter Queue (DLQ):** Qualquer falha não tratável na camada de negócio envia a mensagem para a DLQ para análise manual (ex: falhas drásticas de banco de dados, dados corrompidos).

## 4. Modelo de Dados PostgreSQL

A tabela `payments` garante a idempotência através de Constraint UNIQUE.

```sql
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL,
    idempotency_key VARCHAR(255) UNIQUE NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'BRL',
    status VARCHAR(50) NOT NULL, -- PROCESSING, SUCCESS, FAILED
    gateway_charge_id VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indice para buscas rápidas pelo order_id
CREATE INDEX idx_payments_order_id ON payments(order_id);
```

## 5. Estrutura de Diretórios Go

```text
payment-service/
├── cmd/
│   └── worker/
│       └── main.go              # Entrypoint Go / RabbitMQ Listener
├── config/
│   └── config.go
├── internal/
│   ├── consumer/
│   │   └── amqp_consumer.go     # Handler de consumo de pagamentos
│   ├── service/
│   │   └── payment_service.go   # Lógica de negócio e Idempotência
│   ├── gateway/
│   │   └── stripe_client.go     # Integração HTTP com Gateway
│   ├── repository/
│   │   └── postgres_repo.go     # Queries de Insert e Update
│   └── publisher/
│       └── amqp_publisher.go    # Emite eventos de notificação e ordens
├── pkg/
│   └── pb/                      # gRPC stub (opcional, p/ status gRPC)
├── docker-compose.yml
├── Dockerfile
├── go.mod
└── go.sum
```

## 6. Variáveis de Ambiente

```env
APP_ENV=production

# Database
DATABASE_URL=postgres://root:password@postgres:5432/payments_db

# RabbitMQ
RABBITMQ_URL=amqp://guest:guest@rabbitmq:5672/

# Gateway Integration
GATEWAY_API_URL=https://api.stripe.com/v1
GATEWAY_API_KEY=sk_test_...
GATEWAY_TIMEOUT_MS=5000
GATEWAY_RETRY_COUNT=3

# OpenTelemetry
OTEL_SERVICE_NAME=payment-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy:4317
OTEL_TRACES_SAMPLER=always_on
```

## 7. Dockerfile e Observabilidade OTel

### W3C Context Propagation e External API Tracing

O serviço de pagamentos faz chamadas externas HTTP. Utilizando OpenTelemetry, as requisições de saída devem usar `otelhttp.Transport` para garantir que o *Trace* continue até o Gateway (ou ao menos crie um span que rastreie latências externas e status codes).

```go
// Exemplo de configuração HTTP Client com OTel
client := &http.Client{
    Timeout:   time.Duration(cfg.GatewayTimeoutMs) * time.Millisecond,
    Transport: otelhttp.NewTransport(http.DefaultTransport),
}
```

Os logs estruturados JSON incluem informações vitais como a `idempotency_key`, `gateway_charge_id`, `trace_id` e `span_id`.

### Dockerfile

```dockerfile
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /go/bin/payment-worker ./cmd/worker/main.go

FROM gcr.io/distroless/static-debian12
COPY --from=builder /go/bin/payment-worker /payment-worker
EXPOSE 50055
USER nonroot:nonroot
ENTRYPOINT ["/payment-worker"]
```

## 8. Checklist de Produção

- [ ] Padrão de Idempotência implementado usando `idempotency_key` (UNIQUE index no PostgreSQL).
- [ ] Retries implementados (com backoff exponencial) via código ou via dead-letter com TTL.
- [ ] Conexões HTTP externas utilizam Timeouts rigorosos.
- [ ] Tratamento de falhas: circuit breaker e circuit opening caso o Gateway caia.
- [ ] `otelhttp` propagando span IDs na comunicação de saída.
- [ ] Credenciais e API Keys nunca armazenadas em logs, arquivos ou banco (mascaramento de dados sensíveis).
- [ ] ACID garantido durante inserção do status de sucesso/falha do pagamento.
- [ ] Publicador AMQP com Publisher Confirms garantindo que `notification.send` foi recebido pelo broker.
