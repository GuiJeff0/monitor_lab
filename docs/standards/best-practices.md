# Boas Práticas (Best Practices)

## 1. Docker & Docker Compose

### 1.1. Estratégia de Tags de Imagem
- **NUNCA** utilize a tag `:latest` em ambientes de produção. O `:latest` é mutável e pode causar quebras inesperadas se uma nova versão for publicada e o container reiniciar.
- Utilize versões semânticas estritas (ex: `python:3.13-slim-bookworm` em vez de apenas `python:3.13`).
- Para suas próprias imagens, tagueie com o SHA do commit do Git, e adicionalmente com a versão semântica da release.

### 1.2. Health Checks
- Todo container definido no `docker-compose.yml` **DEVE** possuir um bloco `healthcheck`. Isso permite que dependências (usando `depends_on: condition: service_healthy`) funcionem corretamente.
- Exemplo de healthcheck para o PostgreSQL:
  ```yaml
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U postgres"]
    interval: 5s
    timeout: 5s
    retries: 5
  ```

### 1.3. Limites de Recursos
- Sempre defina `deploy.resources.limits` (CPU e Memória) para evitar que um serviço defeituoso (ex: memory leak) derrube todo o host ou outros containers.

### 1.4. Segurança (Non-root)
- Execute processos dentro do container como usuário sem privilégios (non-root).
- Crie um usuário `appuser` no Dockerfile e use a diretiva `USER appuser`.

### 1.5. Boas Práticas Adicionais
- Use um arquivo `.dockerignore` eficiente para evitar enviar `.git/`, `venv/`, ou variáveis `.env` para o contexto de build.
- Prefira **Multi-stage builds** para separar a fase de compilação (instalação de pacotes C) da imagem final de runtime, reduzindo o tamanho da imagem final.

---

## 2. FastAPI & Python

### 2.1. Padrões Async
- Use `async def` para rotas de I/O-bound (banco de dados assíncrono, requisições HTTP externas).
- Use `def` sincrono **apenas** para rotas intensivas de CPU (pois o FastAPI rodará em threadpool), mas idealmente, delegue CPU pesada para workers (ex: Celery, RQ).

### 2.2. Injeção de Dependências
- Aproveite o `Depends()` do FastAPI. Utilize injeção de dependências para passar instâncias de repositórios, serviços e conexões de banco de dados para os controllers.
- Isso desacopla o código e facilita imensamente a criação de mocks para testes unitários.

### 2.3. Pydantic
- Separe rigorosamente os Schemas de Entrada (Request) dos Schemas de Saída (Response).
- Exemplo: `UserCreate` (com senha) e `UserResponse` (sem senha).
- Utilize o `model_validate` (Pydantic v2) para converter ORM models em Pydantic models (substituindo `orm_mode=True`).

### 2.4. Tratamento de Erros e Stack Traces
- Configure **Global Exception Handlers** no FastAPI.
- **NUNCA** exponha stack traces em respostas de erro (HTTP 500) para o cliente. O erro detalhado deve ir para os logs (Loki) e o cliente recebe apenas uma mensagem genérica de "Erro Interno".

### 2.5. Configurações
- Gerencie toda a configuração via `pydantic-settings`. Isso valida tipos, carrega variáveis de ambiente automaticamente e fornece valores default.

---

## 3. Banco de Dados (PostgreSQL)

### 3.1. Connection Pooling
- Em um ambiente assíncrono, use `ext.asyncio.create_async_engine` do SQLAlchemy com a lib `asyncpg`.
- Configure pools adequados (`pool_size`, `max_overflow`). O FastAPI gerencia conexões concorrentes, esgotar o pool resultará em timeouts.

### 3.2. Migrations (Alembic)
- Mudanças de esquema **DEVEM** ser feitas via Alembic. Não altere o schema diretamente no banco.
- Ao revisar PRs, verifique os scripts autogerados, pois às vezes o Alembic erra ao detectar renomeações.

### 3.3. Transações e Camada de Serviço
- Nenhuma lógica de SQL ou acesso direto a dados deve vazar para a camada de Controller (Roteamento).
- As transações (commit/rollback) devem ser gerenciais pela camada de Serviço, ou via middlewares estruturados, garantindo "Tudo ou Nada" nas operações de negócio.

---

## 4. Segurança

### 4.1. Gerenciamento de Segredos
- **NUNCA** commite arquivos `.env`, chaves privadas, senhas de banco ou tokens. 
- Use sistemas de Secrets ou injeção em ambiente (no CI/CD) para popular essas variáveis.

### 4.2. Autenticação e JWT
- Tokens JWT devem ter ciclo de vida curto (ex: 15 minutos).
- Implemente Refresh Tokens se necessário acesso prolongado.
- Hash de senhas deve usar `bcrypt` ou `argon2` (recomendado Passlib).

### 4.3. Validação e TLS
- Valide rigorosamente todos os inputs utilizando as tipagens do Pydantic (tamanhos de strings, regex, faixas numéricas).
- A comunicação externa via Traefik DEVE ser via HTTPS (TLS), mesmo em ambientes de laboratório, simulando produção (ex: certificados Auto-assinados ou Let's Encrypt para domínios reais).

---

## 5. Observabilidade

### 5.1. Nada de Print
- **Proibido** o uso de `print()`. Toda saída do sistema deve ser através do módulo `logging` estruturado (JSON), que enviará os logs ao stdout para serem capturados pelo Alloy.

### 5.2. Contexto é Rei
- O Correlation ID pattern deve estar em todo log da aplicação.
- Nomeie seus traces e spans de forma que reflitam as operações de negócio, não o nome das funções em Python.
- Não faça over-instrumentation: adicionar spans em funções genéricas (`sum_two_numbers()`) polui os traces e degrada o desempenho. Foque em chamadas de I/O e limites arquiteturais.

### 5.3. Logs de Dados Sensíveis
- Revise a política de logs e garanta que payloads contendo cartões de crédito ou senhas sejam mascarados antes de virarem JSON.

---

## 6. Comunicação entre Serviços

### 6.1. Propagação de Trace
- Toda chamada HTTP (usando `httpx`) deve incluir o `traceparent` (via OpenTelemetry Auto-instrumentation).

### 6.2. Resiliência (Circuit Breaker & Retries)
- Não assuma que a rede é confiável.
- Falhas transitórias requerem uma estratégia de **Retry com Exponential Backoff** (ex: bibliotecas como `Tenacity`).
- Se um serviço downstream falhar repetidamente, utilize o padrão **Circuit Breaker** para não sobrecarregá-lo e falhar rápido (*fail fast*).

### 6.3. Idempotência
- Endpoints que alteram estado (POST, PUT, PATCH) devem ser desenhados visando a idempotência sempre que possível (ex: enviar a mesma criação de Ordem de Compra 2 vezes por causa de um retry de rede não deve criar 2 ordens).

---

## 7. Testes

### 7.1. Pirâmide de Testes
- **Unitários**: A maioria. Rápidos, mockando o banco e dependências de rede.
- **Integração**: Testam o Banco (via Testcontainers) ou interações em blocos.
- **E2E (Ponta a Ponta)**: Poucos. Testam fluxos críticos.

### 7.2. Filosofia
- Busque um target de **Coverage > 80%**. Mas o mais importante: teste comportamentos e regras de negócio, não detalhes de implementação.
- Utilize Fixtures do Pytest para popular dados nos bancos de teste de forma limpa.

---

## 8. Git & Versionamento

### 8.1. Conventional Commits
- Siga as regras de commits convencionais.
  - `feat: adiciona endpoint de criacao de usuarios`
  - `fix: corrige falha no tratamento de null pointer`
  - `chore: atualiza pacotes`

### 8.2. Estratégia de Branching
- `main`: Reflete a produção. Código sempre instanciável.
- `develop` (opcional): Ambiente de staging/testes.
- Branches locais para desenvolvimento: `feature/nome-da-feature`, `bugfix/issue-id`.

### 8.3. PRs (Pull Requests)
- Faça Pull Requests pequenos. Grandes PRs não são revisados, são apenas aprovados.
- Todo PR deve passar pelo CI antes de fazer merge.

---

## 9. CI/CD (Futuro)

### 9.1. Pipeline Base
- Planeje pipelines no GitHub Actions.
- **Passo 1 (Linting/Testes)**: Ruff, Black, Pytest, Coverage.
- **Passo 2 (Build)**: Build da Imagem Docker com as tags corretas.
- **Passo 3 (Push)**: Envio para o Registry (DockerHub/GHCR).
- **Passo 4 (Deploy)**: Atualizar arquivos de infra (K8s / Compose) para baixar a nova imagem.

---

## 10. Operational Runbook

Guia rápido para operação no dia a dia do laboratório:

### 10.1. Como verificar a saúde de um serviço?
1. Abra o Grafana.
2. Acesse o Dashboard de Infraestrutura.
3. Verifique os painéis de status dos Containers, Uso de CPU/Memória.
4. Para serviços, chame o endpoint `GET /health` pelo Traefik (ex: `https://monitor.lab/users/health`).

### 10.2. Como encontrar erros no Loki?
1. Abra Grafana -> Explore -> Loki.
2. Rode a query: `{app="users-api"} |= "error" | json` ou `{level="ERROR"}`.
3. Observe o campo `trace_id` e copie-o.

### 10.3. Como rastrear uma requisição end-to-end?
1. Com o `trace_id` copiado, abra a aba Explore -> Tempo.
2. Cole o ID.
3. Você verá o Waterfall Chart mostrando todos os Spans, quanto tempo durou cada etapa e em qual microsserviço a falha ocorreu.

### 10.4. Como debugar uma query lenta?
1. Se o Tempo acusar latência alta num Span do Banco de Dados, inspecione os atributos do Span (O OTel SQLAlchemy instrumentor grava a instrução SQL ali).
2. Conecte no banco localmente (via pgAdmin ou psql) e rode um `EXPLAIN ANALYZE` na query copiada para verificar falta de índices.

### 10.5. Como reiniciar um serviço falho?
1. No terminal da máquina host (onde está o repositório):
   ```bash
   docker compose restart users-api
   ```
2. Para ver os logs temporários na tela:
   ```bash
   docker compose logs -f --tail 100 users-api
   ```
3. Lembre-se, o reinício apenas mascara o problema temporariamente. O foco é coletar logs e traces para a correção da raiz!
