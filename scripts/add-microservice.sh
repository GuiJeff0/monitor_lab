#!/usr/bin/env bash
# ==============================================================================
# Script de Scaffold para Novos Microsserviços no Observability Lab
# Uso:
#   ./scripts/add-microservice.sh <nome-do-servico> [porta] [protocolo: http|grpc] [usuario-dockerhub]
# Exemplo:
#   ./scripts/add-microservice.sh auth-service 50051 grpc creedx66
# ==============================================================================

set -euo pipefail

# Diretório raiz do repositório
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SERVICE_NAME="${1:-}"
SERVICE_PORT="${2:-8080}"
SERVICE_PROTOCOL="${3:-http}"
DOCKERHUB_USER="${4:-creedx66}"

if [ -z "$SERVICE_NAME" ]; then
    echo "❌ Erro: Nome do serviço é obrigatório."
    echo "Uso: $0 <nome-do-servico> [porta=8080] [protocolo=http|grpc] [usuario-dockerhub=creedx66]"
    echo "Exemplo: $0 auth-service 50051 grpc creedx66"
    exit 1
fi

TARGET_DIR="${REPO_ROOT}/k8s/apps/${SERVICE_NAME}"
TARGET_FILE="${TARGET_DIR}/deployment.yaml"
KUSTOMIZATION_FILE="${REPO_ROOT}/k8s/kustomization.yaml"

echo "🚀 Criando scaffold do microsserviço: ${SERVICE_NAME}"
echo "   - Porta: ${SERVICE_PORT}"
echo "   - Protocolo: ${SERVICE_PROTOCOL}"
echo "   - Imagem inicial: ${DOCKERHUB_USER}/${SERVICE_NAME}:latest"

mkdir -p "$TARGET_DIR"

# Configura probe de acordo com protocolo
if [ "$SERVICE_PROTOCOL" = "grpc" ]; then
    OTEL_PROTOCOL="grpc"
    PROBE_BLOCK="          livenessProbe:
            tcpSocket:
              port: ${SERVICE_PORT}
            initialDelaySeconds: 15
            periodSeconds: 15
          readinessProbe:
            tcpSocket:
              port: ${SERVICE_PORT}
            initialDelaySeconds: 5
            periodSeconds: 10"
else
    OTEL_PROTOCOL="grpc"
    PROBE_BLOCK="          livenessProbe:
            httpGet:
              path: /health
              port: ${SERVICE_PORT}
            initialDelaySeconds: 15
            periodSeconds: 15
          readinessProbe:
            httpGet:
              path: /health
              port: ${SERVICE_PORT}
            initialDelaySeconds: 5
            periodSeconds: 10"
fi

cat <<EOF > "$TARGET_FILE"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${SERVICE_NAME}
  namespace: apps
  labels:
    app: ${SERVICE_NAME}
    tier: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${SERVICE_NAME}
  template:
    metadata:
      labels:
        app: ${SERVICE_NAME}
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      imagePullSecrets:
        - name: dockerhub-registry-credentials
      containers:
        - name: ${SERVICE_NAME}
          image: ${DOCKERHUB_USER}/${SERVICE_NAME}:latest
          imagePullPolicy: IfNotPresent
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
          volumeMounts:
            - name: tmp
              mountPath: /tmp
          ports:
            - containerPort: ${SERVICE_PORT}
              name: ${SERVICE_PROTOCOL}
          env:
            # 🔴 Observabilidade: Telemetria OpenTelemetry -> Grafana Alloy
            - name: OTEL_SERVICE_NAME
              value: "${SERVICE_NAME}"
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: "http://alloy.observability.svc.cluster.local:4317"
            - name: OTEL_EXPORTER_OTLP_PROTOCOL
              value: "${OTEL_PROTOCOL}"
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 250m
              memory: 256Mi
${PROBE_BLOCK}
      volumes:
        - name: tmp
          emptyDir:
            medium: Memory
            sizeLimit: 64Mi
---
apiVersion: v1
kind: Service
metadata:
  name: ${SERVICE_NAME}
  namespace: apps
  labels:
    app: ${SERVICE_NAME}
spec:
  selector:
    app: ${SERVICE_NAME}
  ports:
    - port: ${SERVICE_PORT}
      targetPort: ${SERVICE_PORT}
      name: ${SERVICE_PROTOCOL}
EOF

echo "✅ Manifesto criado em: ${TARGET_FILE}"

# Adiciona no k8s/kustomization.yaml se ainda não estiver presente
RESOURCE_ENTRY="  - apps/${SERVICE_NAME}/deployment.yaml"
if grep -q "apps/${SERVICE_NAME}/deployment.yaml" "$KUSTOMIZATION_FILE"; then
    echo "ℹ️  O manifesto já está registrado em k8s/kustomization.yaml."
else
    echo "📝 Registrando ${SERVICE_NAME} em k8s/kustomization.yaml..."
    # Adiciona a entrada na lista de resources
    echo "$RESOURCE_ENTRY" >> "$KUSTOMIZATION_FILE"
    echo "✅ Registrado com sucesso no k8s/kustomization.yaml!"
fi

echo ""
echo "🎉 Tudo pronto! Próximos passos:"
echo "1. No repositório do microsserviço (${SERVICE_NAME}):"
echo "   - Adicione o workflow .github/workflows/ci-cd.yml (template em templates/microservice-ci-cd.yml)"
echo "   - Configure os secrets DOCKERHUB_USERNAME, DOCKERHUB_TOKEN e MONITOR_LAB_PAT"
echo "2. No repositório monitor_lab:"
echo "   - Faça commit das alterações: git add k8s/apps/${SERVICE_NAME} k8s/kustomization.yaml"
echo "   - git commit -m 'feat(k8s): add ${SERVICE_NAME} deployment manifest'"
echo "   - git push origin main"
echo "   - O Flux CD sincronizará automaticamente o novo serviço no K3s!"

