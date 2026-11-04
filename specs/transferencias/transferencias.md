# Especificação Permanente da Capability de Transferências (Transferências entre Contas)

> **Capability:** `transferencias`<br>
> **Status:** Ativo / Canônico<br>
> **Referência de Governança:** `~/AGENTS.md`, `specs/README.md`, `specs/financeiro/financeiro.md`, ADRs `0001` a `0006`.<br>
> **Regra de Ouro:** O código e os testes respondem a esta especificação; qualquer divergência (*drift*) é considerada defeito de primeira classe.

---

## 1. Visão Geral da Capability

A capability **Transferências entre Contas** viabiliza a movimentação de recursos financeiros entre diferentes contas patrimoniais pertencentes ao mesmo espaço (PF ou PJ) do usuário. A operação garante integridade contábil estrita através de lançamentos espelhados no livro razão (`account_movements`), concorrência segura protegida contra *deadlocks* via ordenação de chaves primárias e persistência idempotente.

---

## 2. Critérios de Aceite Numerados (AC-TRF)

### 2.1. Regras Fundamentais e Invariantes Contábeis

- **AC-TRF-001 [Atomicidade e Movimentações Espelhadas]:**
  - A transferência gera obrigatoriamente um registro principal na tabela `transfers` (`space_id`, `source_account_id`, `destination_account_id`, `amount_cents`, `transferred_at`, `notes`, `user_id`).
  - Gera simultaneamente exatamente 2 registros no livro contábil `account_movements` na mesma transação atômica do banco:
    1. Saída na conta de origem: `amount_cents = -valor`
    2. Entrada na conta de destino: `amount_cents = +valor`
  - Ambos os registros de movimentação associam-se à chave estrangeira `transfer_id` e à mesma data contábil (`effective_date = transferred_at`).
  - A operação é estritamente atômica: se qualquer validação falhar, nenhuma alteração em tabelas ou saldos é persistida (rollback integral).

- **AC-TRF-002 [Prevenção Determinística de Deadlock sob Concorrência]:**
  - Ambas as contas envolvidas (origem e destino) são bloqueadas sob lock pessimista (`lockForUpdate()`) antes de qualquer mutação.
  - Para evitar travamento mútuo (*deadlock*) em transferências simultâneas de A para B e de B para A, o bloqueio das contas ocorre estritamente em ordem crescente de seus identificadores numéricos: `id_menor = min(source_id, destination_id)` seguido por `id_maior = max(source_id, destination_id)`.

- **AC-TRF-003 [Contas Distintas e Validação de Contas]:**
  - A conta de origem e a conta de destino não podem ser a mesma entidade (`source_account_id !== destination_account_id`). Tentativa de transferir para a mesma conta resulta em `422 Unprocessable Entity`.
  - Nenhuma das contas envolvidas pode estar arquivada (`archived_at !== null`). Caso qualquer uma esteja arquivada, a operação é rejeitada com `422 Unprocessable Entity`.

---

### 2.2. Isolamento, Segurança e Marco Temporal

- **AC-TRF-004 [Isolamento Multi-Tenant Estrito e Prevenção IDOR]:**
  - Ambas as contas (origem e destino) devem obrigatoriamente pertencer ao `space_id` indicado na requisição e associado ao usuário autenticado.
  - Se a conta de origem ou destino pertencer a outro espaço ou outro usuário, a API responde `404 Not Found` imediato, sem vazar a existência do recurso.

- **AC-TRF-005 [Marco Temporal de Abertura de Conta]:**
  - A data da transferência (`transferred_at`) não pode ser anterior à data de abertura (`opening_balance_date`) de nenhuma das duas contas envolvidas.
  - Se `transferred_at < source_account.opening_balance_date` ou `transferred_at < destination_account.opening_balance_date`, a operação é rejeitada com `422 Unprocessable Entity`.

---

### 2.3. Integridade Monetária e Cheque Especial

- **AC-TRF-006 [Precisão Monetária Sem Float e Limites Suportados]:**
  - O valor transita na API e na UI exclusivamente como string decimal canônica de duas casas (ex.: `"250.00"`), convertida para centavos inteiros (`25000`).
  - O valor deve ser estritamente positivo (`amount_cents > 0`) e menor ou igual ao teto individual `Money::MAX_CENTS` (`99999999999999` centavos).
  - A conta de origem pode ficar com saldo negativo (conforme Decisão 0006 de cheque especial), desde que o saldo resultante não seja inferior a `-Money::MAX_CENTS`.
  - O saldo resultante da conta de destino não pode exceder `+Money::MAX_CENTS`. Violações de limites resultam em `422 Unprocessable Entity`.

---

### 2.4. Idempotência e Suporte Multiplataforma

- **AC-TRF-007 [Idempotência Transacional Persistida]:**
  - A rota `POST /api/spaces/{space}/transfers` exige obrigatoriamente o cabeçalho `Idempotency-Key`.
  - Replay de requisição idêntica com mesma chave e mesmo fingerprint responde `HTTP 200 OK` com `replayed: true` e a representação atualizada da transferência.
  - Replay com chave idêntica mas payload diferente responde `HTTP 409 Conflict`.

- **AC-TRF-008 [Interface Unificada Multiplataforma (iOS, Android e Web)]:**
  - Ação rápida acessível no Dashboard e na aba Carteira de Contas.
  - Formulário acessível com seletores de conta de origem e destino, campo com máscara monetária sem float (`MoneyInputFormatter`), seletor de data e campo de observações opcionais.
  - Responsivo e resiliente a escalas de acessibilidade de 150% e 200% em viewports a partir de 320pt de largura sem overflow visual.

---

## 3. Casos de Borda e Validações

| Cenário de Borda | Entrada | Comportamento Esperado | Código HTTP / Exceção |
| :--- | :--- | :--- | :--- |
| Contas idênticas | `source_account_id == destination_account_id` | Rejeição com mensagem explicativa | `422 Unprocessable Entity` |
| Conta arquivada | Origem ou destino com `archived_at != null` | Rejeição impedindo movimentação | `422 Unprocessable Entity` |
| Conta de outro espaço | ID de conta pertencente a outro `space_id` | Proteção contra IDOR | `404 Not Found` |
| Data pré-abertura | Data anterior ao saldo inicial da conta | Rejeição contábil | `422 Unprocessable Entity` |
| Valor zerado ou negativo | `amount: "0.00"` ou `"-50.00"` | Rejeição de valor inválido | `422 Unprocessable Entity` |
| Replay divergente | Mesma chave com valor ou contas diferentes | Conflito explícito de idempotência | `409 Conflict` |
| Replay idêntico | Mesma chave e mesmo payload | Replay seguro idempotente | `200 OK` (`replayed: true`) |

---

## 4. Matriz de Rastreabilidade (Spec ↔ Código ↔ Testes)

| Critério de Aceite | Implementação (Backend / Mobile) | Testes Automatizados |
| :--- | :--- | :--- |
| **AC-TRF-001** | `apps/api/app/Actions/Transfers/TransferFunds.php`, `apps/api/app/Models/Transfer.php` | `apps/api/tests/Feature/TransfersTest.php` |
| **AC-TRF-002** | `apps/api/app/Actions/Transfers/TransferFunds.php` | `apps/api/tests/Feature/TransfersTest.php` |
| **AC-TRF-003** | `apps/api/app/Actions/Transfers/TransferFunds.php` | `apps/api/tests/Feature/TransfersTest.php` |
| **AC-TRF-004** | `apps/api/app/Http/Controllers/TransferController.php` | `apps/api/tests/Feature/TransfersTest.php` |
| **AC-TRF-005** | `apps/api/app/Actions/Transfers/TransferFunds.php` | `apps/api/tests/Feature/TransfersTest.php` |
| **AC-TRF-006** | `apps/api/app/Actions/Transfers/TransferFunds.php` | `apps/api/tests/Feature/TransfersTest.php` |
| **AC-TRF-007** | `apps/api/app/Actions/Receivables/IdempotentOperations.php` | `apps/api/tests/Feature/TransfersTest.php` |
| **AC-TRF-008** | `apps/mobile/lib/features/transfers/transfer_form_screen.dart` | `apps/mobile/test/features/transfer_form_test.dart` |
