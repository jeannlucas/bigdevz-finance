# BigDev.Z Finance — Transição Operacional (Handoff)

> **Data de Atualização:** 17/11/2026 10:40 (UTC-03:00)  
> **Versão em Produção:** `v1.2.0` (commit [`7af3d2d49b41836911acd9e7740ece015f9b7e86`](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/))  
> **Branch Ativa de Trabalho:** `fix/deploy-pipeline-hardening`  
> **Status Operacional:** ✅ HARDENING E RESILIÊNCIA DO PIPELINE DE DEPLOY E RECUPERAÇÃO CONCLUÍDOS COM 100% DE TESTES AUTOMATIZADOS VERDES  
> **Soberania Git:** Commits, pushes e tags sob autoridade exclusiva de Jeann Lucas. Nenhuma alteração em produção realizada.

---

## 1. Contexto e Diagnóstico das Falhas Corrigidas

Durante o incidente de deploy da release `v1.2.0`, foram identificadas vulnerabilidades operacionais na orquestração:
1. **Divergência de Projeto Compose:** Scripts esperavam o nome de projeto `bigdevz-finance`, enquanto a VPS executa os containers sob o projeto `finance-prod` (rede `finance-prod_default`, containers `finance-prod-*-1`), causando falha de resolução de hostname do banco de dados (`postgres`) em comandos efêmeros.
2. **Invocação de Opções no Cliente SSH:** O workflow do GitHub Actions (`deploy.yml`) executava `ssh ... "--tag $TAG --digest $DIGEST"` sem o separador `--`, fazendo o cliente OpenSSH interpretar incorretamente argumentos como switches do próprio cliente SSH (`exit code 255`).
3. **Permissão de Escrita em Marcadores:** O arquivo `/var/lib/vps-deploy/bigdevz-finance/implantado_digest` pertencia a `root:root` (modo 0644), gerando `Permission denied` ao final do deploy sob usuário operacional (`jeann`).
4. **Acoplamento Indevido de Trap Pós-Healthcheck:** A trap de rollback `perform_rollback` em `scripts/vps-deploy.sh` interrompia serviços saudáveis caso ocorresse qualquer erro em metadados secundários mesmo após o healthcheck `/up` já ter sido aprovado.
5. **Publicação Antecipada do Bundle Web:** A sincronização de `/srv/finance/web` ocorria antes da validação do backend, expondo o novo frontend a usuários antes que a API estivesse funcional.

---

## 2. Hardening e Soluções Implementadas

1. **Scripts de Deploy Canônico (`scripts/vps-deploy.sh`):**
   - **Resolução Consistente de Projeto:** Exportação padronizada de `COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-${PROJECT_NAME:-finance-prod}}"`.
   - **Descoberta Dinâmica de Containers:** Funções auxiliares `resolve_containers` e `get_service_container` para identificar automaticamente os containers reais de banco e API (`finance-prod-postgres-1`, `finance-prod-api-1` ou convenções do projeto).
   - **Pré-Voo Fail-Closed de Permissões:** Função `check_permissions_preflight` que valida permissão de escrita atômica em `/var/lib/vps-deploy/<projeto>` e nos marcadores (`implantado_tag`, `implantado`, `implantado_digest`, `recuperacao_pendente`) antes de parar qualquer escritor ou iniciar migrações.
   - **Pré-Voo de Infraestrutura:** Valida a presença e o status de execução do container PostgreSQL antes do snapshot.
   - **Escrita Atômica Segura:** Função `safe_write_marker` que cria arquivos temporários com `mktemp`, define permissão `0644` e executa substituição atômica (`mv -f`).
   - **Desacoplamento de Rollback Pós-Healthcheck:** Flag `DEPLOY_HEALTH_PASSED=1` protege os containers saudáveis contra parada acidental na trap `perform_rollback`.
   - **Estadiamento Coordenado da Web:** Suporte a `/srv/finance/web_staging/`, promovendo para `/srv/finance/web/` somente após confirmação 200 OK do endpoint `/up`.
2. **Wrapper SSH (`scripts/vps-deploy-wrapper.sh`):**
   - Suporte transparente a argumentos posicionais (`$1` como tag, `$2` como digest), flags nomeadas (`--tag`, `--digest`) e descarte seguro de separadores `--` passados pelo OpenSSH.
   - Suporte a execução tanto via `SSH_ORIGINAL_COMMAND` quanto por linha de comando direta.
3. **Workflow GitHub Actions (`.github/workflows/deploy.yml`):**
   - Linha de invocação SSH corrigida com `--` explícito para neutralizar parsing ambíguo de opções:
     `ssh -i ~/.ssh/deploy_key -o StrictHostKeyChecking=yes -p "$VPS_SSH_PORT" "$VPS_SSH_USER@$VPS_HOST" -- "$TAG_NAME" "$IMAGE_DIGEST"`
4. **Scripts de Suporte Operacional (`scripts/deploy-production.sh`, `scripts/rollback-production.sh`, `scripts/backup-production.sh`):**
   - Alinhamento de todos os scripts ao projeto `finance-prod`.
   - Remoção de nomes hardcoded estáticos em favor de resolução dinâmica resiliente.
   - Sincronização web direcionada a `web_staging` no `deploy-production.sh`, com swap atômico somente pós-healthcheck.
5. **Configuração Docker Compose (`docker-compose.production.yml`):**
   - Nome do projeto configurado como `name: ${COMPOSE_PROJECT_NAME:-finance-prod}`.
6. **Nova Suíte de Testes Automatizados (`tests/infra/test-deploy-hardening-preflight.sh`):**
   - Valida suporte do wrapper a argumentos com e sem `--`.
   - Valida bloqueio fail-closed no pré-voo quando marcadores não possuem permissão de escrita.
   - Valida que a trap não derruba serviços pós-healthcheck.
   - Valida sintaxe segura do workflow `deploy.yml`.
   - Integrada à suíte de qualidade obrigatória em `scripts/check.sh --full`.
7. **Documentação e Runbooks Atualizados:**
   - [`docs/operations/production-deployment.md`](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/docs/operations/production-deployment.md): Arquitetura, regras de pré-voo, projeto Compose e fluxo de staging web.
   - [`docs/operations/production-runbook.md`](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/docs/operations/production-runbook.md): Inventário de serviços atualizado e playbook `INC-07` para diagnóstico de permissões e rede Compose.

---

## 3. Comprovação de Backpressure e Testes Automatizados

Comando executado: `./scripts/check.sh --full`
- **Domínio Financeiro Puro (PHP):** 15/15 PASS (0 falhas).
- **Linter e Estilo PHP (Laravel Pint):** 167 arquivos auditados, PASS.
- **Tipagem e Análise Dart (`flutter analyze`):** 0 issues (No issues found).
- **Formatação Dart (`dart format`):** 162 arquivos formatados (0 changed).
- **Suíte Flutter (`flutter test`):** **332 testes PASS** (100% verde).
- **Suíte API Laravel (`php artisan test`):** **203 testes PASS (1.931 asserções)** em PostgreSQL real.
- **Testes de Governança SemVer (`tests/infra/test-deploy-governance.sh`):** **7/7 cenários PASS**.
- **Testes de Transição de Deploy SemVer (`tests/infra/test-vps-deploy-transition.sh`):** **3/3 cenários PASS**.
- **Testes de Hardening e Pré-Voo (`tests/infra/test-deploy-hardening-preflight.sh`):** **4/4 cenários PASS**.
- **Status Geral:** **100% VERDE (ZERO ERROS)**.

---

## 4. Estado da Produção e Salvaguardas

- **Produção Atual (`srv1884441`):** Permanece 100% intacta, ativa e saudável servindo `v1.2.0` (commit `7af3d2d49b41836911acd9e7740ece015f9b7e86`).
- **Nenhum Deploy Executado:** Nenhuma alteração foi aplicada na VPS durante esta sessão.
- **Segurança de Credenciais:** Zero credenciais lidas, impressas ou commitadas. Nenhum arquivo `.env` real tocado.

---

## 5. Próximos Passos Imediatos

1. Apresentar os resultados, arquivos alterados e comprovação de testes a Jeann Lucas.
2. Aguardar revisão humana e autorização prévia e explícita para:
   - Criação do commit na branch `fix/deploy-pipeline-hardening`.
   - Merge na branch `dev` e publicação.
