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
        CaddyHost -->|/api/* (Reverse Proxy 127.0.0.1:8510)| ApiContainer["bigdevz-finance-api-1 (Laravel 13 - Port 8000)"]
        
        subgraph DockerNet["Rede Docker (bigdevz-finance)"]
            ApiContainer -->|Porta 5432| Postgres["bigdevz-finance-postgres-1 (PostgreSQL 17 Alpine)"]
            Scheduler["bigdevz-finance-scheduler-1 (Schedule Work)"] -->|Porta 5432| Postgres
        end
        
        Postgres -->|Persistência| VolumePg[("Volume: postgres-data")]
        ApiContainer -->|Montagem /app| ApiDir["/srv/finance/api"]
        Scheduler -->|Montagem /app| ApiDir
    end
```

### Regras Críticas de Integridade:
1. **Preservação Estrita do PostgreSQL 17:** É proibido atualizar ou migrar para PostgreSQL 18. O banco oficial é estritamente `bigdevz_finance` sobre o volume persistente `postgres-data`.
2. **Caddy Nativo no Host:** O Caddy já gerencia certificados HTTPS e atua como terminador TLS e servidor de arquivos estáticos para `/srv/finance/web`, com fallback para `index.html`. Não há contêiner Nginx em produção.
3. **Isolamento de Portas:** O PostgreSQL (5432) não possui qualquer porta exposta no host ou na internet. A API Laravel escuta estritamente no bind local `127.0.0.1:8510`.
4. **Execução sem Root:** O container da API executa sob usuário não-root dedicado `appuser` (UID/GID 1000).

---

## 2. Inventário de Recursos da VPS

| Recurso | Configuração Real em Produção |
|---|---|
| **Host / Alias** | `srv1884441` (`ssh bigdevz`) |
| **Diretório Canônico** | `/srv/finance` (subdiretórios `api/`, `web/`, `infra/`, `backups/`) |
| **Banco de Dados** | PostgreSQL 17 Alpine (`bigdevz-finance-postgres-1`) |
| **Base de Dados** | `bigdevz_finance` |
| **Volume Docker** | `postgres-data` |
| **Backend API** | `bigdevz-finance-api-1` (`127.0.0.1:8510->8000/tcp`) |
| **Agendador** | `bigdevz-finance-scheduler-1` (`php artisan schedule:work`) |
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
