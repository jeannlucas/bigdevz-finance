# Edição e Cancelamento de Lançamentos (A Pagar e A Receber) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir edição e cancelamento seguros de lançamentos financeiros cadastrados erroneamente em Contas a Pagar e Contas a Receber, tanto no Web/Desktop quanto no Mobile, mantendo 100% de integridade contábil e auditoria.

**Architecture:**
- **Backend (API):** Extensão do domínio de Recebíveis com migração para `agreements` (`cancelled_at`, `cancel_reason`, `edited_at`), Action `ChangeAgreements` para cancelamento e edição auditada de acordos em aberto (com validação estrita de ausência de recebimentos ativos), e rotas `PATCH /agreements/{id}` e `POST /agreements/{id}/cancel`.
- **Frontend (Flutter):** Atualização dos modelos e repositórios (`Agreement`, `AgreementsRepository`), inclusão de ações de cancelamento e edição no `AgreementModal` e `AgreementScreen`, e paridade no `PayableModal` para Desktop/Web com ações de cancelamento e edição de contas a pagar em aberto.

**Tech Stack:** Laravel 13 (PHP 8.3+, PostgreSQL), Flutter 3.38+ / Dart 3.10+, Testes automatizados (Pint, PHPUnit, Flutter Test).

**Spec:** [`specs/financeiro/financeiro.md`](specs/financeiro/financeiro.md) (Critérios AC-FIN-009, AC-FIN-010, AC-FIN-011, AC-FIN-017).

## Global Constraints

- Proibição estrita de float/double para valores monetários (`Money` com centavos inteiros).
- Imutabilidade contábil: nenhuma obrigação com pagamentos ou recebimentos ativos pode ser cancelada ou ter valor reduzido abaixo do liquidado sem estorno prévio.
- Segregação multi-tenant por espaço (`space_id`) contra IDOR/BOLA.
- Backpressure inegociável: `./scripts/check.sh --full` deve passar 100% verde antes de qualquer push.

---

## Task Decomposition

### Task 1: Spec Update & Backend Migration para Agreements
**Files:**
- Modify: `specs/financeiro/financeiro.md`
- Create: `apps/api/database/migrations/2026_11_09_120000_add_cancelled_at_to_agreements.php`
- Modify: `apps/api/app/Models/Agreement.php`

- [ ] Adicionar critério `AC-FIN-017` em `specs/financeiro/financeiro.md`.
- [ ] Criar migration adicionando `cancelled_at`, `cancel_reason`, `edited_at` na tabela `agreements`.
- [ ] Atualizar model `Agreement` com fillable, casts e métodos auxiliares `isCancelled()`, `receivedCents()`.

### Task 2: Backend Action ChangeAgreements & Endpoints da API
**Files:**
- Create: `apps/api/app/Actions/Receivables/ChangeAgreements.php`
- Modify: `apps/api/app/Http/Controllers/Api/AgreementController.php`
- Modify: `apps/api/app/Http/Resources/AgreementResource.php`
- Modify: `apps/api/routes/api.php`
- Test: `apps/api/tests/Feature/Receivables/AgreementCancellationAndEditTest.php`

- [ ] Escrever teste com falha em `AgreementCancellationAndEditTest.php` cobrindo cancelamento de acordo em aberto, rejeição se houver recebimento, e edição de descrição/categoria.
- [ ] Implementar `ChangeAgreements::cancel` e `ChangeAgreements::edit`.
- [ ] Implementar métodos `cancel` e `update` em `AgreementController`, e filtrar `cancelled_at IS NULL` na listagem de abertos.
- [ ] Expor novos campos em `AgreementResource` (`is_cancelled`, `cancelled_at`, `cancel_reason`).
- [ ] Registrar rotas em `routes/api.php` e rodar suíte de testes da API.

### Task 3: Mobile/Web Agreements - Repositório, Modelo e Ações de Cancelar/Editar
**Files:**
- Modify: `apps/mobile/lib/features/agreements/agreement.dart`
- Modify: `apps/mobile/lib/features/agreements/agreements_repository.dart`
- Modify: `apps/mobile/lib/features/agreements/agreement_modal.dart`
- Modify: `apps/mobile/lib/features/agreements/agreement_screen.dart`
- Test: `apps/mobile/test/features/agreement_cancel_and_edit_test.dart`

- [ ] Escrever teste de widget cobrindo visualização de status cancelado e diálogo de cancelamento/edição.
- [ ] Atualizar `Agreement` para parsear `is_cancelled`, `cancelled_at`, `cancel_reason`.
- [ ] Adicionar métodos `cancel` e `update` em `AgreementsRepository`.
- [ ] Adicionar botões "Editar" e "Cancelar conta a receber" no `AgreementModal` (Desktop/Web) e `AgreementScreen` (Mobile), com diálogo de motivo e validação.
- [ ] Validar que conta cancelada desabilita baixa e exibe badge de cancelada.

### Task 4: Mobile/Web Payables - Paridade de Ações no PayableModal (Desktop/Web)
**Files:**
- Modify: `apps/mobile/lib/features/payables/payable_modal.dart`
- Test: `apps/mobile/test/features/payable_modal_edit_test.dart`

- [ ] Escrever teste de widget para `PayableModal` validando presença e acionamento de "Editar conta" e "Cancelar conta".
- [ ] Integrar no `PayableModal` a opção de cancelar conta a pagar em aberto com diálogo de justificativa (chamando `payablesRepository.cancel`).
- [ ] Integrar no `PayableModal` modo de edição rápida de descrição, credor, valor e vencimento para contas comuns em aberto.
- [ ] Validar estado cancelado no `PayableModal` (exibição de badge cancelada e desativação de pagamentos).

### Task 5: Homologação Completa, Backpressure e Entrega
- [ ] Rodar `./scripts/check.sh --full` e garantir 0 erros em testes unitários, formatação Dart, Pint e integração API.
- [ ] Validar visualmente via Chrome DevTools / Flutter Web.
- [ ] Elaborar relatório de entrega nos 5 tópicos obrigatórios.
