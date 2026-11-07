# Especificação Permanente da Capability de Empréstimos (Empréstimos e Financiamentos)

> **Capability:** `emprestimos`<br>
> **Status:** Ativo / Canônico<br>
> **Referência de Governança:** `~/AGENTS.md`, `specs/README.md`, `specs/financeiro/financeiro.md`, ADRs `0001` a `0006`.<br>
> **Regra de Ouro:** O código e os testes respondem a esta especificação; qualquer divergência (*drift*) é considerada defeito de primeira classe.

---

## 1. Visão Geral da Capability

A capability **Empréstimos** gerencia contratos de obrigações financeiras de médio e longo prazo do usuário no espaço selecionado (PF ou PJ), cobrindo:
1. **Empréstimos Tomados (*passivo / dívida*):** Recursos captados junto a instituições financeiras ou terceiros.
2. **Empréstimos Concedidos (*ativo / direito*):** Recursos disponibilizados a terceiros com expectativa de reembolso.

O módulo atua como orquestrador patrimonial de alto nível: registra o desembolso do principal na conta bancária no marco inicial e integra-se diretamente aos motores de liquidação de fluxo de caixa existentes no sistema (`Payable` para parcelas a pagar em tomados; `Agreement` para parcelas a receber em concedidos).

---

## 2. Critérios de Aceite Numerados (AC-EMP)

### 2.1. Regras Fundamentais e Invariantes Contábeis

- **AC-EMP-001 [Classificação Bipolar e Invariantes do Contrato]:**
  - O empréstimo possui classificação obrigatória `kind`:
    - `'taken'` (tomado): passivo financeiro que gera compromisso a pagar (`payable`).
    - `'granted'` (concedido): ativo financeiro que gera direito a receber (`agreement`).
  - O valor principal (`principal_cents`) e o valor total com encargos (`total_cents`) são obrigatórios, inteiros em centavos, maiores que zero e limitados a `Money::MAX_CENTS` (`99999999999999`).
  - O valor total deve ser maior ou igual ao principal (`total_cents >= principal_cents`), refletindo encargos/juros não-negativos (`interest_cents = total_cents - principal_cents >= 0`).
  - O número de parcelas (`installment_count`) deve estar compreendido entre 1 e 1.200.

- **AC-EMP-002 [Desembolso Inicial Opcional e Atomicidade Contábil]:**
  - A criação do empréstimo pode incluir opcionalmente uma conta bancária de liquidação inicial (`disbursement_account_id`) e data de efetivação (`disbursed_at`).
  - Quando a conta de desembolso for informada:
    1. Se `kind == 'taken'`: o valor do principal é creditado na conta (`amount_cents = +principal_cents`).
    2. Se `kind == 'granted'`: o valor do principal é debitado da conta (`amount_cents = -principal_cents`).
    3. Ambas as movimentações recebem vínculo com `loan_disbursement_id` em `account_movements` na mesma transação atômica (`DB::transaction`).
  - Se a conta de desembolso for omitida (empréstimos históricos contratados antes do início do controle no app), nenhuma movimentação em `account_movements` é gerada.

- **AC-EMP-003 [Integração Nativa aos Motores de Amortização]:**
  - Para `kind == 'taken'`:
    - Cria atomicamente um `Payable` correspondente no espaço com `kind = 'installment'`, total igual a `loan.total_cents` e divisão das parcelas pelo motor já existente.
    - O empréstimo armazena a referência `payable_id`.
    - O saldo devedor do empréstimo em qualquer momento é derivado de `total_cents - payable.paid_cents`.
  - Para `kind == 'granted'`:
    - Cria atomicamente um `Agreement` no espaço com valor total igual a `loan.total_cents` e divisão determinística de parcelas.
    - O empréstimo armazena a referência `agreement_id`.
    - O saldo pendente a receber em qualquer momento é derivado de `total_cents - agreement.received_cents`.

---

### 2.2. Isolamento, Segurança e Concorrência

- **AC-EMP-004 [Isolamento Multi-Tenant e Prevenção IDOR]:**
  - O empréstimo e todas as entidades vinculadas (conta de desembolso, payable, agreement) devem pertencer estritamente ao mesmo `space_id` do usuário autenticado.
  - Tentativas de consultar, criar ou vincular recursos de outros espaços ou usuários respondem estritamente `404 Not Found`.

- **AC-EMP-005 [Validação de Status e Marco de Abertura da Conta]:**
  - Quando informada, a conta de desembolso não pode estar arquivada (`archived_at !== null`).
  - A data de desembolso (`disbursed_at`) não pode ser anterior à data de abertura (`opening_balance_date`) da conta selecionada (`422 Unprocessable Entity`).
  - A data de desembolso não pode ser posterior ao vencimento da primeira parcela (`disbursed_at <= first_due_date`).

- **AC-EMP-006 [Locks Transacionais sob Concorrência]:**
  - Ao registrar o desembolso na conta bancária, a conta é bloqueada com `lockForUpdate()`.
  - Validação de saldo resultante para evitar underflow abaixo de `-Money::MAX_CENTS` ou overflow acima de `Money::MAX_CENTS`.

---

### 2.3. Idempotência e Interface Multiplataforma

- **AC-EMP-007 [Idempotência Persistida por Chave]:**
  - O endpoint de criação `POST /api/spaces/{space}/loans` exige o cabeçalho `Idempotency-Key`.
  - Replay idêntico devolve `HTTP 200 OK` com `replayed: true` e a representação atualizada do empréstimo sem duplicar desembolsos ou parcelas.
  - Replay conflitante devolve `HTTP 409 Conflict`.

- **AC-EMP-008 [Interface Unificada Multiplataforma (iOS, Android e Web)]:**
  - Tela de consulta e acompanhamento de empréstimos com visual fintech, exibindo status (`active`, `settled`), saldo devedor e taxa/encargos embutidos.
  - Formulário acessível de contratação com cálculo dinâmico de juros/encargos, seleção de tipo, conta de desembolso e data.
  - Suporte responsivo a telas estreitas (320pt) sob escalas ampliadas de acessibilidade (150% e 200%) sem estouro de layout.

---

## 3. Casos de Borda e Validações

| Cenário de Borda | Entrada | Comportamento Esperado | Código HTTP |
| :--- | :--- | :--- | :--- |
| Total menor que principal | `total: "1000.00"`, `principal: "1200.00"` | Rejeição de inconsistência de juros | `422 Unprocessable Entity` |
| Parcelas inválidas | `installment_count: 0` ou `> 1200` | Rejeição por limite de parcelas | `422 Unprocessable Entity` |
| Conta arquivada | Conta selecionada com `archived_at != null` | Rejeição de conta inativa | `422 Unprocessable Entity` |
| Desembolso pré-abertura | `disbursed_at < opening_balance_date` | Rejeição de violação cronológica | `422 Unprocessable Entity` |
| Desembolso pós-vencimento | `disbursed_at > first_due_date` | Rejeição de cronograma invertido | `422 Unprocessable Entity` |
| Conta de outro espaço | ID de conta de outro `space_id` | Proteção contra IDOR | `404 Not Found` |
| Replay divergente | Mesma chave com dados diferentes | Conflito de idempotência | `409 Conflict` |
| Replay idêntico | Mesma chave com dados iguais | Replay idempotente com `replayed: true` | `200 OK` |

---

## 4. Matriz de Rastreabilidade (Spec ↔ Código ↔ Testes)

| Critério de Aceite | Implementação (Backend / Mobile) | Testes Automatizados |
| :--- | :--- | :--- |
| **AC-EMP-001** | `apps/api/app/Actions/Loans/CreateLoan.php`, `apps/api/app/Models/Loan.php` | `apps/api/tests/Feature/LoansTest.php` |
| **AC-EMP-002** | `apps/api/app/Actions/Loans/CreateLoan.php` | `apps/api/tests/Feature/LoansTest.php` |
| **AC-EMP-003** | `apps/api/app/Actions/Loans/CreateLoan.php` | `apps/api/tests/Feature/LoansTest.php` |
| **AC-EMP-004** | `apps/api/app/Http/Controllers/Api/LoanController.php` | `apps/api/tests/Feature/LoansTest.php` |
| **AC-EMP-005** | `apps/api/app/Actions/Loans/CreateLoan.php` | `apps/api/tests/Feature/LoansTest.php` |
| **AC-EMP-006** | `apps/api/app/Actions/Loans/CreateLoan.php` | `apps/api/tests/Feature/LoansTest.php` |
| **AC-EMP-007** | `apps/api/app/Actions/Receivables/IdempotentOperations.php` | `apps/api/tests/Feature/LoansTest.php` |
| **AC-EMP-008** | `apps/mobile/lib/features/loans/loans_screen.dart`, `loan_form_screen.dart` | `apps/mobile/test/features/loans_test.dart` |
