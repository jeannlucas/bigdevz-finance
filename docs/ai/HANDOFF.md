# BigDev.Z Finance — Transição Operacional (Handoff)

> **Atualizado em:** 2026-11-18
> **Última versão de produção registrada:** `v1.2.1` (commit `4153d43a571b0d9197544682c981d8c66d2455fb`)
> **Digest Homologado em Produção:** `ghcr.io/jeannlucas/bigdevz-finance-api@sha256:799e4b8998f117a8c078d8872db53a44b3b4728b2ea60c70c21e48d02c926f5a`
> **Branch ativa:** `dev`; a atualização deste handoff será publicada somente em `dev`
> **Status Operacional:** ✅ RELEASE v1.2.1 PUBLICADA E IMPLANTADA EM PRODUÇÃO COM 100% DE SUCESSO E BACKPRESSURE TOTAL
> **Soberania Git:** Commits, pushes e tags sob autoridade exclusiva de Jeann Lucas. Produção validada e íntegra.

---

## 1. O que foi feito nesta sessão

1. **Confirmação do Merge e Proveniência do PR #11:**
   - PR [#11](https://github.com/jeannlucas/bigdevz-finance/pull/11) integrado com sucesso na `main` por Jeann Lucas via "Create a merge commit".
   - Commit de merge: `4153d43a571b0d9197544682c981d8c66d2455fb` (pais: `7af3d2d` e `144ae05`).
   - Checks de CI da `main` no GitHub Actions 100% aprovados.

2. **Quality Gate Local Completo:**
   - Executado `./scripts/check.sh --full` no Mac: 10/10 etapas aprovadas (Domínio PHP, Pint, Dart format, Flutter analyze, Flutter test com 332 testes, Laravel API com 203 testes em PostgreSQL real, 7 testes de governança SemVer, 3 testes de transição, 8 testes de hardening e simulação integrada E2E).

3. **Atualização Prévia e Segura na VPS:**
   - Sincronizado o repositório em `/srv/finance` na VPS com a nova `main` (`4153d43`) via `git fetch origin main && git pull origin main`, garantindo a presença dos scripts corrigidos (`finance-prod`, `--` no wrapper, pré-voo fail-closed de permissões) antes do acionamento.

4. **Publicação da Tag `v1.2.1`:**
   - Criada tag anotada `v1.2.1` apontando para o commit de merge `4153d43a571b0d9197544682c981d8c66d2455fb`.
   - Barreira Git pré-push executou `./scripts/check.sh --full` e liberou o push.
   - Tag publicada com sucesso para `origin`.

5. **Deploy Canônico Concluído na VPS:**
   - Imagem imutável `ghcr.io/jeannlucas/bigdevz-finance-api@sha256:799e4b8998f117a8c078d8872db53a44b3b4728b2ea60c70c21e48d02c926f5a` construída pelo GitHub Actions e baixada na VPS.
   - Pré-voo de permissões e de infraestrutura PostgreSQL aprovados.
   - Parada controlada dos escritores (`api` e `scheduler`).
   - Snapshot preventivo binário consistente gerado em `/srv/finance/backups/db/pre_deploy_OpxKeyZG` (169KB) com validação `pg_restore --list` (349 TOC entries) e checksum SHA-256 verificado.
   - Migrations executadas sem pendências ("Nothing to migrate").
   - Containers recriados com a nova imagem sob o projeto `finance-prod`.
   - Healthcheck `/up` aprovado com 200 OK.
   - Marcadores atômicos atualizados para `v1.2.1`, commit `4153d43` e digest imutável.
   - Trava de recuperação removida com sucesso.

---

## 2. Onde paramos exatamente

- **Versão Ativa em Produção:** `v1.2.1`.
- **Commit Ativo em Produção:** `4153d43a571b0d9197544682c981d8c66d2455fb`.
- **Digest Ativo em Produção:** `ghcr.io/jeannlucas/bigdevz-finance-api@sha256:799e4b8998f117a8c078d8872db53a44b3b4728b2ea60c70c21e48d02c926f5a`.
- **Status dos Serviços:**
  * `finance-prod-api-1`: Ativo e Saudável (`Up`, `healthy`, porta `8510->8000`).
  * `finance-prod-scheduler-1`: Ativo (`Up`, comando `php artisan schedule:work`).
  * `finance-prod-postgres-1`: Ativo e Saudável (`Up 10 hours`, `healthy`, porta `5432`).
  * `Caddy`: Servindo HTTPS em `https://finance.bigdevz.com/` com HTTP 200.
- **Integridade Contábil Auditada:**
  * 2 espaços, 1 usuário, 8 contas, 255 contas a pagar, 21 acordos, 78 movimentações de conta, 75 parcelas, 52 pagamentos, 21 recebimentos e 2 transferências preservados integralmente.
- **CI econômico:** PRs para `dev` usam o gate pré-push local; a promoção para `main` e o SHA final continuam validados no GitHub Actions (run `44433081350`).

---

## 3. Próximos Passos Imediatos

1. Planejar as próximas tarefas de negócio/produto a partir da `dev`.

---

## 4. Comandos para Auditoria e Conferência

```bash
# Conferir status e integridade do Git
git status
git log -n 3 --oneline

# Conferir o CI do commit publicado na main
gh run list --branch main --limit 3

# Executar a validação local completa
./scripts/check.sh --full
```
