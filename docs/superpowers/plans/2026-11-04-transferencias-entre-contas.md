# Plano de Implementação — Transferências entre Contas

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar transferência atômica de valores entre contas do mesmo espaço financeiro (PF ou PJ), garantindo precisão monetária sem float, concorrência segura imune a deadlocks, idempotência e interface acessível multiplataforma (iOS, Android e Web).

**Architecture:** Monólito modular Laravel 13 servindo endpoint REST com `Idempotency-Key` persistido e lock pessimista ordenado por ID (`lockForUpdate`). Movimentações espelhadas no livro contábil (`account_movements`). App Flutter unificado consumindo a API com formulário responsivo e acessível.

**Tech Stack:** Laravel 13, PostgreSQL 18, PHP 8.3 / BCMath, Flutter 3.47.x / Dart 3.13.x.

**Spec:** [`specs/transferencias/transferencias.md`](../../specs/transferencias/transferencias.md)

---

## Global Constraints

- Proibição estrita de `float`/`double` para dinheiro (`AC-FIN-001`, `AC-TRF-006`).
- Preservação da suíte de testes existente (166 testes Flutter e 86 testes Laravel em PostgreSQL real, 100% verde).
- Governança de branch: trabalho isolado na branch `feature/transferencias-entre-contas`.
- Backpressure obrigatório: `bash scripts/check.sh --full` deve passar com zero erros antes de qualquer entrega.
- Zero credenciais rastreadas ou segredos expostos.

---

## Review Focus

1. Atomicidade e consistência contábil (saída na origem e entrada no destino no mesmo commit de banco).
2. Ordem determinística de locks (`min(id)` depois `max(id)`) para eliminação de risco de deadlock.
3. Isolamento multi-tenant estrito (IDOR resulta em `404 Not Found`).
4. Rejeição de contas idênticas ou arquivadas e validação da data mínima de abertura.
5. Idempotência persistida com detecção de replay idêntico e conflito de payload.
6. Acessibilidade e responsividade da interface no Flutter (320pt em 150% e 200%).

---

## Tarefas de Implementação

### Tarefa 1: Banco de Dados e Modelagem da Transferência (Backend)
- [x] **1.1 Escrever migration de `transfers` e atualização de `account_movements`:**
  - Criar `database/migrations/YYYY_MM_DD_HHMMSS_create_transfers_table.php`:
    - `id` (bigIncrements)
    - `space_id` (foreignId com cascade, FK composta com espaço)
    - `source_account_id` (foreignId para accounts)
    - `destination_account_id` (foreignId para accounts)
    - `amount_cents` (unsignedBigInteger com check `> 0` e `<= Money::MAX_CENTS`)
    - `transferred_at` (date)
    - `notes` (string nullable)
    - `user_id` (foreignId para users)
    - `timestamps`
  - Adicionar coluna `transfer_id` nullable em `account_movements` com FK para `transfers.id`.
- [x] **1.2 Criar Model `Transfer` e atualizar `AccountMovement`:**
  - Criar `apps/api/app/Models/Transfer.php` com casts de data e centavos inteiros, e relacionamentos (`sourceAccount`, `destinationAccount`, `space`, `user`, `movements`).
  - Atualizar `apps/api/app/Models/AccountMovement.php` adicionando `transfer_id` no `$fillable` e relação `transfer()`.
- [x] **1.3 Executar migration em ambiente de teste:**
  - Validar integridade do schema no PostgreSQL de teste.

### Tarefa 2: Action `TransferFunds` e Regras de Domínio (TDD)
- [x] **2.1 Escrever teste reproduzível em `apps/api/tests/Feature/TransfersTest.php`:**
  - Testes cobrindo:
    - Transferência bem-sucedida entre duas contas gerando débito na origem e crédito no destino.
    - Rejeição se origem e destino forem a mesma conta (`422`).
    - Rejeição se alguma conta estiver arquivada (`422`).
    - Rejeição se a data da transferência for anterior à data de abertura de qualquer das contas (`422`).
    - Rejeição se o valor for `<= 0` ou ultrapassar limites suportados (`422`).
    - Bloqueio ordenado por ID para prevenção de deadlocks.
    - Isolamento multi-tenant: 404 se tentar transferir conta de outro espaço ou outro usuário.
    - Idempotência: replay idêntico retorna 200 (`replayed: true`), payload conflitante retorna 409.
- [x] **2.2 Executar o teste e comprovar falha inicial (Delta Provado):**
  - Confirmar que o teste falha com rota inexistente / Action não implementada.
- [x] **2.3 Implementar a Action `apps/api/app/Actions/Transfers/TransferFunds.php`:**
  - Integrar com `IdempotentOperations` (`OPERATION_TRANSFER`).
  - Ordenar IDs: `$orderedIds = [$sourceId, $destinationId]; sort($orderedIds);`.
  - Lock pessimista: `Account::query()->where('space_id', $space->id)->whereIn('id', $orderedIds)->orderBy('id')->lockForUpdate()->get()`.
  - Validações de negócio e cálculo seguro de saldo.
  - Persistir `Transfer` e os 2 registros espelhados em `AccountMovement`.
- [x] **2.4 Criar Controller `TransferController` e registrar rotas em `routes/api.php`:**
  - `POST /api/spaces/{space}/transfers` protegido pelo middleware de autenticação e idempotência.
- [x] **2.5 Executar a suíte de testes de transferências:**
  - Validar que todos os cenários passam no PostgreSQL real descartável.

### Tarefa 3: Integração no App Flutter (Mobile e Web)
- [x] **3.1 Criar cliente de API e DTO de transferência em `apps/mobile/lib/features/transfers/`:**
  - DTO para payload de criação (`TransferRequest`) com valor formatado em string decimal e chave de idempotência.
  - Método no `ApiClient` ou service dedicado.
- [x] **3.2 Escrever testes de widget para o formulário de transferência:**
  - Criar `apps/mobile/test/features/transfer_form_test.dart`:
    - Renderização dos seletores de conta.
    - Validação de que conta de destino não pode ser a mesma da origem.
    - Formatação correta do valor monetário via `MoneyInputFormatter`.
    - Resiliência de layout em viewport de 320pt com escalas de 150% e 200%.
- [x] **3.3 Implementar `TransferFormScreen` (`apps/mobile/lib/features/transfers/transfer_form_screen.dart`):**
  - Componentes de UI semânticos, cabeçalho adaptativo, botões de ação e mensagens claras de erro e sucesso.
- [x] **3.4 Conectar botão "Transferir" na interface do usuário:**
  - Adicionar atalho/ação rápida na aba de Carteira de Contas (`AccountsTab`) e no Dashboard (`SummaryTab` / `HomeShell`).
- [x] **3.5 Executar suíte de testes Flutter:**
  - `flutter test` cobrindo novos testes e regressão nos 166 testes existentes.

### Tarefa 4: Backpressure Completo e Verificação Pré-Push
- [x] **4.1 Rodar suíte determinística de qualidade:**
  - `bash scripts/check.sh --full` (100% verde: PHP domain, Pint, Flutter analyze, Dart format, Flutter test, Laravel feature tests).
- [x] **4.2 Revisar `git diff` e preparar relatório de entrega:**
  - Garantir ausência de arquivos desnecessários ou segredos.
