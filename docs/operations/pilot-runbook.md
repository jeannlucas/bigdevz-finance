# Runbook Operacional: Piloto Controlado BigDev.Z Finance

> **Aplicação:** BigDev.Z Finance  
> **Fase:** Piloto Controlado com Usuários Reais  
> **Objetivo:** Operação segura, observabilidade em tempo real, mitigação de incidentes e plano determinístico de rollback.

---

## 1. Critérios de Entrada no Piloto (Entry Gate)
- [x] Quality Gate automatizado (`./scripts/check.sh --full`) 100% verde com ZERO erros e ZERO warnings.
- [x] Zero credenciais reais versionadas em código ou repositório.
- [x] Zero manipulação de dinheiro com ponto flutuante (*Zero Float* — centavos inteiros de 64 bits).
- [x] Restrições compostas `(id, space_id)` em PostgreSQL garantindo isolamento multi-tenant intransponível.
- [x] Chave de idempotência obrigatória para mutações financeiras.
- [x] Auditoria indelével para estornos, cancelamentos e alterações em `obligation_changes`.
- [x] Trava de período contábil fechado (`closed_until`) ativa e testada.
- [x] RBAC por organização testado (Administrador, Financeiro, Operador, Contador).
- [x] Rastreabilidade de requisições com `X-Request-ID` em todas as rotas.
- [x] Health check com monitoramento de banco (`/api/health`).
- [x] Procedimento de backup e restauração testado e validado.

---

## 2. Checklist Pré-Deploy
1. **Configuração do Host:**
   - Garantir que as portas mapeadas (`5440` para PostgreSQL, `8000` para API) não colidam com serviços locais ativos (`lsof -i :8000`, `lsof -i :5440`).
2. **Ambiente `.env`:**
   - Provisionar variáveis do host sem comitar valores reais.
   - Definir `APP_ENV=production` e `APP_DEBUG=false`.
   - Gerar `APP_KEY` seguro (`php artisan key:generate --show`).
   - Configurar `BIGDEVZ_DB_PASSWORD` complexa.
3. **Migrações de Banco:**
   - Executar migrações pendentes em modo não destrutivo: `php artisan migrate --force`.
   - Nunca executar `migrate:fresh` ou `migrate:reset`.

---

## 3. Checklist Pós-Deploy e Observabilidade
1. **Verificação de Saúde (Liveness & Readiness):**
   ```bash
   curl -i http://127.0.0.1:8000/api/health
   # Deve retornar HTTP 200 com status "ok" e database "ok"
   ```
2. **Monitoramento de Logs e Erros:**
   - Inspecionar logs da API:
     ```bash
     docker compose logs -f api
     ```
   - Garantir que nenhuma linha de log contenha senhas, tokens, dados completos de cartão ou conteúdo integral de OFX.
3. **Monitoramento do Agendador de Obrigações (Scheduler):**
   ```bash
   docker compose logs -f scheduler
   ```

---

## 4. Procedimento de Rollback Determinístico
Caso ocorra qualquer instabilidade crítica ou anomalia contábil durante o piloto:

1. **Ativar Modo de Manutenção Imediato:**
   ```bash
   docker compose exec -T api php artisan down --render="errors.503" --secret="manutencao-segura-bigdevz"
   ```
2. **Interromper Agendador e Processamento em Fila:**
   ```bash
   docker compose stop scheduler
   ```
3. **Reversão de Código / Imagem:**
   - Fazer checkout do commit estável anterior:
     ```bash
     git checkout <hash-versao-anterior>
     ```
   - Reiniciar containers:
     ```bash
     docker compose up -d --build api scheduler
     ```
4. **Reversão de Banco de Dados (se necessário):**
   - Restaurar o dump prévio conforme [`docs/operations/backup-and-restore.md`](backup-and-restore.md).
5. **Reabertura da Aplicação:**
   ```bash
   docker compose exec -T api php artisan up
   ```

---

## 5. Protocolo de Resposta a Incidentes

| Severidade | Descrição do Incidente | Ação Imediata | Responsável |
| :--- | :--- | :--- | :--- |
| **P0 (Crítico)** | Divergência de saldo contábil, tentativa de invasão IDOR ou indisponibilidade de banco. | 1. Ativar modo de manutenção imediato.<br>2. Capturar snapshot dos logs forenses.<br>3. Notificar Jeann Lucas.<br>4. Executar rollback se a causa não for transitória. | Tech Lead / Jeann Lucas |
| **P1 (Alto)** | Falha no upload/parsing de arquivo OFX ou lentidão em consultas de fluxo de caixa. | 1. Isolar arquivo com erro para testes em sandbox.<br>2. Verificar logs de `X-Request-ID`.<br>3. Aplicar hotfix com TDD. | QA Lead / Tech Lead |
| **P2 (Médio)** | Inconsistência de layout ou erro de validação em campos de filtros. | 1. Registrar ticket.<br>2. Corrigir na próxima iteração da branch `feature/fix`. | Desenvolvedor |

---

## 6. Critérios de Saída do Piloto (Exit Gate para Produção Ampla)
1. 14 dias consecutivos de operação em piloto sem nenhum incidente P0/P1.
2. 100% de conciliações OFX e baixas parciais auditadas sem descontinuidade de centavos.
3. Trilha de auditoria e período contábil fechado validados por gestor e contador.
4. Teste de restauração em disaster recovery executado e aprovado com RTO < 15 min e RPO < 1 hora.
