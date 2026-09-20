# Gestão de Secrets com SOPS e age

Este diretório gerencia os Kubernetes Secrets criptografados para o cluster K3s.

## Como Funciona

1. Os arquivos com sufixo `.enc.yaml` são **criptografados com a chave pública `age`** antes de serem commitados no Git.
2. O **Flux CD** no cluster K3s possui a **chave privada `age`** montada via Secret (`sops-age` no namespace `flux-system`).
3. Ao reconciliar os manifests, o Flux decripta os secrets automaticamente em memória e os injeta como Secrets nativos do Kubernetes.
4. **Nenhum segredo em texto puro fica exposto no repositório Git.**

## Comandos Rápidos

### 1. Gerar Chave age (se ainda não fez)

```bash
sudo ./scripts/sops-keygen.sh
```

### 2. Criptografar um arquivo de Secret

```bash
# Cria o secret a partir do template
cp secrets/templates/grafana-secret.yaml secrets/grafana.enc.yaml

# Criptografa in-place
sops -e -i secrets/grafana.enc.yaml
```

### 3. Editar um Secret criptografado diretamente

```bash
sops secrets/grafana.enc.yaml
```

*(O SOPS abre o seu editor padrão `$EDITOR`, decripta para edição e recriptografa automaticamente ao salvar)*

### 4. Visualizar o conteúdo decriptado

```bash
sops -d secrets/grafana.enc.yaml
```
