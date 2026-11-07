# Especificação Permanente da Capability Extrato (Extrato Unificado & UX Desktop)

> **Capability:** `extrato`<br>
> **Status:** Ativo / Canônico<br>
> **Referência de Governança:** `AGENTS.md`, `specs/README.md`, `docs/project-guidelines.md`<br>
> **Regra de Ouro:** O código e os testes respondem a esta especificação; qualquer divergência (*drift*) é considerada defeito de primeira classe.

---

## 1. Visão Geral da Capability

A capability **Extrato** consolida a visão temporal unificada de todos os lançamentos financeiros liquidados (`AccountMovement`) das contas bancárias de um espaço financeiro (PF ou PJ). Ela fornece aos usuários e aos sistemas clientes uma trilha contábil auditável e cronológica (entradas de recebimentos, saídas de pagamentos, transferências entre contas, estornos compensatórios e desembolsos de empréstimos), acompanhada de um layout responsivo profissional no Flutter com Sidebar lateral adaptativa para telas desktop e web amplas.

---

## 2. Critérios de Aceite Numerados (AC-EXT)

### 2.1. Consulta Contábil e Linha do Tempo

- **AC-EXT-001 [Ordenação Cronológica e Consolidação]:**
  - O endpoint de extrato (`GET /api/spaces/{space}/statement` ou `movements`) deve retornar todas as movimentações efetivadas de contas pertencentes ao espaço autenticado em ordem cronológica decrescente (`effective_date DESC, id DESC`).
  - O saldo inicial histórico não é uma movimentação diária, mas as movimentações refletem rigorosamente o fluxo de caixa liquidado.

- **AC-EXT-002 [Classificação Semântica e Metadados do Lançamento]:**
  - Cada item do extrato deve ser classificado deterministicamente entre entrada (`credit` / `in`) ou saída (`debit` / `out`):
    - Recebimento (`receipt_id`): `credit` (verde, valor positivo).
    - Estorno de Recebimento (`receipt_reversal_id`): `debit` (vermelho, saída compensatória).
    - Pagamento (`payment_id`): `debit` (vermelho, saída).
    - Estorno de Pagamento (`payment_reversal_id`): `credit` (verde, entrada compensatória).
    - Transferência (`transfer_id`):
      - Se a conta da movimentação for a de origem (`source_account_id`): `debit` (saída por transferência).
      - Se a conta for a de destino (`destination_account_id`): `credit` (entrada por transferência).
    - Desembolso de Empréstimo (`loan_disbursement_id`):
      - Empréstimo tomado (`type == taken`): `credit` (entrada de capital desembolsado).
      - Empréstimo concedido (`type == granted`): `debit` (saída de capital emprestado).
  - Cada item deve conter: `id`, `account_id`, `account_name`, `effective_date` (`YYYY-MM-DD`), `amount` (string decimal canônica), `direction` (`credit` ou `debit`), `category_label` ou `description` amigável da operação.

- **AC-EXT-003 [Filtros de Consulta na API]:**
  - Suporte a filtros opcionais via query parameters:
    - `account_id`: filtra exclusivamente as movimentações daquela conta bancária (validando pertencimento ao espaço ativo).
    - `from` e `to`: intervalo de datas efetivas (`YYYY-MM-DD`).
    - `direction`: `credit` ou `debit` para filtrar somente entradas ou saídas.

---

### 2.2. Isolamento, Segurança e Integridade Monetária

- **AC-EXT-004 [Isolamento Multi-Tenant e Prevenção IDOR]:**
  - O extrato opera estritamente sob o espaço resolvido do usuário autenticado: `$request->user()->spaces()->findOrFail($spaceId)`.
  - Se for fornecido `account_id` que pertença a outro espaço ou outro usuário, a resposta DEVE ser estritamente `404 Not Found`.

- **AC-EXT-005 [Valores Monetários Exatos e Sem Float]:**
  - Todos os valores transitam como strings decimais canônicas com duas casas decimais (`"1500.00"`). É proibido o uso de números de ponto flutuante.

---

### 2.3. Interface de Usuário e UX Desktop

- **AC-EXT-006 [Layout Adaptativo Web/Desktop com Sidebar Lateral]:**
  - Em viewports com largura $\ge 840$pt (monitores, computadores, tablets em modo paisagem):
    - O aplicativo exibe uma Sidebar lateral moderna (`NavigationRail` ou painel fintech dedicado) com a logo da BigDev.Z, seletor de espaço PF/PJ, itens de navegação (Resumo, Extrato, A Receber, A Pagar, Contas, Empréstimos), atalho de configurações e perfil/logout.
    - A área principal de conteúdo expande-se de forma fluida com container responsivo centralizado de até 1200px.
  - Em viewports com largura $< 840$pt (mobile):
    - O aplicativo mantém a experiência compacta com `BottomNavigationBar` e cabeçalho otimizado.

- **AC-EXT-007 [Privacidade Financeira e Acessibilidade no Extrato]:**
  - A tela de Extrato escuta `PreferencesController.obscureValues`. Quando ativado, os valores das movimentações são mascarados (`R$ ••••••••`) com rótulos semânticos acessíveis.
  - O layout suporta escalas de texto de até 200% sem overflow.

---

## 3. Matriz de Rastreabilidade (Spec ↔ Código ↔ Testes)

| Critério | Implementação Backend / Mobile | Testes Automatizados |
| :--- | :--- | :--- |
| **AC-EXT-001** | `StatementController.php`, `AccountMovement.php` | `StatementTest.php` |
| **AC-EXT-002** | `StatementResource.php`, `statement_entry.dart` | `StatementTest.php`, `statement_test.dart` |
| **AC-EXT-003** | `StatementController.php` (filtros de query) | `StatementTest.php` |
| **AC-EXT-004** | `StatementController.php` (`findOrFail` no space) | `StatementTest.php` |
| **AC-EXT-005** | `Money::fromCents`, `Money.parse` | `StatementTest.php`, `money_test.dart` |
| **AC-EXT-006** | `home_shell.dart`, `app_sidebar.dart` | `home_shell_test.dart` |
| **AC-EXT-007** | `statement_screen.dart`, `preferences_controller.dart` | `statement_screen_test.dart` |
