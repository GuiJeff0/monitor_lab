#!/usr/bin/env bash
# ==============================================================================
# Install K3s Single-Node Cluster on creedx66
# Configured for:
# - Disabled built-in Traefik (we use Traefik v3 via Terraform/Helm)
# - Disabled built-in ServiceLB (Traefik binds hostPorts 80/443)
# - Default Storage on /mnt/dados/k3s-storage (HDD 1TB)
# - Readable Kubeconfig for local user
# ==============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root or with sudo: sudo $0"
   exit 1
fi

STORAGE_PATH="/mnt/dados/k3s-storage"
mkdir -p "$STORAGE_PATH"

echo "=== Pre-flight: Stopping existing Docker containers on ports 80/443 ==="
if command -v docker &>/dev/null; then
    docker stop traefik 2>/dev/null || true
    echo "Existing docker traefik container stopped."
fi

echo "=== Installing K3s ==="
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --disable=traefik \
  --disable=servicelb \
  --default-local-storage-path=${STORAGE_PATH} \
  --write-kubeconfig-mode=644 \
  --node-name=creedx66" sh -

echo "=== Waiting for K3s Node to be Ready ==="
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
until kubectl get node creedx66 2>/dev/null | grep -q "Ready"; do
    sleep 2
    echo "Waiting for node ready..."
done

echo "=== Setting up user kubeconfig ==="
USER_HOME=$(eval echo "~${SUDO_USER:-$USER}")
mkdir -p "${USER_HOME}/.kube"
cp /etc/rancher/k3s/k3s.yaml "${USER_HOME}/.kube/config"
chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "${USER_HOME}/.kube"

echo "=== K3s Status ==="
kubectl get nodes -o wide
echo "K3s installation finished successfully!"

