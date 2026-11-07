# Plano de Implementação — Empréstimos e Financiamentos

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar o módulo de Empréstimos (tomados e concedidos) no BigDev.Z Finance com cálculo de saldo devedor, desembolso contábil atômico, integração aos motores de parcelas existentes (`Payable` e `Agreement`), idempotência e suporte completo e unificado a iOS, Android e Web.

**Architecture:** Monólito modular Laravel 13 com endpoint REST protegido por `Idempotency-Key` e locks transacionais. Integração com livro contábil (`account_movements`) e entidades de compromissos. App Flutter com tela de gestão e formulário acessível responsivo.

**Tech Stack:** Laravel 13, PostgreSQL 18, PHP 8.3 / BCMath, Flutter 3.47.x / Dart 3.13.x.

**Spec:** [`specs/emprestimos/emprestimos.md`](../../specs/emprestimos/emprestimos.md)

---

## Global Constraints

- Proibição estrita de `float`/`double` para dinheiro (`AC-FIN-001`, `AC-EMP-001`).
- Preservação da suíte de testes existente (171 testes Flutter e 87 testes Laravel em PostgreSQL real, 100% verde).
- Governança de branch: trabalho isolado na branch `feature/emprestimos`.
- Backpressure obrigatório: `bash scripts/check.sh --full` deve passar com zero erros.
- Zero credenciais rastreadas ou segredos expostos.

---

## Tarefas de Implementação

### Tarefa 1: Banco de Dados e Modelagem de Empréstimos (Backend)
- [x] **1.1 Escrever migration `create_loans_table.php`:**
  - Criar `database/migrations/YYYY_MM_DD_HHMMSS_create_loans_table.php`:
    - Tabela `loans` com chaves estrangeiras compostas para `spaces`, `users`, `accounts` (desembolso), `payables` e `agreements`.
    - Restrições `CHECK`: `kind IN ('taken', 'granted')`, `principal_cents > 0`, `total_cents >= principal_cents`, `installment_count BETWEEN 1 AND 1200`.
    - Adicionar coluna `loan_disbursement_id` nullable em `account_movements` e atualizar `account_movements_source_check`.
    - Adicionar coluna `loan_id` nullable em `idempotency_keys` e atualizar checks de `operation` e `status`.
- [x] **1.2 Criar Model `Loan` e atualizar `AccountMovement` e `IdempotencyKey`:**
  - Criar `apps/api/app/Models/Loan.php` com casts de inteiros e datas e relacionamentos (`space`, `user`, `disbursementAccount`, `payable`, `agreement`, `disbursementMovement`).
  - Atualizar `apps/api/app/Models/AccountMovement.php` e `apps/api/app/Models/IdempotencyKey.php`.
  - Atualizar `apps/api/app/Actions/Receivables/IdempotentOperations.php` (`OPERATION_LOAN`).
- [x] **1.3 Executar migration em ambiente de teste:**
  - Validar integridade do schema no PostgreSQL de teste via Docker Compose.

### Tarefa 2: Action `CreateLoan` e Regras de Domínio (TDD)
- [x] **2.1 Escrever teste reproduzível em `apps/api/tests/Feature/LoansTest.php`:**
  - Testes cobrindo:
    - Criação de empréstimo tomado com desembolso em conta corrente gerando crédito no saldo e `Payable` com parcelas.
    - Criação de empréstimo concedido com desembolso gerando débito no saldo e `Agreement` com parcelas a receber.
    - Criação de empréstimo sem desembolso inicial (empréstimo histórico).
    - Validação de regras: total menor que principal (`422`), parcelas inválidas (`422`), conta arquivada (`422`).
    - Validação de marco temporal: desembolso anterior à abertura da conta (`422`) ou posterior ao primeiro vencimento (`422`).
    - Isolamento multi-tenant e proteção contra IDOR (404 em contas de outro espaço).
    - Idempotência: replay idêntico retorna 200 com `replayed: true`, payload divergente retorna 409.
- [x] **2.2 Executar o teste e comprovar falha inicial (Delta Provado):**
  - Confirmar falha esperada pela ausência de rota/Action.
- [x] **2.3 Implementar a Action `apps/api/app/Actions/Loans/CreateLoan.php`:**
  - Validações de limites e concorrência com lock pessimista na conta de desembolso.
  - Orquestração atômica de criação de `Loan`, movimentação no livro razão e geração das obrigações correspondentes.
- [x] **2.4 Implementar `LoanController`, `LoanResource` e rotas em `routes/api.php`:**
  - `GET /api/spaces/{space}/loans` e `POST /api/spaces/{space}/loans`.
- [x] **2.5 Executar a suíte de testes de empréstimos:**
  - Validar aprovação completa dos testes de Feature.

### Tarefa 3: Interface no App Flutter (Mobile e Web)
- [x] **3.1 Criar DTOs e Repositório `LoansRepository` em `apps/mobile/lib/features/loans/`:**
  - Modelos `Loan`, `LoanKind` e métodos `list(spaceId)` e `create(...)`.
  - Registro de Provider em `bootstrap.dart`.
- [x] **3.2 Escrever testes de widget para listagem e formulário de empréstimos:**
  - Criar `apps/mobile/test/features/loans_test.dart`:
    - Listagem separando tomados e concedidos e exibindo saldo devedor/ativo.
    - Formulário com cálculo dinâmico de juros, validação e envio.
    - Teste de reflow 320pt sob escalas de 150% e 200%.
- [x] **3.3 Implementar `LoansScreen` e `LoanFormScreen`:**
  - Telas com visual fintech, cards modernos de progresso, máscaras monetárias sem float e semântica acessível.
- [x] **3.4 Integrar atalho de Empréstimos na navegação:**
  - Atalho em Carteira de Contas (`AccountsTab`) e menu de ações.
- [x] **3.5 Executar testes Flutter:**
  - `flutter test` garantindo regressão zero e aprovação de todos os testes novos e existentes.

### Tarefa 4: Backpressure Completo e Verificação Pré-Push
- [x] **4.1 Rodar suíte determinística de qualidade:**
  - `bash scripts/check.sh --full` (100% verde).
- [x] **4.2 Revisar `git diff` e preparar relatório de entrega:**
  - Ausência de arquivos desnecessários ou segredos.
