#!/usr/bin/env bash
# ==============================================================================
# Bootstrap Tools Script for creedx66
# Installs: kubectl, helm, terraform, sops, age, k3s
# ==============================================================================
set -euo pipefail

echo "=========================================================="
echo " Starting Bootstrap of DevOps & Kubernetes Tooling"
echo "=========================================================="

# Ensure running as root or with sudo
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root or with sudo: sudo $0"
   exit 1
fi

ARCH="amd64"
DEBIAN_FRONTEND=noninteractive

# 1. System packages
echo "[1/7] Updating apt repositories and installing utilities..."
apt-get update -y
apt-get install -y curl wget git unzip gpg ca-certificates lsb-release jq

# 2. Install kubectl
echo "[2/7] Installing kubectl..."
if ! command -v kubectl &>/dev/null; then
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/
    echo "kubectl installed: $(kubectl version --client -o yaml | grep gitVersion)"
else
    echo "kubectl is already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
fi

# 3. Install Helm
echo "[3/7] Installing Helm 3..."
if ! command -v helm &>/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    echo "Helm installed: $(helm version --short)"
else
    echo "Helm is already installed: $(helm version --short)"
fi

# 4. Install Terraform
echo "[4/7] Installing Terraform..."
if ! command -v terraform &>/dev/null; then
    wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
    apt-get update -y && apt-get install -y terraform
    echo "Terraform installed: $(terraform version | head -n 1)"
else
    echo "Terraform is already installed: $(terraform version | head -n 1)"
fi

# 5. Install age & SOPS
echo "[5/7] Installing age and SOPS for Secret Encryption..."
if ! command -v age &>/dev/null; then
    apt-get install -y age || {
        AGE_VER="v1.2.0"
        curl -LO "https://github.com/FiloSottile/age/releases/download/${AGE_VER}/age-${AGE_VER}-linux-amd64.tar.gz"
        tar -xzf "age-${AGE_VER}-linux-amd64.tar.gz"
        mv age/age age/age-keygen /usr/local/bin/
        rm -rf age "age-${AGE_VER}-linux-amd64.tar.gz"
    }
    echo "age installed: $(age --version)"
else
    echo "age is already installed: $(age --version)"
fi

if ! command -v sops &>/dev/null; then
    SOPS_VER="v3.9.4"
    curl -LO "https://github.com/getsops/sops/releases/download/${SOPS_VER}/sops-${SOPS_VER}.linux.amd64"
    chmod +x "sops-${SOPS_VER}.linux.amd64"
    mv "sops-${SOPS_VER}.linux.amd64" /usr/local/bin/sops
    echo "SOPS installed: $(sops --version)"
else
    echo "SOPS is already installed: $(sops --version)"
fi

# 6. Install Flux CLI
echo "[6/7] Installing Flux CLI..."
if ! command -v flux &>/dev/null; then
    curl -s https://fluxcd.io/install.sh | bash
    echo "Flux CLI installed: $(flux --version)"
else
    echo "Flux CLI is already installed: $(flux --version)"
fi

# 7. Check K3s setup
echo "[7/7] Checking K3s..."
if ! command -v k3s &>/dev/null; then
    echo "Note: K3s is not installed yet. You can install it using scripts/install-k3s.sh."
else
    echo "K3s is already installed: $(k3s --version)"
fi

echo "=========================================================="
echo " All Devops & Kubernetes tools successfully installed!"
echo "=========================================================="

