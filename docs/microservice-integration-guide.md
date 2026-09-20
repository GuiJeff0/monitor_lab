# Guia de Integração e Deploy de Microsserviços

Este guia orienta o desenvolvimento, instrumentação com **OpenTelemetry (OTel SDK)** e deploy de novos microsserviços no cluster K3s utilizando o fluxo de **CI/CD com Docker Hub e Flux CD**.

---

## 1. Padrão de Instrumentação OpenTelemetry (OTel SDK)

Todo microsserviço deve exportar telemetria (Métricas, Logs e Traces) para o **Grafana Alloy** via protocolo OTLP (porta `4317` gRPC ou `4318` HTTP).

### Variáveis de Ambiente Obrigatórias
Ao rodar no cluster K3s, configure as seguintes variáveis no manifesto de `Deployment`:

```yaml
env:
  - name: OTEL_SERVICE_NAME
    value: "auth-service"             # Nome exclusivo do serviço
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://alloy.observability.svc.cluster.local:4317"
  - name: OTEL_EXPORTER_OTLP_PROTOCOL
    value: "grpc"
```

---

## 2. Exemplo de Código: Golang (gRPC) com OpenTelemetry

```go
package main

import (
	"context"
	"log"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func initTracer(ctx context.Context, serviceName string) (*sdktrace.TracerProvider, error) {
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		endpoint = "alloy.observability.svc.cluster.local:4317"
	}

	exporter, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithInsecure(),
		otlptracegrpc.WithEndpoint(endpoint),
		otlptracegrpc.WithDialOption(grpc.WithTransportCredentials(insecure.NewCredentials())),
	)
	if err != nil {
		return nil, err
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceNameKey.String(serviceName),
		)),
	)
	otel.SetTracerProvider(tp)
	return tp, nil
}
```

---

## 3. Exemplo de Código: Python (FastAPI) com OpenTelemetry

```python
import os
from fastapi import FastAPI
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.resources import Resource

service_name = os.getenv("OTEL_SERVICE_NAME", "fastapi-bff")
otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://alloy.observability.svc.cluster.local:4317")

# Configura o provedor de trace OTel
resource = Resource.create(attributes={"service.name": service_name})
provider = TracerProvider(resource=resource)
processor = BatchSpanProcessor(OTLPSpanExporter(endpoint=otlp_endpoint, insecure=True))
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)

app = FastAPI(title=service_name)
FastAPIInstrumentor.instrument_app(app)

@app.get("/health")
def health():
    return {"status": "healthy", "service": service_name}
```

---

## 4. Manifesto de Deploy no Kubernetes (`k8s/apps/<servico>/`)

Crie o arquivo `deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: meu-servico
  namespace: apps
  labels:
    app: meu-servico
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
          imagePullPolicy: Always
          ports:
            - containerPort: 50051
              name: grpc
          env:
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
    - port: 50051
      targetPort: 50051
      name: grpc
```

---

## 5. Fluxo de Publicação e Deploy (GitOps)

```text
[Desenvolvedor] ──► git push origin main
       │
       ▼
[GitHub Actions] (CI)
       ├─ Roda testes unitários
       ├─ Build da imagem Docker
       └─ docker push <USER>/meu-servico:latest (Docker Hub)
       │
       ▼
[Flux CD no K3s] (CD)
       ├─ Detecta nova alteração em k8s/apps/
       ├─ Reconcilia o cluster automaticamente
       └─ O K3s baixa a nova imagem usando o secret 'dockerhub-registry-credentials'
```
