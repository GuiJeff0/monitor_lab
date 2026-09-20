# Stack de Observabilidade LGTM (`k8s/observability`)

Este diretório gerencia a infraestrutura de telemetria completa (Métricas, Logs e Traces) baseada na stack Grafana LGTM + OpenTelemetry.

## Componentes

- **`alloy.yaml`**: DaemonSet coletor unificado (OTLP gRPC :4317, HTTP :4318, logs de Pods via `/var/log/pods`, Node Exporter e cAdvisor). Injeta automaticamente os identificadores multi-tenant (`X-Scope-OrgID: platform`).
- **`loki.yaml`**: Agregador de logs estruturados (Porta 3100 HTTP / 9095 gRPC), armazenamento no HDD (`local-hdd`), com compactor e retenção de 7 dias (`168h`). Multi-tenancy habilitado (`auth_enabled: true`).
- **`mimir.yaml`**: TSDB escalável compatível com Prometheus (Porta 8080 HTTP / 9095 gRPC), armazenamento no HDD (`local-hdd`), compactor e retenção de 30 dias. Multi-tenancy habilitado (`multitenancy_enabled: true`).
- **`tempo.yaml`**: Distributed Tracing com TraceQL (Porta 3200 HTTP / 4317 gRPC / 4318 HTTP), armazenamento no HDD (`local-hdd`), gerador de métricas e retenção de 7 dias.
- **`network-policy.yaml`**: Isolamento de tráfego de rede — restringe acesso exclusivamente aos namespaces `ingress` (Grafana UI), `apps` (OTLP) e `kube-system` (probes).
- **`grafana-admin.enc.yaml`**: Secret criptografado com SOPS contendo as credenciais de admin do Grafana.
