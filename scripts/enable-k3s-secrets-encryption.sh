#!/usr/bin/env bash
# ==============================================================================
# Script: enable-k3s-secrets-encryption.sh
# Objetivo: Habilitar Criptografia at-rest no etcd/SQLite do K3s
# Requisitos: Executar com sudo
# ==============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
   echo "[-] Este script deve ser executado como root (sudo)."
   exit 1
fi

ENCRYPTION_DIR="/var/lib/rancher/k3s/server"
ENCRYPTION_CONFIG="${ENCRYPTION_DIR}/encryption-config.yaml"
K3S_SERVICE="/etc/systemd/system/k3s.service"

echo "[+] 1. Verificando se a criptografia já está configurada..."
if [[ -f "${ENCRYPTION_CONFIG}" ]]; then
    echo "[!] O arquivo ${ENCRYPTION_CONFIG} já existe. Abortando para evitar sobrescrever a chave existente."
    exit 0
fi

echo "[+] 2. Gerando chave de criptografia AES-CBC de 32 bytes..."
mkdir -p "${ENCRYPTION_DIR}"
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

echo "[+] 3. Criando ${ENCRYPTION_CONFIG}..."
cat <<EOF > "${ENCRYPTION_CONFIG}"
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF

chmod 600 "${ENCRYPTION_CONFIG}"
chown root:root "${ENCRYPTION_CONFIG}"

echo "[+] 4. Atualizando configuração do serviço K3s..."
if grep -q "encryption-provider-config" "${K3S_SERVICE}"; then
    echo "[!] Flag de encryption já presente em ${K3S_SERVICE}."
else
    sed -i "s|--write-kubeconfig-mode 644|--write-kubeconfig-mode 644 \\\\\n\t--kube-apiserver-arg=encryption-provider-config=${ENCRYPTION_CONFIG}|" "${K3S_SERVICE}"
fi

echo "[+] 5. Reiniciando o serviço K3s..."
systemctl daemon-reload
systemctl restart k3s

echo "[+] 6. Aguardando a API do K3s responder..."
sleep 5
until k3s kubectl get nodes &>/dev/null; do
    echo "    Aguardando API server..."
    sleep 2
done

echo "[+] 7. Re-encriptando todos os Secrets existentes no cluster..."
k3s kubectl get secrets --all-namespaces -o json | k3s kubectl replace -f -

echo "[✔] Criptografia de segredos at-rest no etcd/K3s habilitada com sucesso!"
echo "[!] ATENÇÃO: Guarde uma cópia de segurança de ${ENCRYPTION_CONFIG} fora deste servidor."
