# Guia de Integração de Microsserviços e Tracing Distribuído

Este é o **guia definitivo** para integrar qualquer microsserviço (desenvolvido em **Golang**, **Python**, ou qualquer linguagem suportada por OpenTelemetry) ao ecossistema do **Observability Lab**.

---

## 🏛️ 1. Como Funciona o Pipeline de Telemetria

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                       PIPELINE DE TELEMETRIA OPENTELEMETRY                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   [Seu Microsserviço] (Go / Python / Node)                                  │
│   ├─ OpenTelemetry SDK integrado                                            │
│   ├─ Gera Spans (Traces), Métricas RED e Logs estruturados                  │
│   │                                                                         │
│   ▼ OTLP gRPC (:4317) / OTLP HTTP (:4318)                                  │
│                                                                             │
│   [Grafana Alloy DaemonSet]                                                 │
│   (Roda em cada nó do K3s em alloy.observability.svc.cluster.local)         │
│   │                                                                         │
│   ├─ Traces (OTLP)     ──► Grafana Tempo (:4317) (Armazena no HDD 1TB)      │
│   ├─ Métricas (PromQL) ──► Grafana Mimir (:8080) (Remote Write no HDD)      │
│   └─ Logs (OTLP)       ──► Grafana Loki  (:3100) (Chunks no HDD)            │
│                                                                             │
│   ▼ Visualização Unificada                                                  │
│   [Grafana Dashboards & Tempo TraceQL]                                      │
│   • Trace ponta a ponta correlacionado com Logs e Métricas                  │
│   • Node Graph visual de dependências entre serviços                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🔑 2. Padrão de Propagação de Contexto (W3C & Correlation ID)

Para que uma requisição possa ser rastreada do início ao fim através de múltiplos microsserviços, ela **deve propagar dois identificadores**:

1. **W3C Trace Context (`traceparent`):**
   - Formato: `00-<trace-id>-<span-id>-01` (ex: `00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`).
   - Propagado automaticamente pelo SDK via cabeçalhos HTTP, metadados gRPC e headers AMQP.
2. **Correlation ID (`X-Correlation-ID`):**
   - UUID v4 propagado publicamente para clientes, logs e telas de suporte.

---

## 🐹 3. Implementação em Golang (gRPC + HTTP + AMQP)

### 3.1 Dependências Go
```bash
go get go.opentelemetry.io/otel \
       go.opentelemetry.io/otel/sdk \
       go.opentelemetry.io/otel/trace \
       go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc \
       go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc \
       go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp
```

### 3.2 Inicialização do Tracer Provider (`telemetry.go`)
```go
package telemetry

import (
	"context"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func InitTelemetry(ctx context.Context, serviceName string) (*sdktrace.TracerProvider, error) {
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		endpoint = "alloy.observability.svc.cluster.local:4317"
	}

	// 1. Configura o exportador OTLP via gRPC
	exporter, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithInsecure(),
		otlptracegrpc.WithEndpoint(endpoint),
		otlptracegrpc.WithDialOption(grpc.WithTransportCredentials(insecure.NewCredentials())),
	)
	if err != nil {
		return nil, err
	}

	// 2. Metadados do recurso (nome do serviço)
	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceNameKey.String(serviceName),
			semconv.ServiceVersionKey.String("1.0.0"),
		),
	)
	if err != nil {
		return nil, err
	}

	// 3. Provedor de Trace com Batching
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.AlwaysSample()), // 100% amostragem em dev/lab
	)
	otel.SetTracerProvider(tp)

	// 4. Configura os propagadores W3C padrão globalmente
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	return tp, nil
}
```

### 3.3 Instrumentação de Servidor e Cliente gRPC
```go
import (
	"go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc"
	"google.golang.org/grpc"
)

// No Servidor gRPC:
func StartGRPCServer() {
	server := grpc.NewServer(
		grpc.StatsHandler(otelgrpc.NewServerHandler()), // Tracing automático de todas as chamadas
	)
	// Registre seus serviços aqui...
}

// No Cliente gRPC:
func NewGRPCClient(target string) (*grpc.ClientConn, error) {
	return grpc.NewClient(target,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithStatsHandler(otelgrpc.NewClientHandler()), // Injeta trace context automaticamente
	)
}
```

### 3.4 Criando Spans Manuais e Registrando Erros
```go
import (
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
)

func ProcessOrder(ctx context.Context, orderID string) error {
	tracer := otel.Tracer("orders-service")
	ctx, span := tracer.Start(ctx, "ProcessOrder")
	defer span.End()

	// Adicione atributos de negócio (anonimizados, sem senhas/cartões)
	span.SetAttributes(
		attribute.String("order.id", orderID),
		attribute.String("db.system", "postgresql"),
	)

	if err := db.Save(ctx, orderID); err != nil {
		// Registra o erro no span para aparecer vermelho no Grafana
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return err
	}

	return nil
}
```

### 3.5 Propagação de Trace via RabbitMQ (AMQP)
```go
import (
	"context"
	amqp "github.com/rabbitmq/amqp091-go"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
)

// Ao Publicar: Injeta o Trace Context nos headers da mensagem AMQP
func PublishMessage(ctx context.Context, ch *amqp.Channel, body []byte) error {
	headers := make(amqp.Table)
	propagator := otel.GetTextMapPropagator()
	propagator.Inject(ctx, &amqpTableCarrier{headers})

	return ch.PublishWithContext(ctx, "events", "order.created", false, false, amqp.Publishing{
		ContentType: "application/json",
		Headers:     headers,
		Body:        body,
	})
}

// Ao Consumir: Extrai o Trace Context para continuar o mesmo trace
func ConsumeMessage(ctx context.Context, msg amqp.Delivery) {
	propagator := otel.GetTextMapPropagator()
	ctx = propagator.Extract(ctx, &amqpTableCarrier{msg.Headers})

	tracer := otel.Tracer("order-worker")
	ctx, span := tracer.Start(ctx, "HandleOrderCreated")
	defer span.End()

	// Seu processamento de negócio continua sob o mesmo Trace ID!
}

// Adaptador TextMapCarrier para amqp.Table
type amqpTableCarrier struct{ amqp.Table }
func (c *amqpTableCarrier) Get(key string) string {
	if v, ok := c.Table[key]; ok { return v.(string) }
	return ""
}
func (c *amqpTableCarrier) Set(key, val string) { c.Table[key] = val }
func (c *amqpTableCarrier) Keys() []string {
	keys := make([]string, 0, len(c.Table))
	for k := range c.Table { keys = append(keys, k) }
	return keys
}
```

---

## 🐍 4. Implementação em Python (FastAPI)

### 4.1 Dependências Python
```bash
pip install opentelemetry-api \
            opentelemetry-sdk \
            opentelemetry-exporter-otlp-proto-grpc \
            opentelemetry-instrumentation-fastapi \
            opentelemetry-instrumentation-httpx
```

### 4.2 Inicialização no FastAPI (`main.py`)
```python
import os
import uuid
from fastapi import FastAPI, Request
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor

service_name = os.getenv("OTEL_SERVICE_NAME", "fastapi-bff")
otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "alloy.observability.svc.cluster.local:4317")

# 1. Configura Provedor e Exportador
resource = Resource.create(attributes={"service.name": service_name})
provider = TracerProvider(resource=resource)
exporter = OTLPSpanExporter(endpoint=otlp_endpoint, insecure=True)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)

app = FastAPI(title=service_name)

# 2. Middleware para Correlation ID e Trace Context
@app.middleware("http")
async def correlation_id_middleware(request: Request, call_next):
    correlation_id = request.headers.get("X-Correlation-ID", str(uuid.uuid4()))
    response = await call_next(request)
    response.headers["X-Correlation-ID"] = correlation_id
    return response

# 3. Auto-instrumentação FastAPI e HTTPX
FastAPIInstrumentor.instrument_app(app)
HTTPXClientInstrumentor().instrument()

@app.get("/health")
def health():
    return {"status": "ok", "service": service_name}
```

---

## 📦 5. Manifesto Kubernetes Padrão (`k8s/apps/<servico>/`)

Todo serviço adicionado ao K3s deve possuir um `deployment.yaml` com as variáveis OTel injetadas:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: meu-servico
  namespace: apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: meu-servico
  template:
    metadata:
      labels:
        app: meu-servico
    spec:
      imagePullSecrets:
        - name: dockerhub-registry-credentials
      containers:
        - name: meu-servico
          image: <SEU_DOCKERHUB_USER>/meu-servico:latest
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
              name: http
          env:
            # 🔴 Variáveis de Telemetria Obrigatórias:
            - name: OTEL_SERVICE_NAME
              value: "meu-servico"
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: "http://alloy.observability.svc.cluster.local:4317"
            - name: OTEL_EXPORTER_OTLP_PROTOCOL
              value: "grpc"
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 250m
              memory: 256Mi
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: meu-servico
  namespace: apps
spec:
  selector:
    app: meu-servico
  ports:
    - port: 8080
      targetPort: 8080
      name: http
```

---

## 🔍 6. Como Visualizar os Traces no Grafana / Tempo

1. Acesse o Grafana: **`http://<SEU_TAILSCALE_HOST>/grafana/`**
2. No menu lateral, clique em **Explore** (ícone da bússola).
3. Selecione a fonte de dados **Tempo**.
4. Na aba de busca:
   - **Service Name:** Selecione o seu serviço (ex: `fastapi-bff` ou `auth-service`).
   - Clique em **Run query**.
5. Clique em qualquer Trace da lista para abrir o **Waterfall Diagram**:
   - Você verá exatamente cada etapa da requisição, duração de cada span e chamadas de banco de dados.
   - Clique na aba **Node Graph** para ver o gráfico interativo de conexões entre os microsserviços.
   - Clique no botão **Logs for this span** para abrir na hora os logs no Loki filtrados pelo `TraceID` correspondente.
