# Guia de Migração para K3s com Terraform, Observabilidade e GitOps

Este documento detalha o passo a passo para inicializar e operar a infraestrutura Kubernetes (K3s) gerenciada por Terraform no servidor `creedx66`.

---

## 🏛️ Visão Geral da Infraestrutura

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ARQUITETURA K3S + GITOPS                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  [Developer] ──► git push (GitHub)                                          │
│        │                                                                    │
│        ├─► GitHub Actions (CI) ──► Build Docker Image ──► Docker Hub        │
│        │                                                                    │
│        └─► Flux CD (GitOps)                                                 │
│              │ (reconciliação a cada 1m)                                    │
│              ├─ Decripta Secrets criptografados com SOPS (chave age)        │
│              └─ Aplica Deployments, Services, IngressRoutes no K3s          │
│                                                                             │
│  [Usuário / Tailscale]                                                      │
│        │                                                                    │
│        ▼ :80 / :443                                                         │
│   Traefik v3 Ingress Controller                                             │
│        ├─ /grafana/*   ──► Grafana (LGTM Stack)                             │
│        ├─ /portainer/* ──► Portainer CE (Gerenciador Visual do K3s)         │
│        └─ /api/v1/*    ──► FastAPI BFF ──► gRPC Microservices               │
│                                                                             │
│  [Observabilidade & Telemetria]                                             │
│   Microserviços (OTel SDK) ──► Alloy DaemonSet (OTLP Receiver)              │
│                                      ├─ Metrics ──► Mimir (TSDB no HDD)     │
│                                      ├─ Logs    ──► Loki (Chunks no HDD)    │
│                                      └─ Traces  ──► Tempo (Blocks no HDD)   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 📁 Estrutura de Diretórios no Repositório

```text
monitor_lab/
├── scripts/
│   ├── mount-hdd.sh            # Formata e monta o HDD de 1TB em /mnt/dados
│   ├── bootstrap-tools.sh      # Instala kubectl, helm, terraform, sops, age, flux
│   ├── install-k3s.sh          # Instala o cluster K3s com storage no HDD
│   └── sops-keygen.sh          # Gera par de chaves age e configura o SOPS
│
├── secrets/
│   ├── .sops.yaml              # Regras de encriptação do SOPS
│   ├── README.md               # Guia de encriptação e decriptação
│   └── templates/              # Modelos de secrets (Grafana, Docker Hub, DBs)
│
├── terraform/                  # IaC - Provisionamento de Infraestrutura
│   ├── providers.tf            # Provider kubernetes e helm
│   ├── variables.tf            # Variáveis parametrizáveis
│   ├── main.tf                 # Namespaces, Traefik, Portainer, Grafana, Alloy, Flux
│   └── outputs.tf              # URLs de acesso (Grafana, Portainer, Traefik)
│
├── k8s/                        # Manifests Kubernetes reconciliados pelo Flux
│   ├── ingress/                # Traefik IngressRoutes e Middlewares
│   ├── observability/          # Mimir, Loki, Tempo, Alloy ConfigMap
│   ├── apps/                   # Deployments dos Microserviços (FastAPI BFF, etc.)
│   └── gitops/                 # Flux GitRepository e Kustomization
│
└── .github/workflows/
    ├── ci-microservice.yml     # Pipeline de build e push para Docker Hub
    └── terraform-validate.yml  # Validação de sintaxe e formato do Terraform
```

---

## 🚀 Passo a Passo de Execução no Servidor (`creedx66`)

Execute os comandos abaixo diretamente no terminal do servidor:

### Passo 1: Montar o HDD de 1TB de forma permanente
```bash
cd /var/www/projects/monitor_lab
sudo ./scripts/mount-hdd.sh
```
*Isso verifica `/dev/sda1`, formata como `ext4` se necessário, monta em `/mnt/dados` e adiciona ao `/etc/fstab` com a pasta `/mnt/dados/k3s-storage` pronta.*

---

### Passo 2: Instalar as Ferramentas de DevOps
```bash
sudo ./scripts/bootstrap-tools.sh
```
*Instala: `kubectl`, `helm`, `terraform`, `age`, `sops` e `flux`.*

---

### Passo 3: Instalar o K3s
```bash
sudo ./scripts/install-k3s.sh
```
*Instala o K3s configurando o armazenamento padrão no HDD de 1TB, desabilitando o Traefik embutido (usaremos a versão v3 via Terraform) e exportando o `kubeconfig` para `~/.kube/config`.*

Verifique o nó:
```bash
kubectl get nodes -o wide
```

---

### Passo 4: Gerar a Chave de Criptografia de Secrets (SOPS + age)
```bash
./scripts/sops-keygen.sh
```
*Gera sua chave privada em `~/.config/sops/age/keys.txt` e atualiza o `secrets/.sops.yaml` com a sua chave pública.*

Para criar e criptografar o primeiro secret:
```bash
cp secrets/templates/grafana-secret.yaml secrets/grafana.enc.yaml
sops -e -i secrets/grafana.enc.yaml
```

---

### Passo 5: Provisionar a Infraestrutura com Terraform
```bash
cd /var/www/projects/monitor_lab/terraform
terraform init
terraform plan
terraform apply -auto-approve
```

---

### Passo 6: Aplicar Manifests e IngressRoutes
```bash
cd /var/www/projects/monitor_lab
kubectl apply -f k8s/ingress/
kubectl apply -f k8s/observability/
```

---

## 🌐 URLs de Acesso via Tailscale

Uma vez provisionado, acesse os serviços na sua Tailnet:

| Serviço | URL | Descrição |
|---|---|---|
| **Portainer CE** | `http://creedx66.tail096995.ts.net/portainer/` | Gerenciamento visual do K3s, Pods, Volumes e Logs |
| **Grafana** | `http://creedx66.tail096995.ts.net/grafana/` | Dashboards LGTM, métricas e tracing |
| **Traefik Dashboard** | `http://creedx66.tail096995.ts.net:8080/dashboard/` | Métricas de roteamento e middlewares |
| **API BFF** | `http://creedx66.tail096995.ts.net/api/v1/` | Gateway de microsserviços |

---

## 🔒 Segredos no GitHub Actions para CI/CD

No repositório do GitHub (`Settings > Secrets and variables > Actions`), configure:
- `DOCKERHUB_USERNAME`: Seu usuário do Docker Hub
- `DOCKERHUB_TOKEN`: Seu Personal Access Token (PAT) do Docker Hub

