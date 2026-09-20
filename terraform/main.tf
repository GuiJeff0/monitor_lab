# ==============================================================================
# Terraform Main Configuration for K3s on creedx66
# ==============================================================================

# 1. Namespaces
resource "kubernetes_namespace" "namespaces" {
  for_each = toset([
    "ingress",
    "observability",
    "apps",
    "data",
    "portainer",
    "flux-system"
  ])

  metadata {
    name = each.key
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "environment"                  = "production"
    }
  }
}

# 2. StorageClasses (Separando SSD NVMe e HDD SATA 1TB)
resource "kubernetes_storage_class" "local_hdd" {
  metadata {
    name = "local-hdd"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "rancher.io/local-path"
  volume_binding_mode    = "WaitForFirstConsumer"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true
}

resource "kubernetes_storage_class" "local_ssd" {
  metadata {
    name = "local-ssd"
  }

  storage_provisioner    = "rancher.io/local-path"
  volume_binding_mode    = "WaitForFirstConsumer"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true
}

# 3. Traefik Ingress Controller (Helm)
resource "helm_release" "traefik" {
  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  version    = "34.0.0" # Traefik v3
  namespace  = kubernetes_namespace.namespaces["ingress"].metadata[0].name

  values = [
    yamlencode({
      deployment = {
        replicas = 1
      }
      ports = {
        web = {
          port     = 80
          hostPort = 80
          exposedPort = 80
        }
        websecure = {
          port     = 443
          hostPort = 443
          exposedPort = 443
        }
        traefik = {
          port        = 8080
          hostPort    = 8080
          exposedPort = 8080
        }
      }
      service = {
        type = "ClusterIP"
      }
      ingressRoute = {
        dashboard = {
          enabled = true
        }
      }
      metrics = {
        prometheus = {
          entryPoint = "traefik"
        }
      }
      logs = {
        general = {
          level  = "INFO"
          format = "json"
        }
        access = {
          enabled = true
          format  = "json"
        }
      }
    })
  ]
}

# 4. Portainer CE (Visualizador K3s para o Usuário)
resource "helm_release" "portainer" {
  count      = var.enable_portainer ? 1 : 0
  name       = "portainer"
  repository = "https://portainer.github.io/k8s/"
  chart      = "portainer"
  version    = "1.0.60"
  namespace  = kubernetes_namespace.namespaces["portainer"].metadata[0].name

  values = [
    yamlencode({
      service = {
        type = "ClusterIP"
      }
      ingress = {
        enabled = false # Usamos o Traefik IngressRoute dedicado
      }
      persistence = {
        enabled      = true
        storageClass = "local-hdd"
        size         = "10Gi"
      }
    })
  ]

  depends_on = [helm_release.traefik]
}

# 5. Grafana LGTM Stack (Grafana, Mimir, Loki, Tempo)
resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "8.8.2"
  namespace  = kubernetes_namespace.namespaces["observability"].metadata[0].name

  values = [
    yamlencode({
      adminUser     = "admin"
      adminPassword = "admin" # Substituído em runtime via SOPS secret
      env = {
        GF_SERVER_DOMAIN             = var.tailscale_hostname
        GF_SERVER_ROOT_URL           = "http://${var.tailscale_hostname}/grafana/"
        GF_SERVER_SERVE_FROM_SUB_PATH = "true"
      }
      persistence = {
        enabled      = true
        storageClass = "local-hdd"
        size         = "5Gi"
      }
      datasources = {
        "datasources.yaml" = {
          apiVersion = 1
          datasources = [
            {
              name      = "Mimir"
              type      = "prometheus"
              uid       = "mimir"
              url       = "http://mimir.observability.svc.cluster.local:8080/prometheus"
              access    = "proxy"
              isDefault = true
              jsonData = {
                httpMethod   = "POST"
                timeInterval = "15s"
              }
            },
            {
              name     = "Loki"
              type     = "loki"
              uid      = "loki"
              url      = "http://loki.observability.svc.cluster.local:3100"
              access   = "proxy"
              jsonData = {
                maxLines = 1000
                derivedFields = [
                  {
                    datasourceUid = "tempo"
                    matcherRegex  = "\"traceID\":\"(\\w+)\""
                    name          = "TraceID"
                    url           = "$${__value.raw}"
                  }
                ]
              }
            },
            {
              name     = "Tempo"
              type     = "tempo"
              uid      = "tempo"
              url      = "http://tempo.observability.svc.cluster.local:3200"
              access   = "proxy"
              jsonData = {
                httpMethod = "GET"
                tracesToLogsV2 = {
                  datasourceUid = "loki"
                  filterByTraceID = true
                }
                tracesToMetrics = {
                  datasourceUid = "mimir"
                }
                nodeGraph = {
                  enabled = true
                }
              }
            }
          ]
        }
      }
    })
  ]
}

# 6. Grafana Alloy (DaemonSet para Coleta Unificada OTel & K8s)
resource "helm_release" "alloy" {
  name       = "alloy"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  version    = "0.10.0"
  namespace  = kubernetes_namespace.namespaces["observability"].metadata[0].name

  values = [
    yamlencode({
      alloy = {
        configMap = {
          create = false
          name   = "alloy-config"
          key    = "config.alloy"
        }
      }
      controller = {
        type = "daemonset"
      }
    })
  ]

  depends_on = [helm_release.grafana]
}

# 7. Flux CD (GitOps Controller com suporte nativo a SOPS)
resource "helm_release" "flux" {
  count      = var.enable_flux ? 1 : 0
  name       = "flux"
  repository = "https://fluxcd-community.github.io/helm-charts"
  chart      = "flux2"
  version    = "2.14.0"
  namespace  = kubernetes_namespace.namespaces["flux-system"].metadata[0].name

  values = [
    yamlencode({
      installCRDs = true
      kustomizeController = {
        create = true
      }
      sourceController = {
        create = true
      }
    })
  ]
}

