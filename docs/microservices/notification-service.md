# Notification Service

## 1. Visão Geral e Canais Suportados
O **Notification Service** é um microsserviço assíncrono desenvolvido em Golang, responsável pelo envio de notificações multicanal (Email, SMS, Push Notifications) e pelo registro de auditoria no ecossistema do *Ticket Booking System*. Ele processa mensagens do RabbitMQ e persiste o histórico e status de entrega no MongoDB.

Canais suportados:
- **Email**: Confirmação de pedidos de ingressos, recuperação de senha, alertas de segurança.
- **SMS**: Alertas críticos, 2FA, notificações de última hora (mudança de horário do evento).
- **Push Notification**: Atualizações em tempo real no app mobile.

## 2. Arquitetura de Consumo Assíncrono

```mermaid
graph TD
    A[Orders/Payment Service] -->|Publish AMQP| B((RabbitMQ Topic Exchange))
    B -->|Routing Key: notification.*| C[Queue: notification.send]
    
    C -->|Consume AMQP| D[Notification Service]
    
    D --> E{Channel Router}
    E -->|Email| F[Email Provider SMTP/API]
    E -->|SMS| G[SMS Gateway Twilio/SNS]
    E -->|Push| H[Push Gateway FCM/APNs]
    
    F & G & H --> I[Status Update]
    I --> J[(MongoDB)]
    
    D -->|Failure/Max Retries| K[Queue: notification.dlx]
```

## 3. Integração RabbitMQ

- **Fila Principal**: `notification.send`
- **Exchange**: `events.topic`
- **Dead Letter Exchange (DLX)**: `notification.dlx.exchange`
- **Dead Letter Queue (DLQ)**: `notification.dlx`

O serviço implementa Publisher Confirms, prefetch count ajustado e requeue controlado. Erros não recuperáveis ou timeout levam a mensagem para a DLQ.

## 4. Modelo de Dados MongoDB

Os dados de notificação e logs de auditoria são armazenados em coleções no MongoDB.

### Coleção `notifications`
```json
{
  "_id": "ObjectId",
  "user_id": "uuid",
  "order_id": "uuid",
  "channel": "EMAIL",
  "type": "ORDER_CONFIRMATION",
  "status": "SENT",
  "recipient": "user@example.com",
  "payload": {
    "subject": "Sua compra foi confirmada!",
    "body": "..."
  },
  "created_at": "ISODate",
  "sent_at": "ISODate",
  "error_reason": null
}
```

### Coleção `audit_logs`
```json
{
  "_id": "ObjectId",
  "entity": "Notification",
  "entity_id": "ObjectId",
  "action": "SEND_ATTEMPT",
  "actor": "system",
  "timestamp": "ISODate",
  "metadata": {
    "trace_id": "...",
    "correlation_id": "..."
  }
}
```

## 5. Estrutura de Diretórios Go

```text
notification-service/
├── cmd/
│   └── notification/
│       └── main.go
├── internal/
│   ├── config/
│   ├── consumer/
│   │   └── amqp.go
│   ├── service/
│   │   └── notification.go
│   ├── provider/
│   │   ├── email/
│   │   ├── sms/
│   │   └── push/
│   ├── repository/
│   │   └── mongodb.go
│   └── model/
├── pkg/
│   ├── otel/
│   └── logger/
├── go.mod
├── go.sum
└── Dockerfile
```

## 6. Variáveis de Ambiente

| Variável | Descrição | Exemplo |
|---|---|---|
| `APP_ENV` | Ambiente de execução | `production` |
| `RABBITMQ_URL` | URL de conexão AMQP | `amqp://user:pass@rabbitmq:5672/` |
| `MONGODB_URI` | String de conexão MongoDB | `mongodb://user:pass@mongodb:27017` |
| `MONGODB_DATABASE` | Nome do banco | `notifications_db` |
| `SMTP_HOST` | Host do provedor de e-mail | `smtp.mailgun.org` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Endpoint OTLP (Alloy/Tempo) | `http://alloy:4317` |

## 7. Dockerfile Multi-stage

```dockerfile
# Build stage
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o notification-service ./cmd/notification/main.go

# Run stage
FROM alpine:3.19
WORKDIR /app
COPY --from=builder /app/notification-service .
RUN adduser -D -g '' appuser
USER appuser
CMD ["./notification-service"]
```

## 8. Observabilidade OTel

O Notification Service extrai o W3C Trace Context dos headers das mensagens AMQP recebidas.
Isso garante a continuidade do trace originado lá no cliente ou BFF.

```go
// Exemplo de extração de contexto AMQP
ctx := otel.GetTextMapPropagator().Extract(context.Background(), amqpPropagationFormat{msg.Headers})
ctx, span := tracer.Start(ctx, "process_notification")
defer span.End()
```

Logs são ejetados via estruturação JSON contendo `trace_id` e `correlation_id` para o Loki.

## 9. Checklist de Produção

- [ ] Consumidores configurados com `PrefetchCount` adequado.
- [ ] Retentativas configuradas com *Exponential Backoff*.
- [ ] DLX configurada e monitorada com alertas no Grafana.
- [ ] Conexão MongoDB com Pool devidamente dimensionado.
- [ ] Instrumentação OTLP validando a correlação cruzada de Logs, Traces e Metrics.
