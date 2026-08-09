# Event Service

## 1. Visão Geral e Domínio

O **Event Service** é o microsserviço central responsável pela gestão e consulta do catálogo de eventos, apresentações (shows), setores e pela busca textual de ingressos do Ticket Booking System. 
Desenvolvido em **Golang 1.23+**, este serviço expõe sua interface via **gRPC** na porta `:50053`.

Para garantir alta performance de leitura e flexibilidade estrutural, ele utiliza o **MongoDB 7** como *source of truth* (persistência principal) dos dados de eventos, permitindo modelos semiesquematizados para catálogos ricos. Para operações de busca textual avançada, filtros facetados (data, gênero, preço, localização) e *full-text search*, o serviço sincroniza dados com o **Elasticsearch 8**. Além disso, publica eventos de domínio (`event.created`, `event.updated`) no **RabbitMQ** para notificar outros componentes (como o `search-sync-worker`).

## 2. Protobuf Definition (`event.proto`)

A interface de comunicação síncrona com o FastAPI BFF (e outros serviços) é definida via gRPC Protobuf:

```protobuf
syntax = "proto3";

package event.v1;

option go_package = "github.com/observability-lab/event-service/pkg/pb;eventv1";

import "google/protobuf/timestamp.proto";

service EventService {
  rpc GetEvent (GetEventRequest) returns (GetEventResponse);
  rpc ListEvents (ListEventsRequest) returns (ListEventsResponse);
  rpc SearchEvents (SearchEventsRequest) returns (SearchEventsResponse);
  rpc CreateEvent (CreateEventRequest) returns (CreateEventResponse);
}

message Event {
  string id = 1;
  string title = 2;
  string description = 3;
  string category = 4;
  google.protobuf.Timestamp start_time = 5;
  google.protobuf.Timestamp end_time = 6;
  string location = 7;
  repeated Sector sectors = 8;
  string status = 9;
}

message Sector {
  string id = 1;
  string name = 2;
  int32 capacity = 3;
  double price = 4;
}

message GetEventRequest {
  string event_id = 1;
}

message GetEventResponse {
  Event event = 1;
}

message ListEventsRequest {
  int32 limit = 1;
  int32 offset = 2;
}

message ListEventsResponse {
  repeated Event events = 1;
  int32 total_count = 2;
}

message SearchEventsRequest {
  string query = 1;
  string category = 2;
  double min_price = 3;
  double max_price = 4;
}

message SearchEventsResponse {
  repeated Event events = 1;
  int32 total_hits = 2;
}

message CreateEventRequest {
  string title = 1;
  string description = 2;
  string category = 3;
  google.protobuf.Timestamp start_time = 4;
  google.protobuf.Timestamp end_time = 5;
  string location = 6;
  repeated Sector sectors = 7;
}

message CreateEventResponse {
  Event event = 1;
}
```

## 3. Arquitetura Interna Go

A arquitetura do serviço segue o padrão em camadas (Router/Transport → Controller/Handler → Service → Repository → Database) garantindo separação de responsabilidades.

```mermaid
graph TD
    subgraph "gRPC Transport"
        gRPC[gRPC Server :50053]
    end

    subgraph "Application Core"
        Handler[Event Handler / Controller]
        Service[Event Service Layer]
    end

    subgraph "Data Access / Integration"
        MongoRepo[MongoDB Repository]
        ESRepo[Elasticsearch Repository]
        RabbitPub[RabbitMQ Publisher]
    end

    subgraph "External Infrastructure"
        MongoDB[(MongoDB 7)]
        ES[(Elasticsearch 8)]
        RabbitMQ((RabbitMQ))
    end

    gRPC --> Handler
    Handler --> Service
    Service --> MongoRepo
    Service --> ESRepo
    Service --> RabbitPub

    MongoRepo --> MongoDB
    ESRepo --> ES
    RabbitPub --> RabbitMQ

    %% Observability Injection
    OTel[OpenTelemetry SDK] -.-> MongoRepo
    OTel -.-> ESRepo
    OTel -.-> gRPC
```

## 4. Modelo de Dados

### MongoDB Schema (BSON)

Os dados são armazenados na collection `events`.

```json
{
  "_id": "ObjectId('64c123abc456...')",
  "title": "Rock in Rio 2026",
  "description": "Maior festival de música do mundo",
  "category": "music_festival",
  "start_time": "ISODate('2026-09-15T18:00:00Z')",
  "end_time": "ISODate('2026-09-17T23:59:00Z')",
  "location": "Cidade do Rock, RJ",
  "sectors": [
    {
      "id": "sec-vip-01",
      "name": "Área VIP",
      "capacity": 5000,
      "price": 1500.00
    },
    {
      "id": "sec-pista-01",
      "name": "Pista",
      "capacity": 80000,
      "price": 450.00
    }
  ],
  "status": "published",
  "created_at": "ISODate('2026-01-01T10:00:00Z')",
  "updated_at": "ISODate('2026-01-01T10:00:00Z')"
}
```

### Elasticsearch Index Mapping

O index `events_idx` é projetado para buscas eficientes:

```json
{
  "mappings": {
    "properties": {
      "id": { "type": "keyword" },
      "title": { 
        "type": "text",
        "analyzer": "standard"
      },
      "description": { "type": "text" },
      "category": { "type": "keyword" },
      "start_time": { "type": "date" },
      "end_time": { "type": "date" },
      "location": { "type": "text" },
      "sectors": {
        "type": "nested",
        "properties": {
          "id": { "type": "keyword" },
          "name": { "type": "text" },
          "price": { "type": "double" }
        }
      },
      "min_price": { "type": "double" },
      "status": { "type": "keyword" }
    }
  }
}
```

## 5. Estrutura de Diretórios Go

```text
event-service/
├── cmd/
│   └── server/
│       └── main.go              # Entrypoint da aplicação
├── config/
│   └── config.go                # Carregamento de env vars (Viper)
├── internal/
│   ├── handler/
│   │   └── grpc_handler.go      # Implementação dos métodos do event.proto
│   ├── service/
│   │   └── event_service.go     # Regras de negócio (Service Layer)
│   ├── repository/
│   │   ├── mongodb_repo.go      # Repositório do MongoDB (mongo-go-driver)
│   │   └── elastic_repo.go      # Repositório do Elasticsearch
│   ├── publisher/
│   │   └── amqp_publisher.go    # Publicador RabbitMQ
│   └── model/
│       └── event.go             # Entidades de Domínio e tags BSON
├── pkg/
│   ├── pb/                      # Código gRPC gerado pelo protoc
│   └── logger/                  # Configuração de Logs estruturados (slog) com OTel
├── docker-compose.yml
├── Dockerfile
├── go.mod
└── go.sum
```

## 6. Variáveis de Ambiente

```env
# Application
APP_ENV=production
PORT=50053
LOG_LEVEL=info

# Database (MongoDB)
MONGO_URI=mongodb://root:password@mongodb:27017
MONGO_DB_NAME=ticket_system

# Search (Elasticsearch)
ELASTIC_URL=http://elasticsearch:9200
ELASTIC_INDEX=events_idx

# RabbitMQ
RABBITMQ_URL=amqp://guest:guest@rabbitmq:5672/
RABBITMQ_EXCHANGE=events.topic

# OpenTelemetry / Observability
OTEL_SERVICE_NAME=event-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy:4317
OTEL_TRACES_SAMPLER=always_on
```

## 7. Dockerfile e Observabilidade OTel

### OTel MongoDB & Elasticsearch Tracers

No código de repositório, é crucial injetar o contexto (Context) para garantir que as queries gerem Spans corretos no Grafana Tempo. O driver `go.mongodb.org/mongo-driver/mongo` requer o monitor OTel.

```go
// Exemplo de configuração OTel no mongo-driver
monitor := otelmongo.NewMonitor()
clientOpts := options.Client().ApplyURI(cfg.MongoURI).SetMonitor(monitor)
client, err := mongo.Connect(ctx, clientOpts)
```

Para Elasticsearch, injetamos um `Transport` OTel HTTP:
```go
// Exemplo de configuração OTel no elasticsearch client
esClient, err := elasticsearch.NewClient(elasticsearch.Config{
    Addresses: []string{cfg.ElasticURL},
    Transport: otelhttp.NewTransport(http.DefaultTransport),
})
```

### Dockerfile

```dockerfile
FROM golang:1.23-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /go/bin/event-service ./cmd/server/main.go

FROM gcr.io/distroless/static-debian12
COPY --from=builder /go/bin/event-service /event-service

EXPOSE 50053
USER nonroot:nonroot
ENTRYPOINT ["/event-service"]
```

## 8. Checklist de Produção

- [ ] Tracing distribuído OTel ativo (W3C Trace Context propagating).
- [ ] MongoDB monitorado pelo `otelmongo`.
- [ ] Queries do Elasticsearch utilizando contexto e otelhttp.
- [ ] Índices do MongoDB criados adequadamente (ex: `category`, `status`).
- [ ] Conexões MongoDB e Elasticsearch gerenciadas com pool otimizado e timeouts bem definidos.
- [ ] Logs JSON estruturados emitindo `trace_id` e `correlation_id`.
- [ ] Métricas RED exportadas (Prometheus/OTel) para chamadas gRPC e DB calls.
- [ ] Circuit Breaker configurado para chamadas ao Elasticsearch.
- [ ] Publicação assíncrona no RabbitMQ utilizando Publisher Confirms.
