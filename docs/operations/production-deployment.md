# BigDev.Z Finance — Guia de Deploy de Produção

> **Documento Oficial de Infraestrutura e Release**  
> **Classificação:** Restrito a Operações e Engenharia  
> **Ambiente:** Produção (VPS `bigdevz` / `srv1884441` — Diretório: `/srv/finance`)  
> **Topologia Canônica:** PostgreSQL 17 Alpine | Base: `bigdevz_finance` | Volume: `postgres-data` | Caddy TLS no Host

---

## 1. Arquitetura e Topologia Real de Produção

O BigDev.Z Finance opera em produção utilizando a infraestrutura já provisionada na VPS, preservando integralmente o banco existente e o terminador TLS Caddy:

```mermaid
flowchart TD
    Client["Navegador / Dispositivo QA"] -->|HTTPS (Porta 443)| CaddyHost["Caddy no Host (Let's Encrypt Automático)"]
    
    subgraph HostVPS["VPS Host (srv1884441 - /srv/finance)"]
        CaddyHost -->|/ (Arquivos Estáticos SPA)| WebDir["/srv/finance/web (Flutter Web Release)"]
        CaddyHost -->|/api/* (Reverse Proxy 127.0.0.1:8510)| ApiContainer["finance-prod-api-1 (Laravel 13 - Port 8000)"]
        
        subgraph DockerNet["Rede Docker (finance-prod_default)"]
            ApiContainer -->|Porta 5432| Postgres["finance-prod-postgres-1 (PostgreSQL 17 Alpine)"]
            Scheduler["finance-prod-scheduler-1 (Schedule Work)"] -->|Porta 5432| Postgres
        end
        
        Postgres -->|Persistência| VolumePg[("Volume: postgres-data")]
        ApiContainer -->|Montagem /app| ApiDir["/srv/finance/api"]
        Scheduler -->|Montagem /app| ApiDir
    end
```

### Regras Críticas de Integridade e Pré-Voo (Hardening):
1. **Preservação Estrita do PostgreSQL 17:** É proibido atualizar ou migrar para PostgreSQL 18. O banco oficial é estritamente `bigdevz_finance` sobre o volume persistente `postgres-data`.
2. **Caddy Nativo no Host:** O Caddy já gerencia certificados HTTPS e atua como terminador TLS e servidor de arquivos estáticos para `/srv/finance/web`, com fallback para `index.html`. Não há contêiner Nginx em produção.
3. **Isolamento de Portas:** O PostgreSQL (5432) não possui qualquer porta exposta no host ou na internet. A API Laravel escuta estritamente no bind local `127.0.0.1:8510`.
4. **Execução sem Root:** O container da API executa sob usuário não-root dedicado `appuser` (UID/GID 1000).
5. **Pré-Voo de Permissões Fail-Closed:** Antes de qualquer alteração, o script testa permissões de escrita atômica no diretório `/var/lib/vps-deploy/<projeto>` e nos marcadores (`implantado_tag`, `implantado`, `implantado_digest`, `recuperacao_pendente`), evitando falhas permissivas pós-migração.
6. **Pré-Voo de Rede e Conectividade Compose:** Antes de parar os escritores da API e antes do dump do banco, um container efêmero testa a conectividade PDO com o PostgreSQL na rede Compose exata do projeto (`finance-prod`), abortando imediatamente se houver divergência de projeto ou resolução de host.
7. **Promoção Coordenada do Frontend Web:** O bundle web é recebido em `/srv/finance/web_staging/` e promovido atomicamente para `/srv/finance/web/` somente APÓS a API responder com sucesso 200 OK no endpoint de liveness (`/up`), garantindo que clientes nunca acessem rotas ou frontends novos sem o backend correspondente.
8. **Desacoplamento de Rollback Pós-Healthcheck:** Caso o healthcheck seja aprovado com 100% de sucesso, qualquer falha posterior em metadados secundários não desliga a API saudável em produção.
9. **Invocação SSH Segura:** Todas as chamadas SSH que encaminham tags e digests utilizam o separador `--` para neutralizar parsing ambíguo de opções no cliente OpenSSH.

---

## 2. Inventário de Recursos da VPS

| Recurso | Configuração Real em Produção |
|---|---|
| **Host / Alias** | `srv1884441` (`ssh bigdevz`) |
| **Diretório Canônico** | `/srv/finance` (subdiretórios `api/`, `web/`, `infra/`, `backups/`) |
| **Projeto Compose** | `finance-prod` (configurável via `COMPOSE_PROJECT_NAME`) |
| **Banco de Dados** | PostgreSQL 17 Alpine (`finance-prod-postgres-1` com fallback dinâmico) |
| **Base de Dados** | `bigdevz_finance` |
| **Volume Docker** | `postgres-data` |
| **Backend API** | `finance-prod-api-1` (`127.0.0.1:8510->8000/tcp`) |
| **Agendador** | `finance-prod-scheduler-1` (`php artisan schedule:work`) |
| **Frontend Web** | `/srv/finance/web` servido diretamente pelo Caddy |
| **Proxy Reverso / TLS** | Caddy Server com Let's Encrypt |
| **Domínio Oficial** | `https://finance.bigdevz.com` |

---

## 3. Fluxo de Release Automatizado (Idempotente e Seguro)

Todo deploy em produção deve partir exclusivamente da branch `main` após aprovação de Pull Request.

### 3.1. Pré-requisito: Validação Local (`--check-only`)
Antes de tocar no servidor, valide localmente os artefatos:
```bash
./scripts/deploy-production.sh --check-only
```
Este comando valida:
1. Compilação do Flutter Web de produção (`flutter build web --release`).
2. Testes de domínio financeiro (`php tests/domain.php`).
3. Linter (`vendor/bin/pint --test`) e análise estática (`flutter analyze`).

### 3.2. Execução do Deploy na VPS (`--execute`)
Com a branch `main` ativa e aprovada:
```bash
./scripts/deploy-production.sh --execute
```
Etapas executadas automaticamente:
1. **Snapshot Preventivo com Checksum:** Executa `pg_dump -Fc` no container `bigdevz-finance-postgres-1` da base `bigdevz_finance` e gera hash SHA-256 em `/srv/finance/backups/db/`.
2. **Arquivamento de Versão Anterior:** Salva `/srv/finance/web` em `web_previous` e `/srv/finance/api` em `api_previous`.
3. **Sincronização Atômica:** Atualiza arquivos do Flutter Web e da API Laravel preservando `production.conf`, `storage/` e `.env`.
4. **Reconstrução Controlada:** Recompila e reinicia apenas os containers `api` e `scheduler`.
5. **Migrações e Otimização:** Aplica `php artisan migrate --force` e atualiza caches de rota e configuração.
6. **Verificação de Saúde:** Testa liveness (`/up`) e saúde dos subsistemas (`/api/health`).

---

## 4. Política de Rollback e Recuperação

Em caso de falha pós-deploy:

### 4.1. Rollback Exclusivo de Código (sem alteração de banco)
```bash
ssh bigdevz "/srv/finance/scripts/rollback-production.sh --code-only"
```
Restaura imediatamente as versões de `web_previous` e `api_previous` e reinicia os serviços.

### 4.2. Rollback Completo com Restauração do Banco de Dados
> [!IMPORTANT]
> Se a versão com defeito tiver executado migrações com alteração destrutiva ou incompatível de schema, a restauração da base `bigdevz_finance` a partir do snapshot pré-deploy é obrigatória:
```bash
ssh bigdevz "/srv/finance/scripts/rollback-production.sh --with-db-restore /srv/finance/backups/db/pre_deploy_<TIMESTAMP>.dump"
```
O script encerra conexões ativas na base `bigdevz_finance`, valida o checksum SHA-256 e executa `pg_restore --clean`.

## Publicação pelo GitHub Actions

O push para `dev` compartilha o trabalho. PRs abertos continuam executando CI quando recebem atualizações. O diagnóstico do DefectDojo pode ser iniciado manualmente.

Promova por PR de `dev` para `main`. Aguarde o CI verde na `main` para o commit de merge antes de publicar a tag SemVer nesse commit. A tag dispara o deploy. O job confere o SHA homologado e autentica o SSH com as credenciais do ambiente `production` do Finance antes de construir a imagem.

O Trivy inspeciona a imagem pelo digest enviado à VPS. Após a implantação, o job compara a revisão devolvida por `https://finance.bigdevz.com/api/health` com o SHA da tag. Se essa consulta falhar, confira a revisão pública e os marcadores da VPS antes de repetir o deploy.
