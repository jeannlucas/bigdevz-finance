# BigDev.Z Finance — Transição Operacional (Handoff)

> **Data de Atualização:** 15/11/2026 18:38 (UTC-03:00)  
> **Branch Atual:** `feature/abertura-negativa-e-selecao-conta-baixas` (a partir da `dev`)  
> **Status de Qualidade:** ✅ BACKPRESSURE 100% VERDE (`./scripts/check.sh --full` e `make check`)  
> **Soberania Git:** Commits, pushes e merges aguardando autorização prévia e explícita de Jeann Lucas.

---

## 1. Resumo Executivo das Implementações Concluídas

Foram implementadas as duas melhorias financeiras solicitadas com fidelidade estrita às regras inegociáveis de domínio e UX:

### 1.1. Correção e Cadastro de Abertura de Conta com Valores Negativos (AC-FIN-004)
1. **Banco de Dados PostgreSQL:**
   - Criada migration `2026_11_15_180000_allow_negative_account_opening_balance.php`.
   - Substituídas as restrições `CHECK` que limitavam `>= 0` para `>= -99999999999999` nas tabelas `accounts` e `account_opening_adjustments` (`opening_balance_cents`, `previous_opening_balance_cents`, `new_opening_balance_cents`).
2. **Núcleo de Domínio e Validações PHP:**
   - `Money::toCents(string $decimal, bool $allowNegative = false)`: suporte a valores negativos quando explicitamente habilitado, mantendo a retrocompatibilidade restritiva nos demais fluxos.
   - `MoneyAmount`: suporte ao parâmetro `bool $allowNegative = false`.
   - `AccountController`: suporte a valores negativos nas operações `store` (cadastro) e `adjustOpening` (correção auditada).
   - Teste de domínio PHP `tests/domain.php` expandido com o 15º teste cobrindo valores negativos.
   - Teste de integração `AccountManagementTest.php` cobrindo valores negativos, zero e positivos e o impacto exato no saldo disponível.
3. **Frontend Flutter Mobile e Web:**
   - `Money.fromInput` e `Money.fromSignedInput`: suporte a parsing seguro com sinal.
   - `OpeningAdjustmentScreen`: incorporado seletor visual `SegmentedButton` (`Saldo positivo (+)` vs. `Saldo negativo / devedor (-)`) prevenindo problemas em teclados numéricos mobile que omitem o sinal `-`, calculando o saldo resultante e exibindo na revisão a transição exata (ex.: `R$ 25.000,00 → -R$ 995,98`).
   - Novo teste de widget `opening_adjustment_screen_test.dart` validando o fluxo de ponta a ponta.

### 1.2. Seleção Explícita Obrigatória de Conta Bancária nas Baixas (AC-FIN-024)
1. **Remoção de Pré-seleção Automática:**
   - Em `PayableActionModal` e `BatchPayableModal` (contas a pagar), `AgreementActionModal` (recebíveis) e telas de formulário `PaymentFormScreen` e `ReceiptFormScreen`, a conta bancária inicia desmarcada (`_selectedAccountId = null`), exibindo o hint `"Selecione uma conta"`.
   - Elimina qualquer risco de débito ou crédito acidental na conta errada por desatenção do gestor.
2. **Validação Obrigatória com Mensagem Clara:**
   - A confirmação sem conta é barrada de imediato com mensagens de validação orientativas (`"Selecione uma conta bancária para debitar o pagamento."` / `"Selecione uma conta bancária de destino para o recebimento."`).
   - `DropdownButtonFormField` configurado com `isExpanded: true` eliminando qualquer overflow visual em dispositivos estreitos.
   - Comportamento idêntico e consistente em liquidações individuais e em lote, inclusive quando há apenas uma conta cadastrada.

---

## 2. Resultado do Backpressure Determinístico (`./scripts/check.sh --full`)

- **[1/4] Análise Estática e Tipagem:**
  - Domínio Financeiro PHP: 15 testes puros de centavos e limites (0 falhas).
  - Análise Estática Dart (`flutter analyze`): **No issues found!** (ran in 2.4s).
- **[2/4] Linters e Formatação:**
  - Laravel Pint (`apps/api`): 162 arquivos conformes (PASS).
  - Formatação Dart (`apps/mobile`): 160 arquivos formatados segundo os padrões oficiais.
- **[3/4] Testes de Domínio e Unidade:**
  - Suíte Flutter (`apps/mobile`): **310 testes aprovados (0 falhas)**.
- **[4/4] Suíte de Integração Laravel com PostgreSQL real (`apps/api`):**
  - **196 testes aprovados (1846 asserções, 0 falhas)** em banco de teste descartável homologado.

---

## 3. Evidências Visuais Geradas (Chrome DevTools MCP)

1. `screenshot_abertura_negativa.png`: Tela de correção de abertura com o seletor `Saldo negativo / devedor (-)` ativo, prefixo `-R$` e valor `-995,98` preenchido.
2. `screenshot_revisao_abertura_negativa.png`: Revisão executiva com transição auditada de saldo inicial e cálculo do saldo resultante devedor.
3. `screenshot_validacao_selecao_conta.png`: Modal de baixa com campo de conta iniciando em `"Selecione uma conta"`, barrando confirmação com `"Selecione uma conta bancária para debitar o pagamento."`.
4. `screenshot_menu_contas_aberto.png`: Menu suspenso exibindo as contas ativas do espaço (`ITAÚ PERSONALITÉ` e `NUBANK PRINCIPAL`).
5. `screenshot_conta_selecionada_pronta.png`: Modal pronto para confirmação após seleção consciente da conta bancária.

---

## 4. Próximos Passos Imediatos

1. Apresentar o relatório final estruturado a Jeann Lucas para revisão.
2. Mediante autorização explícita, commitar na branch `feature/abertura-negativa-e-selecao-conta-baixas`.
3. Executar o merge local na branch `dev`, rodar o Quality Gate integrado e publicar via `git push origin dev`.
