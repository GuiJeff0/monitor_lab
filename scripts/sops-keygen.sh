#!/usr/bin/env bash
# ==============================================================================
# Generate age keypair for SOPS & configure Flux CD Secret
# ==============================================================================
set -euo pipefail

KEY_DIR="${HOME}/.config/sops/age"
KEY_FILE="${KEY_DIR}/keys.txt"
REPO_ROOT="/var/www/projects/monitor_lab"

mkdir -p "$KEY_DIR"

if [ ! -f "$KEY_FILE" ]; then
    echo "Generating new age keypair at $KEY_FILE..."
    age-keygen -o "$KEY_FILE"
else
    echo "Existing age keypair found at $KEY_FILE."
fi

# Extract public key
PUBLIC_KEY=$(grep "public key:" "$KEY_FILE" | cut -d: -f2 | tr -d ' ')
echo "Public Key: $PUBLIC_KEY"

# Update .sops.yaml
echo "Configuring ${REPO_ROOT}/secrets/.sops.yaml..."
mkdir -p "${REPO_ROOT}/secrets"

cat <<EOF > "${REPO_ROOT}/secrets/.sops.yaml"
creation_rules:
  - path_regex: .*\.enc\.ya?ml$
    age: "${PUBLIC_KEY}"
EOF

echo "Configuring ${REPO_ROOT}/.sops.yaml..."
cp "${REPO_ROOT}/secrets/.sops.yaml" "${REPO_ROOT}/.sops.yaml"

# If K3s is running, create secret for Flux CD
if kubectl get ns flux-system &>/dev/null; then
    echo "Creating sops-age secret in flux-system namespace..."
    kubectl create secret generic sops-age \
      --namespace=flux-system \
      --from-file=age.agekey="$KEY_FILE" \
      --dry-run=client -o yaml | kubectl apply -f -
    echo "Flux SOPS secret applied."
fi

echo "SOPS Keygen setup complete!"
echo "You can encrypt secrets with: sops -e -i secrets/my-secret.enc.yaml"
echo "You can decrypt secrets with: sops -d secrets/my-secret.enc.yaml"

