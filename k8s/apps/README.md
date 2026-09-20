# Microsserviços de Aplicação (`k8s/apps`)

Este diretório gerencia os manifests de implantação dos microsserviços do ecossistema no namespace `apps`.

## Estrutura

- **`_template/`**: Molde canônico contendo boas práticas de segurança:
  - `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `drop: ALL`.
  - Injeção das variáveis padrão do OpenTelemetry SDK (`OTEL_EXPORTER_OTLP_ENDPOINT`).
  - Probes de liveness e readiness pré-configuradas.
  - ImagePullSecrets configurado para o Docker Hub.
- **`<servico>/deployment.yaml`**: Cada microsserviço adicionado via `scripts/add-microservice.sh` terá seu próprio subdiretório e manifesto aqui.
