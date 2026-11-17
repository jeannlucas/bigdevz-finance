# BigDev.Z Finance — Runbook Operacional de Produção

> **Manual de Operações, Observabilidade e Resposta a Incidentes**  
> **Classificação:** Restrito a Operações e Engenharia  
> **Ambiente:** Produção (VPS `srv1884441` — `/srv/finance`)  
> **Topologia Canônica:** PostgreSQL 17 Alpine | Base: `bigdevz_finance` | Caddy TLS no Host

---

## 1. Inventário de Serviços de Produção

| Serviço / Container | Imagem | Porta Host | Dependências | Função Operacional |
|---|---|---|---|---|
| **finance-prod-postgres-1** | `postgres:17-alpine` | Nenhuma (Interna 5432) | Nenhuma | Banco transacional PostgreSQL (base `bigdevz_finance`, volume `postgres-data`). |
| **finance-prod-api-1** | `ghcr.io/jeannlucas/bigdevz-finance-api@sha256:...` | `127.0.0.1:8510` | `postgres` | Monólito modular Laravel 13 (Actions, regras de negócio e autenticação). |
| **finance-prod-scheduler-1** | `ghcr.io/jeannlucas/bigdevz-finance-api@sha256:...` | Nenhuma (Interna) | `api`, `postgres` | Agendador do Laravel executando geração horária de recorrências (`payables:generate`). |
| **caddy (Host systemd)** | Nativo Linux | `80/tcp`, `443/tcp` | `api`, `/srv/finance/web` | Terminador TLS, proxy reverso de `/api/*` para `127.0.0.1:8510` e SPA file server. |

---

## 2. Endpoints de Observabilidade e Diagnóstico

### 2.1. Liveness Probe (Vida do Processo)
```bash
curl -i http://127.0.0.1:8510/up
# Esperado: HTTP 200 OK
```

### 2.2. Health Check Detalhado (Estado dos Subsistemas)
```bash
curl -s http://127.0.0.1:8510/api/health | jq .
```
Exemplo de resposta operacional saudável:
```json
{
  "status": "ok",
  "timestamp": "2026-11-10T03:00:00+00:00",
  "services": {
    "database": {
      "status": "ok",
      "latency_ms": 1.15,
      "driver": "pgsql"
    },
    "storage": {
      "status": "ok"
    }
  }
}
```

---

## 3. Playbooks de Resposta a Incidentes

### INC-01: API Indisponível ou Erro 502/503

1. **Verificar status dos containers:**
   ```bash
   docker ps --filter "name=bigdevz-finance"
   ```
2. **Inspecionar logs recentes de erro:**
   ```bash
   docker logs --tail=50 bigdevz-finance-api-1
   ```
3. **Reiniciar serviço da API e scheduler:**
   ```bash
   docker restart bigdevz-finance-api-1 bigdevz-finance-scheduler-1
   ```

---

### INC-02: Esgotamento de Conexões no PostgreSQL 17 ou Bloqueios Concorrentes

1. **Listar conexões ativas e consultas bloqueadas:**
   ```bash
   docker exec -it bigdevz-finance-postgres-1 psql -U bigdevz -d bigdevz_finance -c "
       SELECT pid, age(clock_timestamp(), query_start), usename, query, state 
       FROM pg_stat_activity 
       WHERE state != 'idle' AND query NOT LIKE '%pg_stat_activity%' 
       ORDER BY query_start ASC;
   "
   ```
2. **Encerrar consulta travada (lock):**
   ```bash
   docker exec -it bigdevz-finance-postgres-1 psql -U bigdevz -d bigdevz_finance -c "
       SELECT pg_terminate_backend(<PID>);
   "
   ```

---

### INC-03: Falha de Migração e Rollback com Restauração de Banco

> [!CRITICAL]
> **Aviso de Incompatibilidade de Schema:**  
> Se um deploy introduzir alterações de schema e falhar posteriormente, o rollback exclusivo do código quebrará a aplicação. Nestes casos, a restauração da base `bigdevz_finance` a partir do snapshot pré-deploy é mandatória.

1. **Localizar o snapshot pré-deploy gerado:**
   ```bash
   ls -la /srv/finance/backups/db/pre_deploy_*.dump
   ```
2. **Executar o Rollback com Restauração do Banco:**
   ```bash
   /srv/finance/scripts/rollback-production.sh --with-db-restore /srv/finance/backups/db/pre_deploy_<TIMESTAMP>.dump
   ```
3. **Validar integridade pós-restauração:**
   ```bash
   curl -i http://127.0.0.1:8510/up
   curl -s http://127.0.0.1:8510/api/health
   ```

---

### INC-04: Pressão de Armazenamento / Esgotamento de Disco na VPS

1. **Verificar espaço livre:**
   ```bash
   df -h /
   ```
2. **Limpar imagens e containers Docker antigos/não utilizados:**
   ```bash
   docker image prune -a --filter "until=72h" -f
   ```
3. **Aplicar rotação de backups antigos (mantendo 15 ou 30 dias):**
   ```bash
   /srv/finance/scripts/backup-production.sh /srv/finance/backups/db 15
   ```

---

### INC-05: Incidente de Segurança / Rotação de Credenciais

1. **Revogar todas as sessões e tokens Sanctum ativos:**
   ```bash
   docker exec -i bigdevz-finance-api-1 php artisan tinker --execute="
       DB::table('personal_access_tokens')->delete();
       echo 'Todos os tokens Sanctum foram revogados.';
   "
   ```
2. **Rotacionar a `APP_KEY` do Laravel:**
   - Gerar nova chave: `docker exec -i bigdevz-finance-api-1 php artisan key:generate --show`.
   - Atualizar `APP_KEY` no arquivo de configuração `/srv/finance/production.conf`.
   - Reiniciar containers: `docker restart bigdevz-finance-api-1 bigdevz-finance-scheduler-1`.

---

### INC-06: Prevenção de Contaminação de Ambientes e Cache de Frontend

1. **Auditar e Remover Contas de Teste/Dev Não Autorizadas em Produção:**
   ```bash
   docker exec -i bigdevz-finance-api-1 php artisan tinker --execute="
       \$user = App\Models\User::where('email', '<EMAIL_SANITIZADO>')->first();
       if (\$user) {
           \$user->tokens()->delete();
           \$user->delete();
           echo 'Conta não autorizada e tokens revogados com sucesso.';
       }
   "
   ```
2. **Garantir Regras Canônicas de Cache no Caddyfile (`/etc/caddy/Caddyfile`):**
   ```caddy
   finance.bigdevz.com {
       handle /api/* {
           reverse_proxy 127.0.0.1:8510
       }
       handle {
           root * /srv/finance/web
           @no_cache {
               path /index.html / /flutter_service_worker.js /version.json /manifest.json
           }
           header @no_cache Cache-Control "no-cache, no-store, must-revalidate"
           header @no_cache Pragma "no-cache"
           header @no_cache Expires "0"

           @static_assets {
               path /assets/* /canvaskit/* /icons/* /favicon.png
           }
           header @static_assets Cache-Control "public, max-age=31536000, immutable"

           file_server
           try_files {path} /index.html
       }
   }
   ```
3. **Compilação Segura do Frontend Web:**
   - Todo build deve ser gerado pelo script canônico: `./scripts/build-web.sh --env=production`.
   - O runtime valida o endpoint contra o host atual através de `resolveApiBaseUrl()`, bloqueando automaticamente tentativas de acesso cruzado.

---

### INC-07: Diagnóstico de Pré-Voo de Deploy (Permissões e Rede Compose)

Se o pipeline de deploy fail-closed abortar durante a fase de pré-voo:

1. **Permissões em Marcadores (`/var/lib/vps-deploy/<projeto>`):**
   ```bash
   ls -la /var/lib/vps-deploy/
   # Caso algum marcador pertença a root:root e impeça escrita do usuário deployer:
   sudo chown -R $(id -un):$(id -gn) /var/lib/vps-deploy/
   chmod 755 /var/lib/vps-deploy/ /var/lib/vps-deploy/*
   ```
2. **Verificar Projeto Compose e Containers Ativos:**
   ```bash
   docker compose -p finance-prod ps
   # Confirmar conectividade na rede Compose:
   docker exec -it finance-prod-api-1 php -r 'echo "API OK\n";'
   docker exec -it finance-prod-postgres-1 pg_isready -U bigdevz -d bigdevz_finance
   ```
3. **Limpeza de Trava Pendente Órfã (`recuperacao_pendente`):**
   ```bash
   # APENAS após certificar que a base está íntegra e sem migrações corrompidas:
   rm -f /var/lib/vps-deploy/*/recuperacao_pendente
   ```

---

## 4. Janelas de Manutenção Programada

Para intervenções estruturais ou manutenções planejadas:

1. **Ativar Modo de Manutenção com Bypass Seguro:**
   ```bash
   docker exec -i bigdevz-finance-api-1 php artisan down --render="errors.503" --secret="segredo-manutencao-bigdevz"
   ```
   *Nota: O endpoint de healthcheck `/up` continua respondendo 200 para monitoramento externo.*
2. **Executar a Manutenção Programada.**
3. **Desativar Modo de Manutenção:**
   ```bash
   docker exec -i bigdevz-finance-api-1 php artisan up
   ```

---

## 5. Métricas de Recuperação (RTO / RPO)

- **Recovery Point Objective (RPO):**
  - **Rotina Diária:** Máximo de 24 horas (backup diário automatizado com retenção de 30 dias).
  - **Releases de Deploy:** **Zero RPO** (snapshot compulsório criado imediatamente antes de qualquer `migrate`).
- **Recovery Time Objective (RTO):**
  - Restauração completa de banco e aplicação através do `./scripts/rollback-production.sh`: **inferior a 10 minutos**.
