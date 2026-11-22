# Especificação Permanente da Capability de Transferências (Transferências entre Contas e entre Espaços)

> **Capability:** `transferencias`<br>
> **Status:** Ativo / Canônico<br>
> **Referência de Governança:** `~/AGENTS.md`, `specs/README.md`, `specs/financeiro/financeiro.md`, ADRs `0001` a `0006`.<br>
> **Regra de Ouro:** O código e os testes respondem a esta especificação; qualquer divergência (*drift*) é considerada defeito de primeira classe.

---

## 1. Visão Geral da Capability

A capability **Transferências entre Contas e entre Espaços** viabiliza a movimentação de recursos financeiros tanto entre contas patrimoniais do mesmo espaço (PF ou PJ) quanto entre espaços distintos aos quais o usuário autenticado possua acesso e autorização (ex.: da conta PJ para a conta PF como reembolso, ou da PF para a PJ como aporte/integralização). A operação garante integridade contábil estrita através de lançamentos espelhados no livro razão (`account_movements`), concorrência segura protegida contra *deadlocks* via ordenação de chaves primárias de contas, persistência idempotente e estorno coordenado bilateral.

A funcionalidade tem natureza contábil e de registro: reflete movimentações efetivamente realizadas pelo usuário fora do sistema (ex.: via Pix ou TED bancário externo), deixando explícito ao usuário que o aplicativo não executa transações bancárias. A transferência entre espaços é tratada estritamente como movimentação entre contas patrimoniais, sem gerar automaticamente receitas ou despesas artificiais.

---

## 2. Critérios de Aceite Numerados (AC-TRF)

### 2.1. Regras Fundamentais e Invariantes Contábeis

- **AC-TRF-001 [Atomicidade e Movimentações Espelhadas]:**
  - A transferência gera obrigatoriamente um registro principal na tabela `transfers` (`space_id`, `destination_space_id`, `source_account_id`, `destination_account_id`, `amount_cents`, `transferred_at`, `notes`, `user_id`).
  - Gera simultaneamente exatamente 2 registros no livro contábil `account_movements` na mesma transação atômica do banco:
    1. Saída na conta de origem: `amount_cents = -valor`
    2. Entrada na conta de destino: `amount_cents = +valor`
  - Ambos os registros de movimentação associam-se à chave estrangeira `transfer_id` e à mesma data contábil (`effective_date = transferred_at`).
  - A operação é estritamente atômica: se qualquer validação falhar, nenhuma alteração em tabelas ou saldos é persistida (rollback integral, sem lançamentos parciais).

- **AC-TRF-002 [Prevenção Determinística de Deadlock sob Concorrência]:**
  - Ambas as contas envolvidas (origem e destino) são bloqueadas sob lock pessimista (`lockForUpdate()`) antes de qualquer mutação.
  - Para evitar travamento mútuo (*deadlock*) em transferências simultâneas de A para B e de B para A, o bloqueio das contas ocorre estritamente em ordem crescente de seus identificadores numéricos: `id_menor = min(source_id, destination_id)` seguido por `id_maior = max(source_id, destination_id)`, mesmo que pertençam a espaços distintos.

- **AC-TRF-003 [Contas Distintas e Validação de Contas]:**
  - A conta de origem e a conta de destino não podem ser a mesma entidade (`source_account_id !== destination_account_id`). Tentativa de transferir para a mesma conta resulta em `422 Unprocessable Entity`.
  - Nenhuma das contas envolvidas pode estar arquivada (`archived_at !== null`). Caso qualquer uma esteja arquivada, a operação é rejeitada com `422 Unprocessable Entity`.

---

### 2.2. Isolamento, Segurança e Marco Temporal

- **AC-TRF-004 [Isolamento Multi-Tenant Estrito e Prevenção IDOR]:**
  - A conta de origem deve obrigatoriamente pertencer ao `space_id` de origem, e a conta de destino deve pertencer ao `destination_space_id`.
  - Se o usuário autenticado não possuir acesso a qualquer um dos espaços envolvidos ou se qualquer das contas pertencer a outro espaço/usuário, a API responde `404 Not Found` imediato, sem vazar a existência do recurso.

- **AC-TRF-005 [Marco Temporal de Abertura de Conta e Fechamento Contábil]:**
  - A data da transferência (`transferred_at`) não pode ser anterior à data de abertura (`opening_balance_date`) de nenhuma das duas contas envolvidas.
  - Se `transferred_at < source_account.opening_balance_date` ou `transferred_at < destination_account.opening_balance_date`, a operação é rejeitada com `422 Unprocessable Entity`.
  - A data da transferência não pode recair em período contábil fechado em nenhum dos dois espaços (`ensureDateNotClosed`), sob pena de `422 Unprocessable Entity`.

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

- **AC-TRF-008 [Interface Unificada via Navegador (Desktop e Mobile Web)]:**
  - O formulário de transferência adapta-se dinamicamente ao formato de tela do navegador (widescreen desktop e smartphone mobile web). A distribuição em lojas de aplicativos nativas está congelada (ADR 0007).
  - Ação rápida acessível no Dashboard e na aba Carteira de Contas.
  - Formulário acessível com seletores de conta de origem e destino, campo com máscara monetária sem float (`MoneyInputFormatter`), seletor de data e campo de observações opcionais.
  - Responsivo e resiliente a escalas de acessibilidade de 150% e 200% em viewports a partir de 320pt de largura sem overflow visual.

---

### 2.5. Transferências Entre Espaços Distintos e Estorno Coordenado

- **AC-TRF-009 [Transferência Entre Espaços Distintos (Cross-Space Transfer - PJ ↔ PF)]:**
  - Suporte formal para transferências onde `space_id != destination_space_id` (ex.: da PJ para a PF ou da PF para a PJ).
  - A tabela `transfers` armazena `space_id` (origem) e `destination_space_id` (destino). Chaves estrangeiras compostas garantem no banco que a conta de origem pertence ao espaço de origem e a de destino ao de destino.
  - A saída reflete no extrato e saldo do espaço de origem; a entrada reflete no extrato e saldo do espaço de destino.
  - Ambas as movimentações contábeis permanecem vinculadas ao mesmo `transfer_id`.
  - A listagem de transferências de cada espaço exibe transferências originadas nele ou destinadas a ele (`where space_id = ? OR destination_space_id = ?`).
  - O extrato de cada espaço identifica explicitamente o caráter entre espaços da operação (ex.: "Transferência para Conta PF (Pessoal)" ou "Transferência de Conta PJ (Empresa)") e preserva a finalidade informada.

- **AC-TRF-010 [Validação de Acesso e Permissões Multi-Espaço (RBAC e Prevenção IDOR)]:**
  - O usuário autenticado deve ter acesso aos dois espaços (origem e destino) e possuir o privilégio `transfer_funds` em ambos.
  - Perfis sem permissão de movimentação financeira (ex.: `contador`) são barrados com `403 Forbidden`.
  - Tentativa de usar espaço ou conta inacessível responde `404 Not Found` sem vazar a existência do recurso.

- **AC-TRF-011 [Estorno Coordenado e Bilateral de Transferências (Transfer Reversal)]:**
  - Permite o estorno bilateral de uma transferência através de `POST /api/spaces/{space}/transfers/{transfer}/reversal` com cabeçalho `Idempotency-Key` e motivo (`reason` entre 3 e 500 caracteres).
  - Em conformidade com a imutabilidade contábil, a transferência original e seus registros em `account_movements` são preservados intactos.
  - Gera um registro em `transfer_reversals` e exatamente duas contra-movimentações compensatórias em `account_movements` vinculadas a `transfer_reversal_id`:
    1. Crédito na conta de origem: `amount_cents = +valor`
    2. Débito na conta de destino: `amount_cents = -valor`
  - A data contábil efetiva da compensação é a mesma da transferência original (`effective_date = transferred_at`).
  - Apenas perfis autorizados (`administrador` e `financeiro`) podem estornar transferências; `operador` e `contador` são barrados com `403 Forbidden`.
  - Uma transferência já estornada não pode ser estornada novamente (`422 Unprocessable Entity`).
  - O estorno é atômico e protegido contra deadlocks com bloqueio ordenado de contas por ID.

- **AC-TRF-012 [Experiência e Transparência de Interface Multiplataforma]:**
  - A interface disponibiliza seletores explícitos de espaço e conta tanto para a origem quanto para o destino.
  - Nenhuma conta bancária é pré-selecionada automaticamente, exigindo escolha consciente do usuário para prevenir desvios acidentais de saldo.
  - O formulário exibe aviso claro e destacado: "Este registro atualiza os saldos e extratos no BigDev.Z Finance. Ele não executa a transação bancária (Pix/TED) no seu banco."
  - Seletor de espaço exibe apenas os espaços aos quais o usuário tem acesso e permissão de movimentação.
  - Layout ergonômico no Desktop Web (centralizado, largura máxima controlada, modais executivos) e no Mobile (BottomSheet responsivo, toque acessível).

- **AC-TRF-013 [Comportamento Inicial do Formulário e Revisão Detalhada Prévia]:**
  - Ao abrir o formulário no espaço Pessoa Física, preenche o espaço de origem com a Pessoa Física ativa.
  - Ao abrir no espaço Pessoa Jurídica, preenche o espaço de origem com a Pessoa Jurídica ativa.
  - Nenhuma conta bancária (origem ou destino) inicia pré-selecionada (`null` com hint explicativo), prevenindo qualquer movimentação involuntária.
  - A troca do espaço de origem limpa imediatamente qualquer conta de origem previamente selecionada, impedindo associação cruzada inconsistente.
  - A troca do espaço de destino limpa imediatamente qualquer conta de destino previamente selecionada.
  - Antes da gravação definitiva, é apresentada uma tela/etapa de revisão com double-check destacando com máxima clareza: Espaço e Conta de Origem, Espaço e Conta de Destino, tipo de movimentação (interna ou entre espaços), impacto contábil nos saldos, valor monetário exato e data, permitindo ao gestor "Voltar e editar" ou "Confirmar transferência".

---

## 3. Casos de Borda e Validações

| Cenário de Borda | Entrada | Comportamento Esperado | Código HTTP / Exceção |
| :--- | :--- | :--- | :--- |
| Contas idênticas | `source_account_id == destination_account_id` | Rejeição com mensagem explicativa | `422 Unprocessable Entity` |
| Conta arquivada | Origem ou destino com `archived_at != null` | Rejeição impedindo movimentação | `422 Unprocessable Entity` |
| Conta de outro espaço / IDOR | ID de conta que não pertence ao respectivo espaço | Proteção contra IDOR | `404 Not Found` |
| Espaço destino não autorizado | `destination_space_id` sem associação com usuário | Proteção contra IDOR | `404 Not Found` |
| Perfil sem permissão (ex: contador) | Tentativa de transferir fundos | Bloqueio RBAC | `403 Forbidden` |
| Período contábil fechado | Data em mês/ano fechado na origem ou destino | Rejeição contábil | `422 Unprocessable Entity` |
| Data pré-abertura | Data anterior ao saldo inicial da conta | Rejeição contábil | `422 Unprocessable Entity` |
| Valor zerado ou negativo | `amount: "0.00"` ou `"-50.00"` | Rejeição de valor inválido | `422 Unprocessable Entity` |
| Replay divergente | Mesma chave com valor ou contas diferentes | Conflito explícito de idempotência | `409 Conflict` |
| Replay idêntico | Mesma chave e mesmo payload | Replay seguro idempotente | `200 OK` (`replayed: true`) |
| Estorno de transferência já estornada | Transferência já possui `transfer_reversals` | Bloqueio de duplicidade | `422 Unprocessable Entity` |
| Estorno por operador | Perfil `operador` tentando estornar | Bloqueio RBAC | `403 Forbidden` |

---

## 4. Matriz de Rastreabilidade (Spec ↔ Código ↔ Testes)

| Critério de Aceite | Implementação (Backend / Mobile) | Testes Automatizados |
| :--- | :--- | :--- |
| **AC-TRF-001** | `apps/api/app/Actions/Transfers/TransferFunds.php`, `apps/api/app/Models/Transfer.php` | `apps/api/tests/Feature/TransfersTest.php` |
| **AC-TRF-002** | `apps/api/app/Actions/Transfers/TransferFunds.php` | `apps/api/tests/Feature/TransfersTest.php` |
| **AC-TRF-003** | `apps/api/app/Actions/Transfers/TransferFunds.php` | `apps/api/tests/Feature/TransfersTest.php` |
| **AC-TRF-004** | `apps/api/app/Http/Controllers/Api/TransferController.php` | `apps/api/tests/Feature/TransfersTest.php` |
| **AC-TRF-005** | `apps/api/app/Actions/Transfers/TransferFunds.php` | `apps/api/tests/Feature/TransfersTest.php` |
| **AC-TRF-006** | `apps/api/app/Actions/Transfers/TransferFunds.php` | `apps/api/tests/Feature/TransfersTest.php` |
| **AC-TRF-007** | `apps/api/app/Actions/Receivables/IdempotentOperations.php` | `apps/api/tests/Feature/TransfersTest.php` |
| **AC-TRF-008** | `apps/mobile/lib/features/transfers/transfer_form_screen.dart` | `apps/mobile/test/features/transfer_form_test.dart` |
| **AC-TRF-009** | `apps/api/app/Actions/Transfers/TransferFunds.php`, `apps/api/app/Http/Resources/TransferResource.php`, `StatementResource.php` | `apps/api/tests/Feature/CrossSpaceTransfersTest.php`, `TransfersTest.php` |
| **AC-TRF-010** | `apps/api/app/Http/Controllers/Api/TransferController.php`, `TransferFunds.php`, `Space.php` | `apps/api/tests/Feature/CrossSpaceTransfersTest.php` |
| **AC-TRF-011** | `apps/api/app/Actions/Transfers/ReverseTransfer.php`, `apps/api/app/Models/TransferReversal.php` | `apps/api/tests/Feature/CrossSpaceTransfersTest.php` |
| **AC-TRF-012** | `apps/mobile/lib/features/transfers/transfer_form_screen.dart`, `accounts_repository.dart` | `apps/mobile/test/features/transfer_form_test.dart` |
| **AC-TRF-013** | `apps/mobile/lib/features/transfers/transfer_form_screen.dart`, `accounts_tab.dart` | `apps/mobile/test/features/transfer_form_test.dart` |
