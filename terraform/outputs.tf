output "traefik_dashboard_url" {
  description = "Acesso seguro ao Dashboard do Traefik via port-forward"
  value       = "kubectl port-forward -n ingress deployment/traefik 8080:8080 -> http://localhost:8080/dashboard/"
}

output "grafana_url" {
  description = "URL para o Grafana UI"
  value       = "http://${var.tailscale_hostname}/grafana/"
}

output "portainer_url" {
  description = "URL para a interface do Portainer (Gerenciamento do K3s)"
  value       = "http://${var.tailscale_hostname}/portainer/"
}

output "kubectl_command" {
  description = "Comando para conectar e verificar os nós do cluster"
  value       = "kubectl get nodes -o wide"
}

