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

### INC-08: Divergência de Hash do Frontend Web (Bundle Estagnado em Produção)

Caso a verificação pós-deploy (`scripts/verify-production-release.sh`) falhe acusando divergência no SHA-256 do `main.dart.js` ou ausência de assets:

1. **Mecanismo Arquitetural de Promoção Web Atômica e Imutável:**
   - **Hash Obrigatório (`EXPECTED_WEB_HASH`):** O pipeline de deploy (`scripts/vps-deploy-wrapper.sh` e `scripts/vps-deploy.sh`) exige o argumento `--web-hash <64 hex chars>`. Caso ausente ou malformado, o deploy aborta *fail-closed* antes de parar writers, fazer backup do banco ou executar migrações.
   - **Extração Segura e Exclusiva:** O bundle é extraído para um diretório temporário isolado (`mktemp -d /srv/finance/web_staging_XXXXXX`) diretamente do digest Docker aprovado (`/opt/finance/web/.`).
   - **Validação Pré-Ativação:** Antes de qualquer alteração no banco ou nos arquivos servidos, o script valida a presença dos arquivos essenciais (`main.dart.js`, `index.html`, `flutter.js`, `manifest.json`) e confirma que `sha256sum main.dart.js` corresponde exatamente a `EXPECTED_WEB_HASH`.
   - **Primeira Conversão com Troca Atômica no Kernel:** Para a primeira transição de `/srv/finance/web` (que é um diretório real), o script:
     1. Valida previamente os pré-requisitos através de uma sonda (`.swap_probe_dir` e `.swap_probe_link`) em `web_releases/`. Se o sistema de arquivos ou o kernel não suportarem a troca atômica, aborta *fail-closed* antes de alterar o diretório ativo.
     2. Prepara a release permanente em `web_releases/<tag>` e cria o symlink temporário `${target_web}_tmp_$$`.
     3. Executa a permuta atômica no kernel via `atomic_exchange_paths` (`renameat2` com `RENAME_EXCHANGE` no Linux / `renamex_np` com `RENAME_SWAP` no macOS). O diretório real e o symlink trocam de caminho em uma operação indivisível, garantindo que em nenhum momento `/srv/finance/web` deixa de existir ou fica sem arquivos servidos, mesmo sob interrupções abruptas.
     4. Move o diretório legado (agora em `${target_web}_tmp_$$`) para `/srv/finance/web_releases/legacy`, preservando o bundle anterior para auditoria e recuperação.
   - **Deploys Subsequentes em Symlink:** Quando `/srv/finance/web` já é um symlink, a substituição atômica ocorre via `mv -Tf` (chamada atômica de `rename(2)` em nível de kernel).
   - **Replay Idempotente:** Caso o deploy seja reexecutado com a mesma tag já ativa (`IMPLANTADA_TAG == DEPLOY_TAG`) e o hash do `main.dart.js` ativo for idêntico ao esperado, o script reconhece o estado como sucesso idempotente (exit 0) sem parar serviços, sem reexecutar migrações e sem alterar arquivos.

2. **Compatibilidade dos Scripts na VPS antes do Disparo da Tag:**
   Antes de publicar qualquer nova tag SemVer, certifique-se de que os scripts instalados na VPS possuem suporte aos novos argumentos:
   ```bash
   ssh finance-prod "grep -q 'web-hash' /srv/finance/scripts/vps-deploy-wrapper.sh && grep -q 'EXPECTED_WEB_HASH' /srv/finance/scripts/vps-deploy.sh && echo 'VPS scripts compativeis com web-hash' || echo 'VPS scripts PRECISAM ser atualizados antes da tag'"
   ```
   Caso necessário atualizar os scripts da VPS antes do release:
   ```bash
   scp scripts/vps-deploy-wrapper.sh scripts/vps-deploy.sh finance-prod:/srv/finance/scripts/
   ssh finance-prod "chmod +x /srv/finance/scripts/vps-deploy*.sh"
   ```

3. **Inspecionar Hash Local vs. Remoto em Caso de Falha:**
   ```bash
   # Obter hash do main.dart.js em produção servido pelo Caddy:
   curl -s https://finance.bigdevz.com/main.dart.js | sha256sum
   # Obter marcador da última extração na VPS:
   ssh finance-prod "cat /var/lib/vps-deploy/bigdevz-finance/implantado_web_hash"
   ```

4. **Forçar Sincronização e Re-extração Manual do Frontend Web (se necessário):**
   Caso seja necessário re-promover manualmente o frontend a partir da imagem já implantada:
   ```bash
   ssh finance-prod "
     cd /srv/finance
     IMAGE_DIGEST=\$(cat /var/lib/vps-deploy/bigdevz-finance/implantado_digest)
     DEPLOY_TAG=\$(cat /var/lib/vps-deploy/bigdevz-finance/implantada_tag)
     CID=\$(docker create \"\$IMAGE_DIGEST\")
     STAGING_DIR=\$(mktemp -d /srv/finance/web_staging_manual_XXXXXX)
     docker cp \"\$CID:/opt/finance/web/.\" \"\$STAGING_DIR/\"
     docker rm -f \"\$CID\"
     chmod -R a+rX \"\$STAGING_DIR\"
     
     mkdir -p web_releases
     RELEASE_DIR=\"web_releases/\${DEPLOY_TAG}\"
     rm -rf \"\$RELEASE_DIR\"
     mv \"\$STAGING_DIR\" \"\$RELEASE_DIR\"
     ln -sfn \"\$RELEASE_DIR\" web
     sha256sum web/main.dart.js | awk '{print \$1}' > /var/lib/vps-deploy/bigdevz-finance/implantado_web_hash
     echo 'Frontend Web re-promovido com sucesso via symlink atômico!'
   "
   ```

5. **Validar Resposta Pública:**
   ```bash
   ./scripts/verify-production-release.sh --expected-sha "<SHA>" --expected-web-hash "<HASH>"
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

## SMTP de recuperação

O Postfix escuta no gateway privado da rede Docker do Finance (172.20.0.1:25)
e no loopback da VPS. A entrega externa exige TLS. O OpenDKIM assina com
o seletor finance e o único remetente autorizado é recuperacao@mail.finance.bigdevz.com.

A HostGator publica SPF, DKIM e DMARC em mail.finance.bigdevz.com.
Se o gateway Docker mudar, alinhe a escuta do Postfix, a regra do firewall
e MAIL_HOST no Compose. Se o IP público mudar, revise o SPF, a saída na
porta 25 e o DNS reverso.
