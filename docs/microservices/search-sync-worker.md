# Search Sync Worker

## 1. Visão Geral e Estratégia de Sincronização
O **Search Sync Worker** é um processo em Golang cuja função é consumir eventos de alteração (Domain Events) provenientes dos serviços primários (via RabbitMQ) e refleti-los de maneira estruturada no Elasticsearch 8.
Isso garante que o catálogo de eventos permaneça disponível para buscas *full-text* e consultas facetadas de alta performance e baixa latência sem sobrecarregar os bancos transacionais (PostgreSQL/MongoDB).

## 2. Pipeline de Dados

```mermaid
graph LR
    A[Event/Orders Service] -->|Domain Events\nevent.updated/seats.changed| B((RabbitMQ Topic))
    B --> C[Queue: search.sync]
    
    C -->|Consume| D[Search Sync Worker]
    
    D -->|Transform/Enrich| E{Data Mapper}
    
    E -->|Bulk Upsert| F[(Elasticsearch 8)]
    
    D -->|Ack/Nack| C
```

## 3. Mapeamento do Índice Elasticsearch

O índice `events` é otimizado para *geospatial search*, auto-complete e *term aggregations*.

```json
PUT /events
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 2,
    "analysis": {
      "analyzer": {
        "autocomplete": {
          "tokenizer": "autocomplete",
          "filter": ["lowercase"]
        }
      },
      "tokenizer": {
        "autocomplete": {
          "type": "edge_ngram",
          "min_gram": 2,
          "max_gram": 10,
          "token_chars": ["letter"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "id": { "type": "keyword" },
      "title": { 
        "type": "text",
        "analyzer": "autocomplete",
        "search_analyzer": "standard"
      },
      "description": { "type": "text" },
      "location": { "type": "geo_point" },
      "date": { "type": "date" },
      "category": { "type": "keyword" },
      "available_seats": { "type": "integer" },
      "price_range": {
        "properties": {
          "min": { "type": "scaled_float", "scaling_factor": 100 },
          "max": { "type": "scaled_float", "scaling_factor": 100 }
        }
      }
    }
  }
}
```

## 4. Padrão de Idempotência e Tratamento de Erros

Devido à natureza *At-Least-Once Delivery* do RabbitMQ, a idempotência é crítica. O Elasticsearch utiliza *Optimistic Concurrency Control* ou *External Versioning*.
Documentos possuem um `version` atrelado ao `updated_at` (timestamp) ou número sequencial da transação original, prevenindo que um evento desatualizado sobrescreva um mais recente (Out-of-Order Delivery).

Erros de mapeamento ou conectividade enviam a mensagem para uma DLQ após o esgotamento de retentativas.

## 5. Estrutura de Diretórios Go

```text
search-sync-worker/
├── cmd/
│   └── worker/
│       └── main.go
├── internal/
│   ├── config/
│   ├── consumer/
│   │   └── amqp.go
│   ├── indexer/
│   │   └── elasticsearch.go
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
| `RABBITMQ_URL` | URL de conexão AMQP | `amqp://user:pass@rabbitmq:5672/` |
| `ELASTICSEARCH_URL` | Endpoint do cluster ES | `http://elasticsearch:9200` |
| `ELASTICSEARCH_INDEX` | Nome do índice alvo | `events` |
| `SYNC_BATCH_SIZE` | Tamanho do batch para Bulk API | `500` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Endpoint OTLP | `http://alloy:4317` |

## 7. Dockerfile Multi-stage

```dockerfile
# Build stage
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o sync-worker ./cmd/worker/main.go

# Run stage
FROM alpine:3.19
WORKDIR /app
COPY --from=builder /app/sync-worker .
RUN adduser -D -g '' worker
USER worker
CMD ["./sync-worker"]
```

## 8. Observabilidade OTel

O worker deve exportar métricas fundamentais:
- `search_sync_events_processed_total`: Contador de eventos processados.
- `search_sync_batch_size_histogram`: Histograma do tamanho do batch do Bulk API.
- `search_sync_latency_ms`: Duração do processamento de indexação.

Como este é um processo de *background*, o `trace_id` continua das mensagens recebidas e finaliza nos *spans* de chamadas da API Bulk do Elasticsearch.

## 9. Checklist de Produção

- [ ] Mapeamento do índice ES aplicado com analyzers corretos.
- [ ] Controle de versão externo no Elasticsearch garantindo idempotência.
- [ ] Processamento com Bulk API para alta taxa de transferência (Throughput).
- [ ] Configuração de Dead Letter Exchange em caso de mensagens *poison pill*.
- [ ] Dashboard RED mapeado no Grafana via OTLP.
