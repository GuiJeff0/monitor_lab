# GitOps & Sincronização Contínua (Flux CD)

Módulo responsável pela automação de entrega contínua (GitOps) no cluster K3s utilizando o Flux CD v2.

---

## 1. Visão Geral

O Flux CD monitora este repositório Git e reconcilia automaticamente o estado desejado com o cluster a cada 1 minuto.
Segredos criptografados com SOPS (`*.enc.yaml`) são decriptados em tempo de execução via chave `age` armazenada no
secret `sops-age` do namespace `flux-system`.

---

## 2. Componentes

- **`flux-sync.yaml`**:
  - `GitRepository (monitor-lab-repo)`: Conecta ao branch `main` do repositório Git com polling a cada 1m.
  - `Kustomization (monitor-lab-apps)`: Executa o build de `./k8s`, decripta arquivos SOPS e aplica os recursos
    com pruning automático de recursos órfãos.

---

## 3. Comandos Úteis de Operação

Para forçar uma sincronização manual imediata do repositório e aplicar as mudanças:

```bash
# Sincronizar o repositório Git
flux reconcile source git monitor-lab-repo -n flux-system

# Ou via anotação com kubectl
kubectl annotate --overwrite gitrepository monitor-lab-repo \
  -n flux-system reconcile.fluxcd.io/requestedAt="$(date +%s)"

# Reconciliar a Kustomization
flux reconcile kustomization monitor-lab-apps -n flux-system
```

Para inspecionar o status da reconciliação:

```bash
kubectl get gitrepository -n flux-system
kubectl get kustomization -n flux-system
```
