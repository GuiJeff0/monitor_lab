# Roteamento & Ingress (`k8s/ingress`)

Este diretório gerencia o roteamento externo, API Gateway e políticas de borda do Traefik v3.

## Arquivos

- **`middlewares.yaml`**: Middlewares do Traefik por namespace:
  - `tailscale-ipallowlist`: Restringe o acesso aos IPs da malha Tailscale e redes privadas.
  - `https-redirect`: Força redirecionamento automático de HTTP (80) para HTTPS (443).
  - `traefik-redirect`, `traefik-dashboard-redirect`, `traefik-stripprefix`: Roteamento e subcaminho `/traefik/dashboard/`.
  - `portainer-redirect` & `portainer-stripprefix`: Tratamento de trailing slash e subcaminho `/portainer/`.
  - `soap-headers`, `soap-ratelimit`, `soap-buffering`: Hardening contra DoS, XML Bombs e ataques em SOAP.
- **`traefik-ingress.yaml`**: IngressRoute para a interface do dashboard e API do Traefik em `/traefik/dashboard/` e `/api`.
- **`grafana-ingress.yaml`**: IngressRoute para a interface do Grafana em `/grafana`.
- **`portainer-ingress.yaml`**: IngressRoute para a interface do Portainer em `/portainer`.
