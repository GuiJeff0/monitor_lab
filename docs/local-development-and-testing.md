# Guia de Desenvolvimento e Testes Locais

Este guia explica como testar, depurar e validar serviços rodando no cluster K3s no ambiente de laboratório (`creedx66`), bem como na sua máquina pessoal de desenvolvimento conectada via rede mesh (Tailscale).

---

## 1. Conexão e Acesso ao Cluster

### Acesso via Tailscale (Recomendado)
Se a sua máquina de desenvolvimento estiver na mesma rede Tailnet, você tem acesso direto aos serviços utilizando o endereço MagicDNS do servidor:

| Serviço | URL | Credenciais Padrão |
|---|---|---|
| **Portainer CE** | `http://<SEU_TAILSCALE_HOST>/portainer/` | Definidas no 1º acesso |
| **Grafana UI** | `http://<SEU_TAILSCALE_HOST>/grafana/` | `admin` / `<GRAFANA_PASSWORD>` |
| **Traefik Dashboard** | `http://<SEU_TAILSCALE_HOST>:8080/dashboard/` | Acesso direto na Tailnet |
| **API Gateway (BFF)** | `http://<SEU_TAILSCALE_HOST>/api/v1/` | Endpoints públicos da API |

---

## 2. Testando com `kubectl` e Port-Forwarding

Para testar serviços internos que **não estão expostos** via Ingress (por exemplo: PostgreSQL, MongoDB, Mimir, Loki, Tempo):

### Redirecionamento de Portas para sua Máquina Local:
```bash
# Redirecionar o Mimir (Prometheus/TSDB) para porta 8080 local:
kubectl port-forward -n observability svc/mimir 8080:8080

# Redirecionar o Loki (Logs) para porta 3100 local:
kubectl port-forward -n observability svc/loki 3100:3100

# Redirecionar o Tempo (Traces OTLP) para porta 4317 local:
kubectl port-forward -n observability svc/tempo 4317:4317

# Redirecionar o PostgreSQL para porta 5432 local:
kubectl port-forward -n data svc/postgres 5432:5432
```

---

## 3. Testando Endpoints via `curl` no Terminal

### Teste de Saúde do Grafana:
```bash
curl -s http://localhost/grafana/api/health
# Resposta esperada: {"database": "ok", "version": "..."}
```

### Teste de Prontidão do Mimir:
```bash
curl -s http://mimir.observability.svc.cluster.local:8080/ready
# ou via port-forward:
curl -s http://localhost:8080/ready
# Resposta esperada: ready
```

### Teste de Prontidão do Loki:
```bash
curl -s http://loki.observability.svc.cluster.local:3100/ready
# Resposta esperada: ready
```

---

## 4. Como Executar Comandos e Depurar Dentro de Pods

### Abrir um terminal interativo dentro de um Pod:
```bash
# Listar pods
kubectl get pods -A

# Entrar no shell do Pod
kubectl exec -it -n apps <NOME_DO_POD> -- /bin/sh
```

### Fazer requisições de rede dentro do cluster para testar DNS:
```bash
# Executar um curl temporário dentro do cluster
kubectl run debug-curl --rm -i --tty --image=curlimages/curl -- /bin/sh

# Dentro do container debug:
curl -I http://mimir.observability.svc.cluster.local:8080/ready
curl -I http://loki.observability.svc.cluster.local:3100/ready
```

---

## 5. Visualizando Logs e Métricas Locais

### Logs ao vivo pelo terminal:
```bash
# Logs do coletor Alloy:
kubectl logs -n observability daemonset/alloy -f

# Logs do Traefik Ingress:
kubectl logs -n ingress deployment/traefik -f

# Logs de um microsserviço:
kubectl logs -n apps deployment/fastapi-bff -f
```

### Acompanhando Métricas no Grafana:
1. Abra `http://<SEU_TAILSCALE_HOST>/grafana/explore`.
2. Selecione a fonte de dados **Mimir**.
3. Rode consultas PromQL de teste:
   ```promql
   # Taxa de requisições HTTP do Traefik
   rate(traefik_service_requests_total[1m])

   # Uso de CPU dos pods
   sum by (pod) (rate(container_cpu_usage_seconds_total[1m]))
   ```
