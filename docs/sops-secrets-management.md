# Guia de Criptografia e Gestão de Secrets com SOPS e age

Este guia documenta o ciclo de vida de **segredos criptografados** no repositório `monitor_lab` utilizando **Mozilla SOPS** e chaves **age**.

---

## 1. Por que SOPS e age?

Em uma arquitetura GitOps, **todo o estado do cluster deve estar versionado no Git**, inclusive os manifests de Secrets.

- O **SOPS** criptografa apenas os valores confidenciais dos arquivos YAML (mantendo a estrutura legível para validação).
- O **age** é uma ferramenta moderna de criptografia assimétrica baseada em curvas elípticas (X25519), mais leve e segura que GPG.
- **Resultado:** Você pode commitar arquivos `.enc.yaml` no GitHub com 100% de segurança.

---

## 2. Como Funciona a Criptografia Assimétrica

```text
[Sua Máquina / CI]
Chave Pública age (age1...) ──► Criptografa o arquivo .enc.yaml ──► Commit seguro no Git (GitHub)
                                                                           │
                                                                           ▼
[Cluster K3s / Flux CD]
Chave Privada age (AGE-SECRET-KEY-...) ◄── Lê o repositório Git ───────────┘
         │
         ▼
Decripta os valores em memória e injeta como Secret nativo no Kubernetes
```

---

## 3. Passo a Passo: Gerando as Chaves

### Método Automatizado (Recomendado)

Execute o script fornecido no repositório:

```bash
./scripts/sops-keygen.sh
```

### Método Manual

```bash
# 1. Cria o diretório de chaves
mkdir -p ~/.config/sops/age

# 2. Gera o par de chaves
age-keygen -o ~/.config/sops/age/keys.txt

# 3. Extrai a chave pública
PUBLIC_KEY=$(grep "public key:" ~/.config/sops/age/keys.txt | cut -d: -f2 | tr -d ' ')
echo "Sua chave pública é: $PUBLIC_KEY"

# 4. Configura o .sops.yaml com sua chave pública
cat <<EOF > .sops.yaml
creation_rules:
  - path_regex: .*\.enc\.ya?ml$
    age: "${PUBLIC_KEY}"
EOF
```

---

## 4. Injetando a Chave Privada no Cluster (para o Flux CD)

Para que o Flux CD consiga decriptar os arquivos automaticamente no K3s, injete a chave privada no namespace `flux-system`:

```bash
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=$HOME/.config/sops/age/keys.txt \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

## 5. Operações do Dia a Dia com SOPS

### A. Criar e Criptografar um Novo Secret

1. Crie o arquivo a partir dos templates existentes:

   ```bash
   cp secrets/templates/databases-secret.yaml secrets/databases.enc.yaml
   ```

2. Criptografe o arquivo in-place:

   ```bash
   sops -e -i secrets/databases.enc.yaml
   ```

   *(Ao abrir o arquivo, você notará que todos os valores estão em blocos criptografados `sops: ...`)*

### B. Editar um Secret Criptografado

Você não precisa decriptar para editar! O SOPS abre o seu `$EDITOR`, decripta temporariamente na memória e recriptografa ao fechar:

```bash
sops secrets/databases.enc.yaml
```

### C. Visualizar o Conteúdo Decriptado no Terminal

```bash
sops -d secrets/databases.enc.yaml
```

### D. Aplicar Diretamente no Cluster (se não estiver usando GitOps)

```bash
sops -d secrets/databases.enc.yaml | kubectl apply -f -
```

---

## 6. O que NUNCA fazer

- ❌ **NUNCA** commite o arquivo `keys.txt` ou qualquer arquivo contendo `AGE-SECRET-KEY-`.
- ❌ **NUNCA** commite secrets que não tenham a extensão `.enc.yaml`.
- ✅ Apenas a chave pública (`age1...`) e os arquivos `.enc.yaml` podem ir para o Git.
